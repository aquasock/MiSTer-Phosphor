#!/usr/bin/env python3
"""Alias reduction (antialiasing butterfly), transcribed from FFmpeg's
compute_antialias() (mpegaudiodec_template.c), not reasoned from the spec
text alone.

Only applies at "long" subband boundaries (positions 18, 36, ..., 558 --
the boundaries between each of the 32 18-sample subbands making up the
576-value spectrum), and only for non-short blocks:
  - block_type == 2, mixed_block_flag == 0 (pure short): skipped entirely.
  - block_type == 2, mixed_block_flag == 1 (mixed): only the FIRST
    boundary (position 18) -- only the first 36 samples (2 subbands) are
    "long" in a mixed block.
  - anything else (block_type 0/1/3, or not window-switched): all 31
    internal boundaries.

At each boundary, an 8-tap butterfly combines the 8 values just below the
boundary with the 8 values just above it:
    lo' = lo*cs[j] - hi*ca[j]
    hi' = lo*ca[j] + hi*cs[j]
for j = 0..7, where cs[j] = 1/sqrt(1+c[j]^2), ca[j] = c[j]*cs[j], and
c = [-0.6, -0.535, -0.33, -0.185, -0.095, -0.041, -0.0142, -0.0037] is the
standard ISO 11172-3 antialiasing coefficient table (verified by matching
FFmpeg's own stored csa_table floats to 7 significant digits from this
closed form -- FFmpeg's literal constants are not copied directly).
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

C_COEFFS = [-0.6, -0.535, -0.33, -0.185, -0.095, -0.041, -0.0142, -0.0037]
CS = [1.0 / math.sqrt(1 + c * c) for c in C_COEFFS]
CA = [c / math.sqrt(1 + c * c) for c in C_COEFFS]

AA_FRAC_BITS = 20
CS_FIXED = [round(v * (1 << AA_FRAC_BITS)) for v in CS]
CA_FIXED = [round(v * (1 << AA_FRAC_BITS)) for v in CA]


def _round_shift(acc):
    """Round-to-nearest right shift by AA_FRAC_BITS, applied ONCE to a full
    two-term accumulation (lo*coeff - hi*coeff or lo*coeff + hi*coeff) --
    not to each product separately, which would double the rounding error
    for no reason. Matches the hardware design: both products accumulate
    at full width before a single final rounding shift."""
    half = 1 << (AA_FRAC_BITS - 1)
    if acc >= 0:
        return (acc + half) >> AA_FRAC_BITS
    return -((-acc + half) >> AA_FRAC_BITS)


def num_boundaries(block_type, mixed_block_flag, window_switching_flag):
    if window_switching_flag and block_type == 2:
        return 1 if mixed_block_flag else 0
    return 31


def apply_antialias_fixed(xr, block_type, mixed_block_flag, window_switching_flag):
    """xr: flat 576-entry list (mp3_stereo's fixed-point output, post-
    reorder). Returns a new list; does not mutate the input."""
    out = list(xr)
    n = num_boundaries(block_type, mixed_block_flag, window_switching_flag)
    for b in range(n):
        boundary = 18 * (b + 1)
        for j in range(8):
            lo = out[boundary - 1 - j]
            hi = out[boundary + j]
            new_lo = _round_shift(lo * CS_FIXED[j] - hi * CA_FIXED[j])
            new_hi = _round_shift(lo * CA_FIXED[j] + hi * CS_FIXED[j])
            out[boundary - 1 - j] = new_lo
            out[boundary + j] = new_hi
    return out


if __name__ == "__main__":
    print("CS_FIXED =", CS_FIXED)
    print("CA_FIXED =", CA_FIXED)
