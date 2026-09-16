#!/usr/bin/env python3
"""Cross-check mp3_dequant (frame_parser -> bit_reservoir -> huffman_decoder
-> dequant chain) against tools/mp3_dequant_reference.py's dequantize_fixed().
Unlike requantization's methodology note about FFmpeg (see docs/MP3.md /
mp3_dequant_reference.py's module docstring), this check IS bit-exact: both
the RTL and the Python reference implement the identical fixed-point
mag43-table * frac-exp-table * shift algorithm, so there is no float-vs-fixed
ambiguity at this layer.

Usage: compare_dequant.py test_vectors/stereo_128k_44100.mp3 [num_frames]
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from mp3_header_reference import parse_frames, BitReader  # noqa: E402
from mp3_granule_reference import decode_granule  # noqa: E402
from mp3_dequant_reference import compute_exponents, dequantize_fixed  # noqa: E402


def run_reference(mp3_path, num_frames):
    frames = parse_frames(mp3_path, num_frames)
    data = open(mp3_path, "rb").read()
    main_data_stream = bytearray()
    positions = []
    for f in frames:
        header_len = 4 + (0 if f["protection_bit"] else 2)
        stereo = f["channel_mode"] != "mono"
        side_info_len = 32 if stereo else 17
        mo = f["offset"] + header_len + side_info_len
        ml = f["frame_len"] - header_len - side_info_len
        positions.append((len(main_data_stream), f["side_info"]["main_data_begin"], f, stereo))
        main_data_stream += data[mo:mo + ml]

    results = {}  # (frame_idx, gci) -> xr_fixed (576 values)
    for fi, (abs_pos, mdb, f, stereo) in enumerate(positions):
        br = BitReader(bytes(main_data_stream))
        br.bit_pos = (abs_pos - mdb) * 8
        nch = 2 if stereo else 1
        gr0_sf = [None, None]
        for gr in range(2):
            for ch in range(nch):
                gci = gr * 2 + ch
                g = f["side_info"]["granules"][gr][ch]
                scfsi = f["side_info"]["scfsi"][ch]
                values, sf, bits = decode_granule(br, g, f["sample_rate_hz"], gr == 0, scfsi, gr0_sf[ch])
                if gr == 0:
                    gr0_sf[ch] = sf
                exponents = compute_exponents(g, f["sample_rate_hz"], sf, f["mode_extension"])
                xr_fixed = dequantize_fixed(values, exponents)
                results[(fi, gci)] = xr_fixed
    return results


def run_sim(mp3_path, num_frames):
    hex_path = "/tmp/_cmp_dq.hex"
    subprocess.run(["python3", str(REPO / "tools/mp3_to_hex.py"), mp3_path, hex_path], check=True)
    sim_bin = "/tmp/_cmp_dq_tb.out"
    subprocess.run(
        [
            "iverilog", "-g2012", "-o", sim_bin,
            f"-Pmp3_dequant_tb.HEX_FILE=\"{hex_path}\"",
            f"-Pmp3_dequant_tb.NUM_FRAMES={num_frames}",
            str(REPO / "sim/mp3_dequant_tb.sv"),
            str(REPO / "rtl/mp3_frame_parser.sv"),
            str(REPO / "rtl/mp3_bit_reservoir.sv"),
            str(REPO / "rtl/mp3_huffman_decoder.sv"),
            str(REPO / "rtl/mp3_dequant.sv"),
        ],
        check=True,
    )
    return subprocess.run(["vvp", sim_bin], capture_output=True, text=True, timeout=180, check=True).stdout


def parse_sim(text):
    # Each gci's DQDONE lags frame_done by the dequant pipeline's fixed
    # drain latency (a few cycles), since mp3_huffman_decoder asserts
    # frame_done as soon as it finishes emitting the last granule/channel's
    # raw values, before mp3_dequant has finished processing them. That
    # means the last gci's DQDONE line can appear *after* the FRAMEDONE line
    # for the same frame -- counting completions per gci (rather than
    # keying off FRAMEDONE's position in the log) sidesteps that ordering
    # entirely, since each gci completes exactly once per frame regardless.
    results = {}
    completions = {g: 0 for g in range(4)}
    cur = {g: {} for g in range(4)}
    for line in text.splitlines():
        m = re.match(r"DQ gci=(\d) idx=(\d+) data=(-?\d+)", line)
        if m:
            gci, i, d = int(m[1]), int(m[2]), int(m[3])
            cur[gci][i] = d
            continue
        m = re.match(r"DQDONE gci=(\d)", line)
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
        ref_xr = ref[key]
        sim_xr = sim[key]
        checked += 1
        if sim_xr != ref_xr:
            first_diff = next((i for i, (a, b) in enumerate(zip(sim_xr, ref_xr)) if a != b), None)
            print(f"frame {key[0]} gci {key[1]}: value mismatch at index {first_diff} "
                  f"ref={ref_xr[first_diff]} sim={sim_xr[first_diff]}")
            mismatches += 1

    if mismatches == 0:
        print(f"{mp3_path}: {checked} granule/channel dequant decodes match exactly (all 576 values)")
        return 0
    print(f"{mp3_path}: {mismatches} mismatches out of {checked} checked")
    return 1


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    num_frames = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    sys.exit(compare(sys.argv[1], num_frames))
