#!/usr/bin/env python3
"""Cross-check mp3_bit_reservoir against a ground-truth concatenated
main-data stream built directly from the source file.

The reservoir's job is to make the main-data bytes of consecutive frames
(with header/side-info bytes stripped out) look like one continuous logical
stream, so main_data_begin can reach backward across frame boundaries. This
script rebuilds that logical stream in Python by slicing exactly the
main-data byte ranges out of the real file and concatenating them, then
checks the RTL's frame_read_start pointer and the bytes it actually reads
back at that pointer against the corresponding slice of the ground-truth
stream.

Usage: compare_bit_reservoir.py test_vectors/stereo_128k_44100.mp3 [num_frames]
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BUFFER_BYTES = 2048

sys.path.insert(0, str(REPO / "tools"))
from mp3_header_reference import parse_frames  # noqa: E402


def build_reference(mp3_path: str, num_frames: int):
    data = open(mp3_path, "rb").read()
    frames = parse_frames(mp3_path, num_frames)

    # Two passes: the reservoir's read pointer for frame N can legitimately
    # point into frame N's own just-arrived bytes (e.g. main_data_begin=0
    # means "start exactly where my own data begins"), and by the time
    # frame_valid(N) fires in hardware, all of frame N's own main-data bytes
    # have already been written -- so the ground truth needs the complete
    # concatenated stream built first, not just the bytes from prior frames.
    main_data_stream = bytearray()
    positions = []  # (abs_pos_before_this_frame, main_data_begin) per frame
    for f in frames:
        header_len = 4 + (0 if f["protection_bit"] else 2)
        stereo = f["channel_mode"] != "mono"
        side_info_len = 32 if stereo else 17
        main_data_offset = f["offset"] + header_len + side_info_len
        main_data_len = f["frame_len"] - header_len - side_info_len

        positions.append((len(main_data_stream), f["side_info"]["main_data_begin"]))
        main_data_stream += data[main_data_offset: main_data_offset + main_data_len]

    expected = []
    for abs_pos_before_this_frame, mdb in positions:
        read_start = abs_pos_before_this_frame - mdb
        ring_index = read_start % BUFFER_BYTES
        expected_bytes = bytes(main_data_stream[read_start: read_start + 8]) if read_start >= 0 else None
        expected.append((ring_index, expected_bytes))
    return expected


def run_sim(mp3_path: str, num_frames: int) -> str:
    hex_path = "/tmp/_cmp_resv.hex"
    subprocess.run(["python3", str(REPO / "tools/mp3_to_hex.py"), mp3_path, hex_path], check=True)
    sim_bin = "/tmp/_cmp_resv_tb.out"
    subprocess.run(
        [
            "iverilog", "-g2012", "-o", sim_bin,
            f"-Pmp3_bit_reservoir_tb.HEX_FILE=\"{hex_path}\"",
            f"-Pmp3_bit_reservoir_tb.NUM_FRAMES={num_frames}",
            str(REPO / "sim/mp3_bit_reservoir_tb.sv"),
            str(REPO / "rtl/mp3_frame_parser.sv"),
            str(REPO / "rtl/mp3_bit_reservoir.sv"),
        ],
        check=True,
    )
    return subprocess.run(["vvp", sim_bin], capture_output=True, text=True, check=True).stdout


def parse_sim(text: str):
    out = []
    for line in text.splitlines():
        m = re.match(r"FRAME idx=(\d+) frame_read_start=(\d+) bytes=(.*)", line)
        if m:
            ring_index = int(m.group(2))
            byte_str = bytes.fromhex(m.group(3).replace(" ", ""))
            out.append((ring_index, byte_str))
    return out


def compare(mp3_path: str, num_frames: int) -> int:
    expected = build_reference(mp3_path, num_frames)
    actual = parse_sim(run_sim(mp3_path, num_frames))

    mismatches = 0
    for i, ((exp_idx, exp_bytes), (act_idx, act_bytes)) in enumerate(zip(expected, actual)):
        if exp_bytes is None:
            continue  # not enough reservoir history yet to check (shouldn't happen on real files)
        if exp_idx != act_idx:
            print(f"frame {i}: frame_read_start mismatch expected={exp_idx} actual={act_idx}")
            mismatches += 1
        if exp_bytes != act_bytes:
            print(f"frame {i}: readback bytes mismatch expected={exp_bytes.hex()} actual={act_bytes.hex()}")
            mismatches += 1

    if mismatches == 0:
        print(f"{mp3_path}: {len(actual)} frames, reservoir pointer and content all match")
        return 0
    print(f"{mp3_path}: {mismatches} mismatches")
    return 1


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    num_frames = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    return compare(sys.argv[1], num_frames)


if __name__ == "__main__":
    sys.exit(main())
