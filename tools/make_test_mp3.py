#!/usr/bin/env python3
"""Generate deterministic CBR MP3 test vectors covering this project's
entire accepted profile: {128, 192} kb/s x {44100, 48000, 32000} Hz x
{mono, stereo}.

Self-contained -- synthesizes test tones via ffmpeg's lavfi sine source
rather than depending on external sample audio, so the output is
reproducible from a clean checkout. Stereo files use two different
frequencies on left/right so channel separation is verifiable later just
by listening to (or analyzing) the decoded output.

Requires ffmpeg with libmp3lame. Run with no arguments; output goes to
test_vectors/ (gitignored, regenerate any time).
"""
import subprocess
import sys
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "test_vectors"
DURATION_SEC = 5
BITRATES_KBPS = (128, 192)
SAMPLE_RATES_HZ = (44100, 48000, 32000)


def make_mono(path: Path, sample_rate: int, bitrate_kbps: int) -> None:
    subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", f"sine=frequency=440:sample_rate={sample_rate}:duration={DURATION_SEC}",
            "-c:a", "libmp3lame", "-b:a", f"{bitrate_kbps}k",
            "-ar", str(sample_rate), "-ac", "1",
            str(path),
        ],
        check=True,
    )


def make_stereo(path: Path, sample_rate: int, bitrate_kbps: int) -> None:
    subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", f"sine=frequency=440:sample_rate={sample_rate}:duration={DURATION_SEC}",
            "-f", "lavfi", "-i", f"sine=frequency=880:sample_rate={sample_rate}:duration={DURATION_SEC}",
            "-filter_complex", "[0:a][1:a]join=inputs=2:channel_layout=stereo[a]",
            "-map", "[a]",
            "-c:a", "libmp3lame", "-b:a", f"{bitrate_kbps}k",
            "-ar", str(sample_rate), "-ac", "2",
            str(path),
        ],
        check=True,
    )


def main() -> int:
    OUT_DIR.mkdir(exist_ok=True)
    for sample_rate in SAMPLE_RATES_HZ:
        for bitrate_kbps in BITRATES_KBPS:
            mono_path = OUT_DIR / f"mono_{bitrate_kbps}k_{sample_rate}.mp3"
            stereo_path = OUT_DIR / f"stereo_{bitrate_kbps}k_{sample_rate}.mp3"
            print(f"generating {mono_path.name}")
            make_mono(mono_path, sample_rate, bitrate_kbps)
            print(f"generating {stereo_path.name}")
            make_stereo(stereo_path, sample_rate, bitrate_kbps)
    print(f"done -- {2 * len(BITRATES_KBPS) * len(SAMPLE_RATES_HZ)} files in {OUT_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
