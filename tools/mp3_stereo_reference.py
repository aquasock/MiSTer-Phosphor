#!/usr/bin/env python3
"""Stereo processing (MS/intensity) and short-block reorder, transcribed
from FFmpeg's compute_stereo() and reorder_block() (mpegaudiodec_template.c),
not from memory -- this stage's banded intensity-stereo boundary logic is
easy to get subtly wrong by "reasoning from the spec description" alone.

Call order matters and is preserved here exactly as in FFmpeg:
compute_stereo() runs FIRST, on both channels' *un-reordered* (bitstream
order) dequantized spectra -- short-block data at this point is still laid
out per band as [window0's `len` values][window1's `len` values][window2's
`len` values], contiguous, which is exactly what the banded backward scan
below assumes when it walks pointers by `len` per window. reorder_block()
runs SECOND, per channel independently, and only rearranges data (window0/
1/2 interleaved sample-by-sample) for block_type==2 granules; it has
nothing to do with the other channel or with stereo mode.

mode_extension (from the frame header, NOT per-granule) decides everything:
  0: neither MS nor intensity -- compute_stereo is a complete no-op.
  1: intensity only -- MS is never applied even to "real" (non-intensity)
     bands; they pass through completely unchanged.
  2: MS only -- an unconditional full-576 butterfly, no banded scan at all.
     The 1/sqrt(2) renormalization for this case is folded into
     global_gain at parse time instead (rtl/mp3_frame_parser.sv's F_GG
     state / mp3_dequant_reference.py's compute_exponents mode_extension
     param) -- so this function must NOT apply any extra scaling here.
  3: both -- the banded scan applies is_table reconstruction to bands
     identified as intensity-coded, and applies MS combination (WITH an
     explicit 1/sqrt(2) multiply this time -- global_gain is NOT
     pre-adjusted for this combined mode) to the remaining "real" bands.

Fixed-point design (mirrors mp3_dequant_reference.py's style): the 7 real
intensity-position ratios and 1/sqrt(2) are all in [0,1], stored as a
20-bit fractional (Q0.20) integer table computed directly from their exact
closed forms (is_table[k] = tan(k*pi/12)/(1+tan(k*pi/12)) and its
complement) rather than copied from FFmpeg's own differently-scaled
internal fixed-point constants -- consistent with this project's dequant
stage already doing the same thing for its own tables, and for the same
reason: there is no reason to inherit an unrelated implementation's
internal scaling choice for a from-scratch fixed-point design.
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mp3_huffman_source_data import BAND_SIZE_LONG, BAND_SIZE_SHORT

IS_FRAC_BITS = 20
IS_SF_MAX = 7  # MPEG-1 (non-LSF) only -- this project's profile never uses LSF

IS_TABLE = [
    [round((math.tan(k * math.pi / 12) / (1 + math.tan(k * math.pi / 12)) if k < 6 else 1.0) * (1 << IS_FRAC_BITS))
     for k in range(IS_SF_MAX)],
    [round((1 / (1 + math.tan(k * math.pi / 12)) if k < 6 else 0.0) * (1 << IS_FRAC_BITS))
     for k in range(IS_SF_MAX)],
]
ISQRT2_FIXED = round((1.0 / math.sqrt(2.0)) * (1 << IS_FRAC_BITS))


def _mul_shift_round(value, coeff_fixed):
    """value * coeff_fixed, then round-to-nearest right shift by
    IS_FRAC_BITS to bring the product back to value's own scale."""
    product = value * coeff_fixed
    half = 1 << (IS_FRAC_BITS - 1)
    if product >= 0:
        return (product + half) >> IS_FRAC_BITS
    return -((-product + half) >> IS_FRAC_BITS)


def compute_band_indexes(block_type, mixed_block_flag):
    """Same formula as mp3_dequant_reference.py's compute_band_indexes,
    duplicated here (not imported) because this module intentionally takes
    the raw fields rather than a full granule dict -- compute_stereo uses
    channel 1's fields for both channels' banded layout, and callers here
    may be comparing against a different channel's own values."""
    if block_type == 2:
        if mixed_block_flag:
            return 8, 3
        return 0, 0
    return 22, 13


def compute_stereo_fixed(xr0, xr1, sf1, g1_block_type, g1_mixed_block_flag,
                          sample_rate, mode_extension):
    """xr0, xr1: flat 576-entry lists of this granule's dequantized values
    (mp3_dequant.sv's fixed-point scale), channel 0 and 1, in *bitstream*
    order (matches mp3_dequant's own output order -- do not reorder before
    calling this). sf1: channel 1's scale factor list (used for intensity
    positioning; channel 0's scale factors are never used here). Returns
    (new_xr0, new_xr1); does not mutate the inputs."""
    xr0 = list(xr0)
    xr1 = list(xr1)
    ms_enabled = bool(mode_extension & 2)
    is_enabled = bool(mode_extension & 1)

    if not is_enabled:
        if ms_enabled:
            for i in range(576):
                xr0[i], xr1[i] = xr0[i] + xr1[i], xr0[i] - xr1[i]
        return xr0, xr1

    long_end, short_start = compute_band_indexes(g1_block_type, g1_mixed_block_flag)
    bstab_short = BAND_SIZE_SHORT[sample_rate]
    bstab_long = BAND_SIZE_LONG[sample_rate]
    # long_end/short_start (from compute_band_indexes) are *band counts*,
    # used below only for the scale-factor index k -- long_samples is the
    # actual frequency-position offset (36 for our profile's mixed blocks,
    # 0 for pure short, 576 for normal blocks), needed for pos arithmetic.
    long_samples = sum(bstab_long[i] for i in range(long_end))

    def apply_ms(pos0, length):
        for j in range(pos0, pos0 + length):
            if ms_enabled:
                xr0[j], xr1[j] = (_mul_shift_round(xr0[j] + xr1[j], ISQRT2_FIXED),
                                   _mul_shift_round(xr0[j] - xr1[j], ISQRT2_FIXED))
            # else: leave both channels exactly as decoded -- real stereo data.

    def apply_intensity(pos0, length, sf):
        v1, v2 = IS_TABLE[0][sf], IS_TABLE[1][sf]
        for j in range(pos0, pos0 + length):
            tmp0 = xr0[j]
            xr0[j] = _mul_shift_round(tmp0, v1)
            xr1[j] = _mul_shift_round(tmp0, v2)

    non_zero_found_short = [False, False, False]
    if short_start < 13:
        pos = long_samples + sum(bstab_short[i] for i in range(short_start, 13)) * 3
        k = (13 - short_start) * 3 + long_end - 3
        for i in range(12, short_start - 1, -1):
            if i != 11:
                k -= 3
            length = bstab_short[i]
            for w in (2, 1, 0):
                pos -= length
                l = w  # matches the C loop variable name for clarity below
                if not non_zero_found_short[l]:
                    if any(xr1[pos:pos + length]):
                        non_zero_found_short[l] = True
                        apply_ms(pos, length)
                        continue
                    sf = sf1[k + l]
                    if sf >= IS_SF_MAX:
                        apply_ms(pos, length)
                        continue
                    apply_intensity(pos, length, sf)
                else:
                    apply_ms(pos, length)

    non_zero_found = any(non_zero_found_short)
    if long_end > 0:
        pos = long_samples
        for i in range(long_end - 1, -1, -1):
            length = bstab_long[i]
            pos -= length
            if not non_zero_found:
                if any(xr1[pos:pos + length]):
                    non_zero_found = True
                    apply_ms(pos, length)
                    continue
                k = 20 if i == 21 else i
                sf = sf1[k]
                if sf >= IS_SF_MAX:
                    apply_ms(pos, length)
                    continue
                apply_intensity(pos, length, sf)
            else:
                apply_ms(pos, length)

    return xr0, xr1


def reorder_block(xr, block_type, mixed_block_flag, window_switching_flag, sample_rate):
    """In-place-equivalent: returns a new 576-list. No-op unless this is a
    real short/mixed block (window_switching_flag gates block_type's
    meaning exactly as elsewhere in this project -- see docs/MP3.md)."""
    if not (window_switching_flag and block_type == 2):
        return list(xr)

    out = list(xr)
    long_end, short_start = compute_band_indexes(block_type, mixed_block_flag)
    bstab_short = BAND_SIZE_SHORT[sample_rate]
    bstab_long = BAND_SIZE_LONG[sample_rate]
    ptr = sum(bstab_long[i] for i in range(long_end))  # 36 for a mixed block in our profile, 0 for pure short

    for i in range(short_start, 13):
        length = bstab_short[i]
        band = out[ptr:ptr + 3 * length]
        tmp = []
        for f in range(length):
            tmp.append(band[0 * length + f])
            tmp.append(band[1 * length + f])
            tmp.append(band[2 * length + f])
        out[ptr:ptr + 3 * length] = tmp
        ptr += 3 * length

    return out


if __name__ == "__main__":
    print(f"IS_TABLE[0] = {IS_TABLE[0]}")
    print(f"IS_TABLE[1] = {IS_TABLE[1]}")
    print(f"ISQRT2_FIXED = {ISQRT2_FIXED:#x}")
