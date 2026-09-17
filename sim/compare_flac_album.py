#!/usr/bin/env python3
"""Generate a real two-track CUESHEET FLAC and verify album RTL navigation."""

import math
import struct
import subprocess
import tempfile
import wave
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="mister_mp3_album_") as directory:
        temp = Path(directory)
        wav_path = temp / "album.wav"
        cue_path = temp / "album.cue"
        flac_path = temp / "album.flac"
        hex_path = temp / "album.hex"

        with wave.open(str(wav_path), "wb") as output:
            output.setparams((2, 2, 44100, 88200, "NONE", "not compressed"))
            for sample in range(88200):
                value = round(12000 * math.sin(2 * math.pi * 440 * sample / 44100))
                output.writeframesraw(struct.pack("<hh", value, value))
        cue_path.write_text(
            'FILE "album.wav" WAVE\n'
            '  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n'
            '  TRACK 02 AUDIO\n    INDEX 01 00:01:00\n',
            encoding="ascii",
        )
        subprocess.run([
            "flac", "-f", "-s", "-8", "--seekpoint=20x",
            f"--cuesheet={cue_path}", "-o", str(flac_path), str(wav_path),
        ], check=True)
        subprocess.run([
            "python3", str(REPO / "tools/mp3_to_hex.py"), str(flac_path), str(hex_path)
        ], check=True)
        size = flac_path.stat().st_size
        simulation = temp / "album_tb.out"
        subprocess.run([
            "iverilog", "-g2012", "-o", str(simulation),
            f'-Pflac_album_control_tb.HEX_FILE="{hex_path}"',
            f"-Pflac_album_control_tb.FILE_BYTES={size}",
            str(REPO / "sim/flac_album_control_tb.sv"),
            str(REPO / "rtl/audio/flac/flac_album_control.sv"),
            str(REPO / "rtl/media_ui_divider.sv"),
        ], check=True)
        result = subprocess.run(["vvp", str(simulation)], check=False, text=True, capture_output=True)
        print(result.stdout, end="")
        return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
