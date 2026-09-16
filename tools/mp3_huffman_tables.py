#!/usr/bin/env python3
"""Canonical Huffman code construction for MPEG-1 Layer III tables, from the
verified (length, symbol) data in mp3_huffman_source_data.py.

Standard canonical construction (same algorithm as DEFLATE, RFC 1951
3.2.2): count codes per length, derive each length's first code value from
cumulative shorter-length counts, then assign codes to symbols in the
listed order using a per-length running counter. This is deterministic --
given the same (length, symbol) input, it always produces the same
codewords, so the RTL decoder and this Python reference can be checked
against each other independently of the table transcription itself
(a transcription error would show up as *both* agreeing but being wrong --
caught only by the eventual full-pipeline PCM comparison against ffmpeg).

Also provides bit-serial decode (mirroring how the RTL will consume bits
one at a time) and the per-length parameter tables the RTL's incremental
decoder uses, so both share one source of truth.
"""
from mp3_huffman_source_data import (
    HUFF_LENGTHS, HUFF_SYMBOLS, TABLE_SELECT_MAP, QUAD_CODES, QUAD_BITS,
)


def build_canonical_table(lengths, symbols):
    """Returns list of (code, length, x, y) in listed order.

    This must exactly replicate FFmpeg's ff_vlc_init_from_lengths (see
    libavcodec/vlc.c): NOT the textbook "count codes per length, then
    assign in listed order from a per-length counter" canonical
    construction -- that produces different codewords whenever the length
    list isn't sorted (verified by hand-tracing table 1's [3,3,2,1]
    lengths through both algorithms; they diverge completely). FFmpeg's
    actual algorithm is order-sensitive: walk entries in listed order with
    a single 32-bit accumulator, taking the top `length` bits of the
    accumulator as this entry's code, then advancing the accumulator by
    2^(32-length). The data's listing order was evidently chosen
    specifically to make this algorithm reproduce the ISO-standard
    codewords -- a different (if superficially also "canonical")
    construction on the same data gives self-consistent but wrong codes,
    exactly the failure mode this project's granule-level bit-count
    self-check caught.
    """
    WIDTH = 32
    code_acc = 0
    entries = []
    for length, sym in zip(lengths, symbols):
        code = code_acc >> (WIDTH - length)
        entries.append((code, length, (sym >> 4) & 0xF, sym & 0xF))
        code_acc += 1 << (WIDTH - length)
    return entries


def verify_prefix_free(entries):
    """Every codeword must be distinct and no shorter code may be a prefix
    of a longer one -- the defining property of a valid Huffman code."""
    codes_by_length = {}
    for code, length, _, _ in entries:
        codes_by_length.setdefault(length, set())
        if code in codes_by_length[length]:
            return False, f"duplicate code {code:b} at length {length}"
        codes_by_length[length].add(code)

    all_codes = [(code, length) for code, length, _, _ in entries]
    for code_a, len_a in all_codes:
        for code_b, len_b in all_codes:
            if len_a < len_b:
                if (code_a == (code_b >> (len_b - len_a))):
                    return False, f"code {code_a:0{len_a}b} is a prefix of {code_b:0{len_b}b}"
    return True, "ok"


def code_lookup(entries):
    """{length: {code: (x, y)}} -- a direct dict keyed by the actual
    (length, code), not by list position. The RTL/ROM's base+offset
    addressing scheme requires entries of equal length to sit at
    contiguous ROM addresses in code order; the *source* listing order
    (preserved in `entries`) is not grouped by length at all, so that
    arithmetic can't be done against `entries` directly -- this dict is
    the correctness-first version used by the Python reference decoder,
    independent of how the ROM ends up laid out."""
    table = {}
    for code, length, x, y in entries:
        table.setdefault(length, {})[code] = (x, y)
    return table


ALL_TABLES = {}
for name, lengths in HUFF_LENGTHS.items():
    entries = build_canonical_table(lengths, HUFF_SYMBOLS[name])
    ok, msg = verify_prefix_free(entries)
    if not ok:
        raise AssertionError(f"table {name}: {msg}")
    ALL_TABLES[name] = entries


def decode_one(bitreader, table_name, linbits):
    """Decode one big-values pair (x, y) via bit-serial canonical decode,
    mirroring the RTL's incremental approach exactly (read one bit, check
    against the current length's [first_code, first_code+count) range).
    table_name=None means 'table 0': always (0, 0), consumes zero bits."""
    if table_name is None:
        return 0, 0
    entries = ALL_TABLES[table_name]
    table = code_lookup(entries)
    max_len = max(table.keys())

    code = 0
    for length in range(1, max_len + 1):
        code = (code << 1) | bitreader.read(1)
        if length in table and code in table[length]:
            x, y = table[length][code]
            if x == 15 and linbits:
                x += bitreader.read(linbits)
            if x and bitreader.read(1):
                x = -x
            if y == 15 and linbits:
                y += bitreader.read(linbits)
            if y and bitreader.read(1):
                y = -y
            return x, y
    raise ValueError(f"no matching code in table {table_name} (bits so far: {code:b})")


def decode_quad(bitreader, table_letter):
    """Decode one count1 quadruple (v, w, x, y), each -1/0/1."""
    codes = QUAD_CODES[table_letter]
    bits = QUAD_BITS[table_letter]
    max_len = max(bits)
    code = 0
    for length in range(1, max_len + 1):
        code = (code << 1) | bitreader.read(1)
        for sym in range(16):
            if bits[sym] == length and codes[sym] == code:
                v, w, x, y = (sym >> 3) & 1, (sym >> 2) & 1, (sym >> 1) & 1, sym & 1
                if v and bitreader.read(1):
                    v = -v
                if w and bitreader.read(1):
                    w = -w
                if x and bitreader.read(1):
                    x = -x
                if y and bitreader.read(1):
                    y = -y
                return v, w, x, y
    raise ValueError(f"no matching quad code (bits so far: {code:b})")


if __name__ == "__main__":
    for name, entries in ALL_TABLES.items():
        lengths_used = sorted(set(e[1] for e in entries))
        print(f"table {name}: {len(entries)} entries, lengths {lengths_used[0]}..{lengths_used[-1]}, verified prefix-free")
    print("all tables OK")
