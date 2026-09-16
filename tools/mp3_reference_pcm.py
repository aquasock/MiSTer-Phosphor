#!/usr/bin/env python3
"""Reference-decoder tooling for validating the FPGA decoder's output.

decode:  extract ground-truth PCM from an MP3 via ffmpeg's own decoder, as
         signed 16-bit little-endian raw samples at the source file's
         native channel count -- the same representation hardware output
         should be captured in for comparison.

compare: sample-accurate diff between two raw PCM files (e.g. the ffmpeg
         reference vs. a captured FPGA output dump). Reports first
         mismatching sample and peak absolute difference; does not assume
         the two files are the same decoder's output, so an occasional
         +/-1 LSB rounding difference is expected and reported, not fatal.

Usage:
    mp3_reference_pcm.py decode input.mp3 output.pcm
    mp3_reference_pcm.py compare reference.pcm candidate.pcm
"""
import struct
import subprocess
import sys


def decode(mp3_path: str, pcm_path: str) -> int:
    subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-y", "-loglevel", "error",
            "-i", mp3_path,
            "-f", "s16le", "-acodec", "pcm_s16le",
            pcm_path,
        ],
        check=True,
    )
    return 0


def compare(reference_path: str, candidate_path: str) -> int:
    ref = open(reference_path, "rb").read()
    cand = open(candidate_path, "rb").read()

    if len(ref) != len(cand):
        print(f"length mismatch: reference={len(ref)} bytes, candidate={len(cand)} bytes")

    n_samples = min(len(ref), len(cand)) // 2
    ref_samples = struct.unpack(f"<{n_samples}h", ref[: n_samples * 2])
    cand_samples = struct.unpack(f"<{n_samples}h", cand[: n_samples * 2])

    first_mismatch = None
    peak_diff = 0
    for i, (r, c) in enumerate(zip(ref_samples, cand_samples)):
        diff = abs(r - c)
        if diff:
            if first_mismatch is None:
                first_mismatch = i
            peak_diff = max(peak_diff, diff)

    if first_mismatch is None:
        print(f"exact match over {n_samples} samples")
        return 0

    print(f"first mismatch at sample {first_mismatch}, peak absolute difference {peak_diff} LSB")
    return 1


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    mode = sys.argv[1]
    if mode == "decode" and len(sys.argv) == 4:
        return decode(sys.argv[2], sys.argv[3])
    if mode == "compare" and len(sys.argv) == 4:
        return compare(sys.argv[2], sys.argv[3])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
