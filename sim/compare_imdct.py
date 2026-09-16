#!/usr/bin/env python3
"""Cross-check mp3_imdct (the full frame_parser -> bit_reservoir ->
huffman_decoder -> dequant -> stereo -> antialias -> imdct chain) against
tools/mp3_imdct_reference.py's imdct_long_block_fixed()/
imdct_short_block_fixed(), built on top of the already-validated
mp3_antialias_reference.py output. Bit-exact by construction: RTL and
Python reference implement the identical fixed-point algorithm for both
the long-block and short-block paths.

Overlap-add state is genuinely PERSISTENT across granules and frames (the
first such state in this project) -- this script tracks it exactly once,
across the whole run, starting from all zeros (matching the RTL's reset
state), never reset per-frame.

Usage: compare_imdct.py test_vectors/stereo_128k_44100.mp3 [num_frames]
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
from mp3_stereo_reference import compute_stereo_fixed, reorder_block  # noqa: E402
from mp3_antialias_reference import apply_antialias_fixed  # noqa: E402
from mp3_imdct_reference import imdct_long_block_fixed, imdct_short_block_fixed, K  # noqa: E402

NUM_CH = 2  # overlap state is per (channel, subband), channel = gci & 1


def long_end_short_start(block_type, mixed_block_flag):
    if block_type == 2:
        return (2, True) if mixed_block_flag else (0, False)
    return (32, False)


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

    overlaps = [[[0] * K for _ in range(32)] for _ in range(NUM_CH)]
    results = {}  # (frame_idx, gci) -> 576 time-major post-imdct values
    for fi, (abs_pos, mdb, f, stereo) in enumerate(positions):
        br = BitReader(bytes(main_data_stream))
        br.bit_pos = (abs_pos - mdb) * 8
        nch = 2 if stereo else 1
        gr0_sf = [None, None]
        for gr in range(2):
            xr = [None, None]
            gs = [None, None]
            for ch in range(nch):
                g = f["side_info"]["granules"][gr][ch]
                scfsi = f["side_info"]["scfsi"][ch]
                values, sf, bits = decode_granule(br, g, f["sample_rate_hz"], gr == 0, scfsi, gr0_sf[ch])
                if gr == 0:
                    gr0_sf[ch] = sf
                exponents = compute_exponents(g, f["sample_rate_hz"], sf, f["mode_extension"])
                xr[ch] = dequantize_fixed(values, exponents)
                gs[ch] = g

            if stereo:
                xr[0], xr[1] = compute_stereo_fixed(
                    xr[0], xr[1], sf if nch == 2 else [0] * 40,
                    gs[1]["block_type"], gs[1]["mixed_block_flag"],
                    f["sample_rate_hz"], f["mode_extension"],
                )

            for ch in range(nch):
                g = gs[ch]
                gci = gr * 2 + ch
                reordered = reorder_block(xr[ch], g["block_type"], g["mixed_block_flag"],
                                           g["window_switching_flag"], f["sample_rate_hz"])
                aa_out = apply_antialias_fixed(reordered, g["block_type"], g["mixed_block_flag"],
                                                g["window_switching_flag"])

                is_short = g["window_switching_flag"] and g["block_type"] == 2
                long_end, _ = long_end_short_start(g["block_type"], g["mixed_block_flag"]) if is_short else (32, False)
                channel = gci & 1
                time_major = [[0] * 32 for _ in range(18)]
                for sb in range(32):
                    x = aa_out[sb * 18:(sb + 1) * 18]
                    if is_short and sb >= long_end:
                        out = imdct_short_block_fixed(x, sb, overlaps[channel][sb])
                    else:
                        win_bt = 0 if (is_short and sb < long_end) else g["block_type"]
                        out = imdct_long_block_fixed(x, win_bt, sb, overlaps[channel][sb])
                    for t in range(18):
                        time_major[t][sb] = out[t]
                flat = [time_major[t][sb] for t in range(18) for sb in range(32)]
                results[(fi, gci)] = flat
    return results


def run_sim(mp3_path, num_frames):
    hex_path = "/tmp/_cmp_im.hex"
    subprocess.run(["python3", str(REPO / "tools/mp3_to_hex.py"), mp3_path, hex_path], check=True)
    sim_bin = "/tmp/_cmp_im_tb.out"
    subprocess.run(
        [
            "iverilog", "-g2012", "-o", sim_bin,
            f"-Pmp3_imdct_tb.HEX_FILE=\"{hex_path}\"",
            f"-Pmp3_imdct_tb.NUM_FRAMES={num_frames}",
            str(REPO / "sim/mp3_imdct_tb.sv"),
            str(REPO / "rtl/mp3_frame_parser.sv"),
            str(REPO / "rtl/mp3_bit_reservoir.sv"),
            str(REPO / "rtl/mp3_huffman_decoder.sv"),
            str(REPO / "rtl/mp3_dequant.sv"),
            str(REPO / "rtl/mp3_stereo.sv"),
            str(REPO / "rtl/mp3_antialias.sv"),
            str(REPO / "rtl/mp3_imdct.sv"),
        ],
        check=True,
    )
    return subprocess.run(["vvp", sim_bin], capture_output=True, text=True, timeout=900, check=True).stdout


def parse_sim(text):
    results = {}
    completions = {g: 0 for g in range(4)}
    cur = {g: {} for g in range(4)}
    for line in text.splitlines():
        m = re.match(r"IM gci=(\d) idx=(\d+) data=(-?\d+)", line)
        if m:
            gci, i, d = int(m[1]), int(m[2]), int(m[3])
            cur[gci][i] = d
            continue
        m = re.match(r"IMDONE gci=(\d)", line)
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
        print(f"{mp3_path}: {checked} granule/channel imdct decodes match exactly (all 576 values)")
        return 0
    print(f"{mp3_path}: {mismatches} mismatches out of {checked} checked")
    return 1


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    num_frames = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    sys.exit(compare(sys.argv[1], num_frames))
