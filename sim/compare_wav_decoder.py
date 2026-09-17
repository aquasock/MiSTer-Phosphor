#!/usr/bin/env python3
"""Cross-check the wav_decoder RTL simulation output against Python's
stdlib `wave` module (an independent, mature reference -- not code sharing
any logic with rtl/wav_decoder.sv's own RIFF chunk-walking) for one test
file.

Usage: compare_wav_decoder.py test_vectors/stereo_44100.wav
"""
import re
import subprocess
import sys
import wave
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def run_reference(wav_path: str):
    with wave.open(wav_path, "rb") as w:
        assert w.getnchannels() == 2, f"expected stereo, got {w.getnchannels()} channels"
        assert w.getsampwidth() == 2, f"expected 16-bit, got {w.getsampwidth()*8}-bit"
        frames = w.readframes(w.getnframes())
    samples = []
    for i in range(0, len(frames), 4):
        left = int.from_bytes(frames[i:i + 2], "little", signed=True)
        right = int.from_bytes(frames[i + 2:i + 4], "little", signed=True)
        samples.append((left, right))
    return samples


def run_sim(wav_path: str) -> str:
    hex_path = "/tmp/_cmp_wav.hex"
    subprocess.run(["python3", str(REPO / "tools/mp3_to_hex.py"), wav_path, hex_path], check=True)
    sim_bin = "/tmp/_cmp_wav_tb.out"
    subprocess.run(
        [
            "iverilog", "-g2012", "-o", sim_bin,
            f"-Pwav_decoder_tb.HEX_FILE=\"{hex_path}\"",
            str(REPO / "sim/wav_decoder_tb.sv"),
            str(REPO / "rtl/wav_decoder.sv"),
        ],
        check=True,
    )
    return subprocess.run(["vvp", sim_bin], capture_output=True, text=True, check=True).stdout


def parse_sim_output(text: str):
    samples = []
    saw_eof_at = None
    for line in text.splitlines():
        m = re.match(r"PCM idx=(\d+) left=(-?\d+) right=(-?\d+) eof=(\d)", line)
        if m:
            idx, left, right, eof = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
            samples.append((left, right))
            if eof:
                saw_eof_at = idx
        if "TIMEOUT" in line:
            print(line)
    return samples, saw_eof_at


def compare(wav_path: str) -> int:
    ref = run_reference(wav_path)
    sim_out = run_sim(wav_path)
    sim_samples, eof_idx = parse_sim_output(sim_out)

    mismatches = 0
    if len(sim_samples) != len(ref):
        print(f"sample count mismatch: ref={len(ref)} sim={len(sim_samples)}")
        mismatches += 1
    if eof_idx is not None and eof_idx != len(ref) - 1:
        print(f"eof flagged at wrong sample: got idx={eof_idx}, expected {len(ref) - 1}")
        mismatches += 1
    elif eof_idx is None:
        print("eof never flagged")
        mismatches += 1

    for i, ((rl, rr), (sl, sr)) in enumerate(zip(ref, sim_samples)):
        if rl != sl or rr != sr:
            print(f"sample {i}: ref=({rl},{rr}) sim=({sl},{sr})")
            mismatches += 1
            if mismatches > 20:
                print("... too many mismatches, stopping")
                break

    if mismatches == 0:
        print(f"{wav_path}: {len(ref)} samples, all match exactly, eof correct")
        return 0
    print(f"{wav_path}: {mismatches} mismatches")
    return 1


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    return compare(sys.argv[1])


if __name__ == "__main__":
    sys.exit(main())
