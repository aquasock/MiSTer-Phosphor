#!/usr/bin/env python3
"""Host-side reference parser for MPEG-1 Layer III frame headers and side
information. Two jobs:

1. Documentation-by-derivation for the side-info bit layout (see the field
   widths below, verified by requiring the granule/channel blocks to sum to
   exactly 256 bits for stereo / 136 bits for mono -- the ISO fixed side-info
   size -- which is a stronger check than trusting any single memorized
   source for each field width individually).
2. Oracle for the RTL testbench: dumps per-frame header + side-info fields
   as JSON so a simulation testbench can compare hardware-extracted values
   against known-correct ones.

This tool itself is unrestricted (it decodes the general MPEG-1 Layer III
header, not just this project's fixed CBR/128-192/44.1-48 profile) since
it's a development aid, not FPGA logic -- the resource-vs-generality
tradeoff documented in docs/MP3.md only applies to the hardware decoder.

Usage:
    mp3_header_reference.py file.mp3 [max_frames]
"""
import json
import sys

BITRATES_KBPS = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
SAMPLE_RATES_HZ = [44100, 48000, 32000, 0]
CHANNEL_MODES = ["stereo", "joint_stereo", "dual_channel", "mono"]


class BitReader:
    """MSB-first bit reader over a bytes object, matching the MPEG audio
    bitstream's bit order (side info and main data are both packed MSB
    first within each byte)."""

    def __init__(self, data: bytes):
        self.data = data
        self.bit_pos = 0

    def read(self, n: int) -> int:
        value = 0
        for _ in range(n):
            byte_idx = self.bit_pos // 8
            bit_idx = 7 - (self.bit_pos % 8)
            bit = (self.data[byte_idx] >> bit_idx) & 1
            value = (value << 1) | bit
            self.bit_pos += 1
        return value


def parse_granule_channel(br: BitReader) -> dict:
    g = {
        "part2_3_length": br.read(12),
        "big_values": br.read(9),
        "global_gain": br.read(8),
        "scalefac_compress": br.read(4),
        "window_switching_flag": br.read(1),
    }
    if g["window_switching_flag"]:
        g["block_type"] = br.read(2)
        g["mixed_block_flag"] = br.read(1)
        g["table_select"] = [br.read(5), br.read(5)]
        g["subblock_gain"] = [br.read(3), br.read(3), br.read(3)]
        # region boundaries are implied by block_type when window-switched,
        # not transmitted -- no region0_count/region1_count fields here.
        g["region0_count"] = None
        g["region1_count"] = None
    else:
        g["block_type"] = 0
        g["mixed_block_flag"] = 0
        g["table_select"] = [br.read(5), br.read(5), br.read(5)]
        g["subblock_gain"] = None
        g["region0_count"] = br.read(4)
        g["region1_count"] = br.read(3)
    g["preflag"] = br.read(1)
    g["scalefac_scale"] = br.read(1)
    g["count1table_select"] = br.read(1)
    return g


def parse_side_info(data: bytes, stereo: bool) -> dict:
    br = BitReader(data)
    nch = 2 if stereo else 1
    side = {
        "main_data_begin": br.read(9),
        "private_bits": br.read(5 if not stereo else 3),
        "scfsi": [[br.read(1) for _ in range(4)] for _ in range(nch)],
        "granules": [
            [parse_granule_channel(br) for _ in range(nch)] for _ in range(2)
        ],
    }
    assert br.bit_pos == len(data) * 8, f"side info bit count mismatch: consumed {br.bit_pos}, expected {len(data) * 8}"
    return side


def parse_frames(path: str, max_frames: int = 10) -> list:
    data = open(path, "rb").read()
    frames = []
    i = 0
    while i + 4 <= len(data) and len(frames) < max_frames:
        if not (data[i] == 0xFF and (data[i + 1] & 0xE0) == 0xE0):
            i += 1
            continue
        b2, b3 = data[i + 2], data[i + 3]
        bitrate_idx = (b2 >> 4) & 0xF
        sr_idx = (b2 >> 2) & 0x3
        padding = (b2 >> 1) & 0x1
        protection_bit = (data[i + 1] >> 0) & 0x1  # 1 = no CRC, 0 = CRC present
        channel_mode = (b3 >> 6) & 0x3
        mode_extension = (b3 >> 4) & 0x3

        bitrate = BITRATES_KBPS[bitrate_idx] * 1000
        sample_rate = SAMPLE_RATES_HZ[sr_idx]
        if bitrate == 0 or sample_rate == 0:
            i += 1
            continue
        frame_len = (144 * bitrate) // sample_rate + padding

        side_info_offset = i + 4 + (0 if protection_bit else 2)
        stereo = channel_mode != 3
        side_info_len = 32 if stereo else 17
        side_info_bytes = data[side_info_offset: side_info_offset + side_info_len]

        frame = {
            "offset": i,
            "frame_len": frame_len,
            "bitrate_kbps": bitrate // 1000,
            "sample_rate_hz": sample_rate,
            "padding": padding,
            "protection_bit": protection_bit,
            "channel_mode": CHANNEL_MODES[channel_mode],
            "mode_extension": mode_extension,
        }
        if len(side_info_bytes) == side_info_len:
            frame["side_info"] = parse_side_info(side_info_bytes, stereo)
        frames.append(frame)
        i += frame_len
    return frames


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    max_frames = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    frames = parse_frames(sys.argv[1], max_frames)
    print(json.dumps(frames, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
