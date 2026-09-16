#!/usr/bin/env python3
"""Cross-check mp3_synthesis (the full frame_parser -> bit_reservoir ->
huffman_decoder -> dequant -> stereo -> antialias -> imdct -> synthesis
chain) against tools/mp3_synthesis_reference.py's synthesize_timeslot(),
built on top of the already-validated compare_imdct.py's run_reference()
output. Bit-exact by construction: RTL and Python reference implement the
identical fixed-point algorithm (unlike the cross-check against real
FFmpeg output used to validate the algorithm/scale choices themselves in
the first place -- see tools/mp3_synthesis_reference.py's module
docstring -- which only needed to land within +/-1 LSB, an FFmpeg
internal-rounding-convention difference, not a bug).

The 1024-entry-per-channel V history is genuinely PERSISTENT across
granules and frames (the second such state in this project, after
mp3_imdct's overlap_mem) -- this script tracks it exactly once, across
the whole run, starting from all zeros (matching the RTL's reset state),
never reset per-frame.

Usage: compare_synthesis.py test_vectors/stereo_128k_44100.mp3 [num_frames]
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
sys.path.insert(0, str(REPO / "sim"))
import compare_imdct as CI  # noqa: E402
from mp3_synthesis_reference import SynthesisState, synthesize_timeslot, clip_int16  # noqa: E402

NUM_CH = 2


def run_reference(mp3_path, num_frames):
    imdct_results = CI.run_reference(mp3_path, num_frames)  # (fi, gci) -> 576 time-major values

    states = [SynthesisState() for _ in range(NUM_CH)]
    results = {}
    for (fi, gci) in sorted(imdct_results.keys()):
        arr = imdct_results[(fi, gci)]
        channel = gci & 1
        flat = []
        for t in range(18):
            S = arr[t * 32:(t + 1) * 32]
            out = synthesize_timeslot(S, states[channel])
            flat.extend(clip_int16(v) for v in out)
        results[(fi, gci)] = flat
    return results


def run_sim(mp3_path, num_frames):
    hex_path = "/tmp/_cmp_synth.hex"
    subprocess.run(["python3", str(REPO / "tools/mp3_to_hex.py"), mp3_path, hex_path], check=True)
    sim_bin = "/tmp/_cmp_synth_tb.out"
    subprocess.run(
        [
            "iverilog", "-g2012", "-o", sim_bin,
            f"-Pmp3_synthesis_tb.HEX_FILE=\"{hex_path}\"",
            f"-Pmp3_synthesis_tb.NUM_FRAMES={num_frames}",
            str(REPO / "sim/mp3_synthesis_tb.sv"),
            str(REPO / "rtl/mp3_frame_parser.sv"),
            str(REPO / "rtl/mp3_bit_reservoir.sv"),
            str(REPO / "rtl/mp3_huffman_decoder.sv"),
            str(REPO / "rtl/mp3_dequant.sv"),
            str(REPO / "rtl/mp3_stereo.sv"),
            str(REPO / "rtl/mp3_antialias.sv"),
            str(REPO / "rtl/mp3_imdct.sv"),
            str(REPO / "rtl/mp3_synthesis.sv"),
        ],
        check=True,
    )
    return subprocess.run(["vvp", sim_bin], capture_output=True, text=True, timeout=1800, check=True).stdout


def parse_sim(text):
    results = {}
    completions = {g: 0 for g in range(4)}
    cur = {g: {} for g in range(4)}
    for line in text.splitlines():
        m = re.match(r"PCM gci=(\d) idx=(\d+) data=(-?\d+)", line)
        if m:
            gci, i, d = int(m[1]), int(m[2]), int(m[3])
            cur[gci][i] = d
            continue
        m = re.match(r"PCMDONE gci=(\d)", line)
        if m:
            gci = int(m[1])
            results[(completions[gci], gci)] = [cur[gci].get(i, None) for i in range(576)]
            completions[gci] += 1
            cur[gci] = {}
            continue
    return results


def compare(mp3_path, num_frames):
    ref = run_reference(mp3_path, num_frames)
    sim_out = run_sim(mp3_path, num_frames)
    sim = parse_sim(sim_out)

    mismatches = 0
    checked = 0
    for key in sorted(ref.keys()):
        if key not in sim:
            print(f"frame {key[0]} gci {key[1]}: MISSING from sim output")
            mismatches += 1
            continue
        ref_pcm = ref[key]
        sim_pcm = sim[key]
        checked += 1
        if sim_pcm != ref_pcm:
            first_diff = next((i for i, (a, b) in enumerate(zip(sim_pcm, ref_pcm)) if a != b), None)
            print(f"frame {key[0]} gci {key[1]}: value mismatch at index {first_diff} "
                  f"ref={ref_pcm[first_diff]} sim={sim_pcm[first_diff]}")
            mismatches += 1

    if mismatches == 0:
        print(f"{mp3_path}: {checked} granule/channel PCM decodes match exactly (all 576 samples)")
        return 0
    print(f"{mp3_path}: {mismatches} mismatches out of {checked} checked")
    return 1


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    num_frames = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    sys.exit(compare(sys.argv[1], num_frames))
