#!/usr/bin/env python3
"""Full per-granule/channel Huffman decode: region boundaries + big_values
loop + count1 (quadruples) loop, built on mp3_huffman_tables.py.

Region-boundary logic (region_offset2size / init_short_region /
init_long_region below) is transcribed from the same trusted source as the
Huffman tables themselves -- FFmpeg's libavcodec/mpegaudiodec_template.c
-- rather than reconstructed from memory, since the switched-block special
case in particular is easy to get subtly wrong.

The strongest available correctness check without a full pipeline: decode
should consume *exactly* part2_3_length bits, a value independently parsed
by mp3_header_reference.py from the side info (nothing to do with Huffman
tables at all). Landing exactly on that boundary across many real frames is
strong evidence the tables, canonical construction, and region-boundary
logic are all correct together.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mp3_huffman_source_data import BAND_SIZE_LONG, TABLE_SELECT_MAP
from mp3_huffman_tables import decode_one, decode_quad
from mp3_header_reference import BitReader

# ff_slen_table (libavcodec/mpegaudiodec_common.c): scalefactor bit widths
# [slen1, slen2] indexed by scalefac_compress.
SLEN_TABLE = [
    [0, 0, 0, 0, 3, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4],
    [0, 1, 2, 3, 0, 1, 2, 3, 1, 2, 3, 1, 2, 3, 2, 3],
]


def read_scalefactors(bitreader, g, is_first_granule, scfsi, gr0_scalefactors):
    """Reads this granule/channel's scale factors, consuming exactly as many
    bits as the real bitstream allocates for them (per ff_slen_table's
    [slen1, slen2] bit widths for the given scalefac_compress). part2_3_length
    spans both this ("part2") and the following Huffman-coded data ("part3")
    -- per the field's own name, which an earlier version of this decoder
    missed entirely: it started Huffman-decoding at the granule's very first
    bit, treating scale-factor bits as if they were spectral data. That
    produced plausible-looking but wrong decodes with an erratic,
    content-dependent bit-count drift -- root-caused by comparing against an
    instrumented build of FFmpeg's real decoder (see docs/MP3.md), not by
    inspection.

    gr0_scalefactors: this channel's granule-0 scale factor list, needed
    only when is_first_granule is False and some scfsi bit is set -- granule
    1 can skip re-transmitting a whole band group and copy granule 0's
    values instead, consuming zero bits for that group. Pass None for
    granule 0 itself (scfsi never applies there -- see mp3_header_reference.py's
    BitReader.read symmetry note: granule 0 always transmits its own full set).
    """
    slen1 = SLEN_TABLE[0][g["scalefac_compress"]]
    slen2 = SLEN_TABLE[1][g["scalefac_compress"]]
    sf = []
    if g["block_type"] == 2:
        n = 17 if g["mixed_block_flag"] else 18
        for _ in range(n):
            sf.append(bitreader.read(slen1) if slen1 else 0)
        for _ in range(18):
            sf.append(bitreader.read(slen2) if slen2 else 0)
        sf.extend([0, 0, 0])
    else:
        group_sizes = [6, 5, 5, 5]
        j = 0
        for k in range(4):
            n = group_sizes[k]
            slen = slen1 if k < 2 else slen2
            if is_first_granule or not scfsi[k]:
                for _ in range(n):
                    sf.append(bitreader.read(slen) if slen else 0)
            else:
                sf.extend(gr0_scalefactors[j:j + n])
            j += n
        sf.append(0)
    return sf


def band_index_long(sample_rate):
    sizes = BAND_SIZE_LONG[sample_rate]
    idx = [0]
    k = 0
    for size in sizes:
        k += size >> 1
        idx.append(k)
    return idx


def region_sizes(granule_side_info, sample_rate, sample_rate_index_le_2):
    """Returns (region_size[0], region_size[1], region_size[2]) in pairs,
    already clamped to big_values -- mirrors region_offset2size exactly."""
    g = granule_side_info
    big_values = g["big_values"]

    if g["window_switching_flag"]:
        # init_short_region: for our profile (sample_rate_index never 8),
        # region_size[0] is fixed at 18 pairs (36/2) regardless of block_type.
        raw = [18, 288, 288]
    else:
        bidx = band_index_long(sample_rate)
        ra1 = g["region0_count"]
        ra2 = g["region1_count"]
        r0 = bidx[ra1 + 1]
        r1 = bidx[min(ra1 + ra2 + 2, 22)]
        raw = [r0, r1, 288]

    sizes = []
    j = 0
    for r in raw:
        k = min(r, big_values)
        sizes.append(k - j)
        j = k
    return sizes


def decode_granule(bitreader, granule_side_info, sample_rate, is_first_granule, scfsi, gr0_scalefactors=None):
    """Decodes one granule/channel: scale factors, then Huffman data.
    Returns (values, scalefactors, bits_consumed): values is the list of up
    to 576 decoded (signed, unscaled) spectral coefficients; scalefactors is
    this granule/channel's scale factor list (pass as gr0_scalefactors into
    the same channel's granule-1 call); bits_consumed is the RAW
    (pre-realignment) total, i.e. scale-factor bits plus however many
    Huffman bits were actually used."""
    g = granule_side_info
    start_pos = bitreader.bit_pos

    scalefactors = read_scalefactors(bitreader, g, is_first_granule, scfsi, gr0_scalefactors)

    r0, r1, r2 = region_sizes(g, sample_rate, sample_rate <= 2)
    table_selects = g["table_select"]
    values = []
    for region_idx, region_len in enumerate([r0, r1, r2]):
        if region_len == 0:
            continue
        table_name, linbits = TABLE_SELECT_MAP[table_selects[region_idx]]
        for _ in range(region_len):
            x, y = decode_one(bitreader, table_name, linbits)
            values.append(x)
            values.append(y)

    target_bits = g["part2_3_length"]
    count1_table = "B" if g["count1table_select"] else "A"
    while bitreader.bit_pos - start_pos < target_bits and len(values) <= 572:
        v, w, x, y = decode_quad(bitreader, count1_table)
        values.extend([v, w, x, y])

    while len(values) < 576:
        values.append(0)

    bits_used = bitreader.bit_pos - start_pos
    # Force-realign to exactly part2_3_length, mirroring the reference
    # decoder's skip_bits_long(end_pos2 - get_bits_count()) -- natural
    # count1 decode is only guaranteed to land *near* the boundary (up to
    # one quadruple's width short or over), never exactly on it. Without
    # this, the next granule/channel starts from an undefined position and
    # every decode after the first drift is meaningless.
    bitreader.bit_pos = start_pos + target_bits

    return values, scalefactors, bits_used


if __name__ == "__main__":
    import json
    from mp3_header_reference import parse_frames

    mp3_path = sys.argv[1]
    num_frames = int(sys.argv[2]) if len(sys.argv) > 2 else 10

    frames = parse_frames(mp3_path, num_frames)
    data = open(mp3_path, "rb").read()

    main_data_stream = bytearray()
    positions = []
    for f in frames:
        header_len = 4 + (0 if f["protection_bit"] else 2)
        stereo = f["channel_mode"] != "mono"
        side_info_len = 32 if stereo else 17
        main_data_offset = f["offset"] + header_len + side_info_len
        main_data_len = f["frame_len"] - header_len - side_info_len
        positions.append((len(main_data_stream), f["side_info"]["main_data_begin"], f, stereo))
        main_data_stream += data[main_data_offset: main_data_offset + main_data_len]

    ok = 0
    fail = 0
    for abs_pos, mdb, f, stereo in positions:
        read_start_bit = (abs_pos - mdb) * 8
        if abs_pos - mdb < 0:
            continue
        br = BitReader(bytes(main_data_stream))
        br.bit_pos = read_start_bit
        nch = 2 if stereo else 1
        gr0_sf_by_channel = [None, None]
        for gr in range(2):
            for ch in range(nch):
                g = f["side_info"]["granules"][gr][ch]
                scfsi = f["side_info"]["scfsi"][ch]
                try:
                    values, scalefactors, bits_used = decode_granule(
                        br, g, f["sample_rate_hz"], gr == 0, scfsi, gr0_sf_by_channel[ch])
                except Exception as e:
                    print(f"frame@{f['offset']} gr={gr} ch={ch}: EXCEPTION {e}")
                    fail += 1
                    continue
                if gr == 0:
                    gr0_sf_by_channel[ch] = scalefactors
                if bits_used != g["part2_3_length"]:
                    print(f"frame@{f['offset']} gr={gr} ch={ch}: bit count mismatch "
                          f"expected={g['part2_3_length']} actual={bits_used}")
                    fail += 1
                else:
                    ok += 1

    print(f"{mp3_path}: {ok} granule/channel decodes matched part2_3_length exactly, {fail} mismatched")
    sys.exit(1 if fail else 0)
