#!/usr/bin/env python3
"""Cross-check mp3_huffman_decoder (frame_parser -> bit_reservoir ->
huffman_decoder chain) against tools/mp3_granule_reference.py, which is
itself validated value-for-value against an instrumented build of
FFmpeg's real decoder (see docs/MP3.md). Checks both scale factors and
all 576 decoded spectral values per granule/channel.

Usage: compare_huffman_decoder.py test_vectors/stereo_128k_44100.mp3 [num_frames]
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from mp3_header_reference import parse_frames, BitReader  # noqa: E402
from mp3_granule_reference import decode_granule  # noqa: E402


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

    results = {}  # (frame_idx, gci) -> (scalefactors, values)
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
                results[(fi, gci)] = (sf, values)
    return results


def run_sim(mp3_path, num_frames):
    hex_path = "/tmp/_cmp_huff.hex"
    subprocess.run(["python3", str(REPO / "tools/mp3_to_hex.py"), mp3_path, hex_path], check=True)
    sim_bin = "/tmp/_cmp_huff_tb.out"
    subprocess.run(
        [
            "iverilog", "-g2012", "-o", sim_bin,
            f"-Pmp3_huffman_decoder_tb.HEX_FILE=\"{hex_path}\"",
            f"-Pmp3_huffman_decoder_tb.NUM_FRAMES={num_frames}",
            str(REPO / "sim/mp3_huffman_decoder_tb.sv"),
            str(REPO / "rtl/mp3_frame_parser.sv"),
            str(REPO / "rtl/mp3_bit_reservoir.sv"),
            str(REPO / "rtl/mp3_huffman_decoder.sv"),
        ],
        check=True,
    )
    return subprocess.run(["vvp", sim_bin], capture_output=True, text=True, timeout=120, check=True).stdout


def parse_sim(text, num_frames):
    results = {}
    fi = 0
    sf = {g: {} for g in range(4)}
    val = {g: {} for g in range(4)}
    for line in text.splitlines():
        m = re.match(r"SF gci=(\d) idx=(\d+) data=(-?\d+)", line)
        if m:
            gci, i, d = int(m[1]), int(m[2]), int(m[3])
            sf[gci][i] = d
            continue
        m = re.match(r"VAL gci=(\d) idx=(\d+) data=(-?\d+)", line)
        if m:
            gci, i, d = int(m[1]), int(m[2]), int(m[3])
            val[gci][i] = d
            continue
        m = re.match(r"GCDONE gci=(\d)", line)
        if m:
            gci = int(m[1])
            sf_list = [sf[gci].get(i, None) for i in range(39)]  # 39 = short-block max; long blocks use 22
            val_list = [val[gci].get(i, None) for i in range(576)]
            results[(fi, gci)] = (sf_list, val_list)
            sf[gci] = {}
            val[gci] = {}
            continue
        m = re.match(r"FRAMEDONE (\d+)", line)
        if m:
            fi += 1
    return results


def compare(mp3_path, num_frames):
    ref = run_reference(mp3_path, num_frames)
    sim_out = run_sim(mp3_path, num_frames)
    sim = parse_sim(sim_out, num_frames)

    mismatches = 0
    checked = 0
    for key in sorted(ref.keys()):
        if key not in sim:
            print(f"frame {key[0]} gci {key[1]}: MISSING from sim output")
            mismatches += 1
            continue
        ref_sf, ref_val = ref[key]
        sim_sf, sim_val = sim[key]
        checked += 1
        if list(sim_sf[:len(ref_sf)]) != list(ref_sf):
            print(f"frame {key[0]} gci {key[1]}: scale factor mismatch\n  ref={ref_sf}\n  sim={sim_sf[:len(ref_sf)]}")
            mismatches += 1
        if sim_val != ref_val:
            first_diff = next((i for i, (a, b) in enumerate(zip(sim_val, ref_val)) if a != b), None)
            print(f"frame {key[0]} gci {key[1]}: value mismatch at index {first_diff} "
                  f"ref={ref_val[first_diff]} sim={sim_val[first_diff]}")
            mismatches += 1

    if mismatches == 0:
        print(f"{mp3_path}: {checked} granule/channel decodes match exactly (scale factors + all 576 values)")
        return 0
    print(f"{mp3_path}: {mismatches} mismatches out of {checked} checked")
    return 1


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    num_frames = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    sys.exit(compare(sys.argv[1], num_frames))
