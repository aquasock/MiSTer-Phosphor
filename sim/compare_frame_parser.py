#!/usr/bin/env python3
"""Cross-check the mp3_frame_parser RTL simulation output against the
independent Python reference parser, field by field, for one test file.

Usage: compare_frame_parser.py test_vectors/stereo_128k_44100.mp3 [num_frames]
"""
import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def run_reference(mp3_path: str, num_frames: int) -> list:
    out = subprocess.run(
        ["python3", str(REPO / "tools/mp3_header_reference.py"), mp3_path, str(num_frames)],
        capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(out)


def run_sim(mp3_path: str, num_frames: int) -> str:
    hex_path = "/tmp/_cmp.hex"
    subprocess.run(["python3", str(REPO / "tools/mp3_to_hex.py"), mp3_path, hex_path], check=True)
    sim_bin = "/tmp/_cmp_tb.out"
    subprocess.run(
        [
            "iverilog", "-g2012", "-o", sim_bin,
            f"-Pmp3_frame_parser_tb.HEX_FILE=\"{hex_path}\"",
            f"-Pmp3_frame_parser_tb.NUM_FRAMES={num_frames}",
            str(REPO / "sim/mp3_frame_parser_tb.sv"),
            str(REPO / "rtl/mp3_frame_parser.sv"),
        ],
        check=True,
    )
    return subprocess.run(["vvp", sim_bin], capture_output=True, text=True, check=True).stdout


def parse_sim_output(text: str) -> list:
    frames = []
    cur = None
    for line in text.splitlines():
        m = re.match(r"FRAME idx=(\d+) stereo=(\d) channel_mode=(\d) mode_extension=(\d) frame_len=(\d+) main_data_begin=(\d+)", line)
        if m:
            if cur is not None:
                frames.append(cur)
            cur = {
                "stereo": int(m.group(2)),
                "channel_mode": int(m.group(3)),
                "frame_len": int(m.group(5)),
                "main_data_begin": int(m.group(6)),
                "granules": {},
            }
            continue
        m = re.match(r"\s*gci=(\d+) (.*)", line)
        if m and cur is not None:
            gci = int(m.group(1))
            fields = dict(kv.split("=") for kv in m.group(2).split())
            cur["granules"][gci] = {k: (None if not v.lstrip("-").isdigit() else int(v)) for k, v in fields.items()}
    if cur is not None:
        frames.append(cur)
    return frames


def compare(mp3_path: str, num_frames: int) -> int:
    ref = run_reference(mp3_path, num_frames)
    sim_frames = parse_sim_output(run_sim(mp3_path, num_frames))

    mismatches = 0
    for i, (r, s) in enumerate(zip(ref, sim_frames)):
        stereo = r["channel_mode"] != "mono"
        if s["frame_len"] != r["frame_len"]:
            print(f"frame {i}: frame_len mismatch ref={r['frame_len']} sim={s['frame_len']}")
            mismatches += 1
        if s["main_data_begin"] != r["side_info"]["main_data_begin"]:
            print(f"frame {i}: main_data_begin mismatch ref={r['side_info']['main_data_begin']} sim={s['main_data_begin']}")
            mismatches += 1

        gci_map = [(0, 0), (0, 1), (1, 0), (1, 1)]  # (granule, channel) per flat gci index
        active_gcis = range(4) if stereo else (0, 2)
        for gci in active_gcis:
            gr, ch = gci_map[gci]
            rg = r["side_info"]["granules"][gr][ch if stereo else 0]
            sg = s["granules"].get(gci, {})
            field_map = {
                "part2_3_length": "part2_3_length", "big_values": "big_values",
                "global_gain": "global_gain", "scalefac_compress": "scalefac_compress",
                "window_switching_flag": "window_switching_flag",
                "preflag": "preflag", "scalefac_scale": "scalefac_scale",
                "count1table_select": "count1table_select",
            }
            for rk, sk in field_map.items():
                rv, sv = rg[rk], sg.get(sk)
                if rk == "global_gain" and r["mode_extension"] == 2:
                    # MS-stereo-only folds a 1/sqrt(2) renormalization into
                    # global_gain at parse time (mp3_frame_parser.sv's F_GG
                    # state) -- mp3_header_reference.py deliberately stays a
                    # raw/uncorrected parser (see its module docstring), so
                    # the correction is applied here for comparison instead.
                    rv = (rv - 2) & 0xFF
                if rv != sv:
                    print(f"frame {i} gci={gci}: {sk} mismatch ref={rv} sim={sv}")
                    mismatches += 1
            if rg["window_switching_flag"]:
                if rg["block_type"] != sg.get("block_type"):
                    print(f"frame {i} gci={gci}: block_type mismatch ref={rg['block_type']} sim={sg.get('block_type')}")
                    mismatches += 1
                if rg["mixed_block_flag"] != sg.get("mixed_block_flag"):
                    print(f"frame {i} gci={gci}: mixed_block_flag mismatch ref={rg['mixed_block_flag']} sim={sg.get('mixed_block_flag')}")
                    mismatches += 1
                for k in range(2):
                    if rg["table_select"][k] != sg.get(f"table_select{k}"):
                        print(f"frame {i} gci={gci}: table_select{k} mismatch ref={rg['table_select'][k]} sim={sg.get(f'table_select{k}')}")
                        mismatches += 1
                for k in range(3):
                    if rg["subblock_gain"][k] != sg.get(f"subblock_gain{k}"):
                        print(f"frame {i} gci={gci}: subblock_gain{k} mismatch ref={rg['subblock_gain'][k]} sim={sg.get(f'subblock_gain{k}')}")
                        mismatches += 1
            else:
                for k in range(3):
                    if rg["table_select"][k] != sg.get(f"table_select{k}"):
                        print(f"frame {i} gci={gci}: table_select{k} mismatch ref={rg['table_select'][k]} sim={sg.get(f'table_select{k}')}")
                        mismatches += 1
                if rg["region0_count"] != sg.get("region0_count"):
                    print(f"frame {i} gci={gci}: region0_count mismatch ref={rg['region0_count']} sim={sg.get('region0_count')}")
                    mismatches += 1
                if rg["region1_count"] != sg.get("region1_count"):
                    print(f"frame {i} gci={gci}: region1_count mismatch ref={rg['region1_count']} sim={sg.get('region1_count')}")
                    mismatches += 1

    if mismatches == 0:
        print(f"{mp3_path}: {len(ref)} frames, all fields match")
        return 0
    print(f"{mp3_path}: {mismatches} field mismatches")
    return 1


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    num_frames = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    return compare(sys.argv[1], num_frames)


if __name__ == "__main__":
    sys.exit(main())
