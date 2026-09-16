#!/usr/bin/env python3
"""Validates mp3_stereo's intensity-stereo path (mode_extension 1 or 3)
against tools/mp3_stereo_reference.py's compute_stereo_fixed(), using the
same synthetic scenario sim/mp3_stereo_unit_tb.sv drives directly into the
RTL: real LAME output never sets the intensity-stereo mode_ext bit, so
there is no real bitstream to test this path against (see docs/MP3.md and
the testbench's own header comment for how the stimulus files under /tmp
were captured from a real, patched FFmpeg build).

Not bit-exact by construction here: FFmpeg's own compute_stereo() (the
ground truth for the *stimulus*) and this project's fixed-point
compute_stereo_fixed() (the ground truth for *this* comparison) use
different internal rounding conventions, already shown to differ by at
most +/-1 ULP on this exact scenario. What this script checks is RTL vs.
Python reference exact match -- both implement the identical fixed-point
algorithm, so there is no ambiguity at *this* layer, same as
compare_stereo.py's real-file checks.

Usage: compare_stereo_unit.py
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from mp3_stereo_reference import compute_stereo_fixed  # noqa: E402


def run_sim():
    sim_bin = "/tmp/_cmp_st_unit.out"
    subprocess.run(
        [
            "iverilog", "-g2012", "-o", sim_bin,
            str(REPO / "sim/mp3_stereo_unit_tb.sv"),
            str(REPO / "rtl/mp3_stereo.sv"),
        ],
        check=True,
    )
    return subprocess.run(["vvp", sim_bin], capture_output=True, text=True, timeout=60, check=True).stdout


def parse_sim(text):
    results = {0: {}, 1: {}}
    for line in text.splitlines():
        m = re.match(r"ST gci=(\d) idx=(\d+) data=(-?\d+)", line)
        if m:
            gci, i, d = int(m[1]), int(m[2]), int(m[3])
            results[gci][i] = d
    return [results[0].get(i) for i in range(576)], [results[1].get(i) for i in range(576)]


def main():
    ch0 = [int(x) for x in open("/tmp/inj_ch0.txt").read().split()]
    ch1 = [int(x) for x in open("/tmp/inj_ch1.txt").read().split()]
    sf1_22 = [int(x) for x in open("/tmp/inj_sf1.txt").read().split()]
    sf1 = sf1_22 + [0] * (40 - len(sf1_22))

    # block_type=1 ("start"), mixed_block_flag=0 -- window-switched but
    # treated as all-long, matching the testbench's side-info stimulus.
    ref0, ref1 = compute_stereo_fixed(ch0, ch1, sf1, 1, 0, 44100, 3)

    sim_out = run_sim()
    sim0, sim1 = parse_sim(sim_out)

    mismatches = 0
    if sim0 != ref0:
        first_diff = next((i for i, (a, b) in enumerate(zip(sim0, ref0)) if a != b), None)
        print(f"ch0 mismatch at index {first_diff}: ref={ref0[first_diff]} sim={sim0[first_diff]}")
        mismatches += 1
    if sim1 != ref1:
        first_diff = next((i for i, (a, b) in enumerate(zip(sim1, ref1)) if a != b), None)
        print(f"ch1 mismatch at index {first_diff}: ref={ref1[first_diff]} sim={sim1[first_diff]}")
        mismatches += 1

    if mismatches == 0:
        print("synthetic intensity-stereo scenario: RTL matches mp3_stereo_reference.py exactly (all 1152 values)")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
