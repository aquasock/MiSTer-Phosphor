#!/usr/bin/env python3
"""Generates ROM content for requantization (dequantization).

Design, chosen deliberately different from FFmpeg's software-era table
scheme: FFmpeg combines magnitude and the exponent's fractional part into
one table with 4 variants per magnitude (32,828 entries) specifically to
avoid a multiply -- a reasonable trade on a CPU where multiplies were once
expensive relative to memory loads. On this FPGA we have 112 real DSP
multiply blocks sitting mostly idle at this point in the design, so that
trade is backwards: paying 4x the table size to dodge a single multiply
that costs nothing. Instead:

  mag43_table[m]      = round(m^(4/3))                for m = 0..8206
                         (plain integer -- the natural range of m^(4/3)
                         fits exactly in 18 bits, no float-style
                         mantissa/exponent split needed)
  frac_exp_table[k]    = round(2^(k/4) * 2^17)         for k = 0..3
                         (Q1.17 fixed-point, tiny 4-entry table)

  product = mag43_table[m] * frac_exp_table[exponent & 3]   -- one 18x18 DSP multiply
  xr_fixed = round(product * 2^(OUTPUT_SCALE_BITS - 17 + (exponent >> 2)))

OUTPUT_SCALE_BITS=23 is a deliberately-chosen headroom constant (not an
FFmpeg value copied verbatim, though the same ballpark falls out
independently -- see docs/MP3.md): typical real audio coefficients are
tiny fractions once the gain/scalefactor exponent is applied, so without
reserving extra fractional bits in the output integer they'd round to
zero. 23 bits of headroom keeps meaningful precision for quiet
coefficients while still fitting comfortably in a wide fixed-point
accumulator for the rare loud+high-gain extreme (which saturates rather
than overflowing).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mp3_huffman_source_data import BAND_SIZE_LONG, BAND_SIZE_SHORT, PRETAB

OUT_DIR = Path(__file__).resolve().parent.parent / "rtl"

MAX_MAGNITUDE = 8206
FRAC_BITS_TABLE = 17    # frac_exp_table's fixed-point fractional bits
MAG43_FRAC_BITS = 6     # mag43_table's own fractional bits -- plain-integer
                        # storage (0 fractional bits) turned out to lose too
                        # much *relative* precision for small magnitudes:
                        # 2^(4/3)=2.52 rounds to 3, a 19% error, and small
                        # magnitudes are the common case in real audio. 6
                        # extra bits brings worst-case relative error for
                        # any magnitude down to ~0.17% (verified against the
                        # full-precision float reference).


def gen_mag43_table():
    lines = []
    max_val = 0
    for m in range(MAX_MAGNITUDE + 1):
        v = round((m ** (4.0 / 3.0)) * (1 << MAG43_FRAC_BITS))
        max_val = max(max_val, v)
        assert v < (1 << 24), f"magnitude {m}^(4/3) scaled={v} overflows 24 bits"
        lines.append(f"{v:06x}")
    with open(OUT_DIR / "mp3_dequant_mag43.hex", "w") as f:
        for line in lines:
            f.write(line + "\n")
    print(f"mag43 table: {len(lines)} entries, max value {max_val} ({max_val.bit_length()} bits)")


def gen_frac_exp_table():
    lines = []
    for k in range(4):
        v = round((2.0 ** (k / 4.0)) * (1 << FRAC_BITS_TABLE))
        assert v < (1 << 18), f"frac_exp[{k}]={v} overflows 18 bits"
        lines.append(f"{v:05x}")
    with open(OUT_DIR / "mp3_dequant_frac_exp.hex", "w") as f:
        for line in lines:
            f.write(line + "\n")
    print("frac_exp table:", lines)


def gen_band_size_roms():
    """Plain (non-cumulative) band sizes, all three sample rates,
    row0=44100/row1=48000/row2=32000 -- how many frequency positions a given
    band's exponent applies to. Distinct from mp3_band_index_long.hex
    (mp3_huffman_decoder's cumulative version, used for region boundaries)."""
    long_lines = []
    for sr in (44100, 48000, 32000):
        for size in BAND_SIZE_LONG[sr]:
            long_lines.append(f"{size:02x}")
    with open(OUT_DIR / "mp3_dequant_band_size_long.hex", "w") as f:
        for line in long_lines:
            f.write(line + "\n")

    short_lines = []
    for sr in (44100, 48000, 32000):
        for size in BAND_SIZE_SHORT[sr]:
            short_lines.append(f"{size:02x}")
    with open(OUT_DIR / "mp3_dequant_band_size_short.hex", "w") as f:
        for line in short_lines:
            f.write(line + "\n")

    pretab_lines = [f"{v:01x}" for v in PRETAB[1]]  # PRETAB[0] is all zero, no ROM needed
    with open(OUT_DIR / "mp3_dequant_pretab.hex", "w") as f:
        for line in pretab_lines:
            f.write(line + "\n")

    print(f"band_size_long: {len(long_lines)} entries, band_size_short: {len(short_lines)} entries, "
          f"pretab: {len(pretab_lines)} entries")


if __name__ == "__main__":
    OUT_DIR.mkdir(exist_ok=True)
    gen_mag43_table()
    gen_frac_exp_table()
    gen_band_size_roms()
