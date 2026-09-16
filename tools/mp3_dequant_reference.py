#!/usr/bin/env python3
"""Requantization (dequantization) reference, built on decode_granule's
raw Huffman-decoded integers and scale factors.

Exponent formula transcribed from FFmpeg's exponents_from_scale_factors()
(libavcodec/mpegaudiodec_template.c), not from memory:

    gain  = global_gain - 210
    shift = scalefac_scale + 1
    exponent[i] = gain - ((scalefac[band(i)] + pretab[band(i)]) << shift)      -- long bands
    exponent[i] = (gain - (subblock_gain[w] << 3)) - (scalefac[band(i)] << shift)  -- short bands, window w

    xr[i] = sign(is[i]) * |is[i]|^(4/3) * 2^(exponent[i] / 4)

block_type==2 (short/mixed) uses long_end/short_start from
compute_band_indexes (mpegaudiodec_template.c): mixed blocks treat the
first 8 bands (44.1/48kHz) as long, the rest as short (3 interleaved
windows); pure short blocks (mixed_block_flag=0) are short throughout.
Any other block_type uses all 22 long bands and no short bands at all --
this is why block_type 1/3 ("start"/"end", window-switched but not truly
short) still uses the *long* scale-factor and exponent layout, matching
what read_scalefactors already relies on.

IMPORTANT METHODOLOGY NOTE, different from steps 1-4: this stage is not
bit-exact-comparable against FFmpeg's own dequantized output. Their
fixed-point tables bake in an extra `IMDCT_SCALAR = 1.759` divisor
(mpegaudiodec_common_tablegen.h) specifically so a compensating factor can
be skipped later in *their* IMDCT implementation -- that's an
implementation-specific optimization, not part of the ISO formula, and
comparing against it produced a real ~18x discrepancy that took real
effort to root-cause (see docs/MP3.md / project memory) before concluding
it wasn't a bug in this decoder at all. The exponent formula and the raw
Huffman-decoded magnitude were both independently confirmed correct
against instrumented FFmpeg debug output during that investigation; what's
*not* comparable is the final scaled magnitude, because there is no single
"correct" intermediate representation for a real-valued quantity -- only
the full pipeline's final PCM output is a meaningful thing to compare
end-to-end, once IMDCT/synthesis exist.

dequantize_fixed() implements the actual hardware algorithm (validated
against dequantize_float()'s full-precision math for relative error, not
against FFmpeg): a plain 18-bit magnitude^(4/3) table (the natural range
fits exactly, no float-style mantissa/exponent split needed) multiplied by
a tiny 4-entry fractional-exponent table on a real DSP-style multiply,
then a variable shift for the exponent's integer part. See
tools/mp3_dequant_rom_gen.py for why this deliberately differs from
FFmpeg's combined 32,828-entry table (that trade only makes sense when
avoiding a multiply is more valuable than RAM, which is backwards on an
FPGA with 112 idle DSP blocks).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mp3_huffman_source_data import BAND_SIZE_LONG, BAND_SIZE_SHORT, PRETAB

MAX_MAGNITUDE = 8206
FRAC_BITS_TABLE = 17
MAG43_FRAC_BITS = 6  # see tools/mp3_dequant_rom_gen.py for why this is needed
OUTPUT_SCALE_BITS = 23

MAG43_TABLE = [round((m ** (4.0 / 3.0)) * (1 << MAG43_FRAC_BITS)) for m in range(MAX_MAGNITUDE + 1)]
FRAC_EXP_TABLE = [round((2.0 ** (k / 4.0)) * (1 << FRAC_BITS_TABLE)) for k in range(4)]


def compute_band_indexes(g):
    """Returns (long_end, short_start) exactly matching compute_band_indexes."""
    if g["block_type"] == 2:
        if g["mixed_block_flag"]:
            long_end = 8  # sample_rate_index <= 2 always holds for our 44.1/48kHz-only profile
            short_start = 3
        else:
            long_end = 0
            short_start = 0
    else:
        long_end = 22
        short_start = 13
    return long_end, short_start


def compute_exponents(g, sample_rate, scalefactors, mode_extension=0):
    """Returns a flat 576-entry exponent array matching decode_granule's
    raw (bitstream-order, unreordered) value indexing.

    mode_extension==2 (MS-stereo-only, not combined with intensity) folds a
    1/sqrt(2) renormalization into global_gain here, matching FFmpeg's own
    side-info-parsing-time adjustment (mpegaudiodec_template.c: "if MS
    stereo only is selected, we precompute the 1/sqrt(2) renormalization
    factor" -- global_gain -= 2, which is exactly 2^(-2/4) once folded
    through this function's exponent-quarter-power formula). rtl/mp3_dequant.sv
    doesn't need this itself -- rtl/mp3_frame_parser.sv applies the same
    -2 at parse time, so global_gain already arrives pre-adjusted in
    hardware; this parameter exists here only because this reference
    function is handed the *raw* parsed global_gain by its callers
    (mp3_header_reference.py is deliberately a raw/uncorrected parser)."""
    long_end, short_start = compute_band_indexes(g)
    global_gain = g["global_gain"]
    if mode_extension == 2:
        global_gain = (global_gain - 2) & 0xFF
    gain = global_gain - 210
    shift = g["scalefac_scale"] + 1
    pretab = PRETAB[g["preflag"]]

    exponents = []
    bstab_long = BAND_SIZE_LONG[sample_rate]
    for i in range(long_end):
        v0 = gain - ((scalefactors[i] + pretab[i]) << shift)
        exponents.extend([v0] * bstab_long[i])

    if short_start < 13:
        bstab_short = BAND_SIZE_SHORT[sample_rate]
        sg = g["subblock_gain"] if g.get("subblock_gain") else [0, 0, 0]
        gains = [gain - (sg[w] << 3) for w in range(3)]
        k = long_end
        for i in range(short_start, 13):
            length = bstab_short[i]
            for w in range(3):
                v0 = gains[w] - (scalefactors[k] << shift)
                k += 1
                exponents.extend([v0] * length)

    while len(exponents) < 576:
        exponents.append(exponents[-1] if exponents else 0)
    return exponents[:576]


def dequantize_float(values, exponents):
    """Full-precision (Python float) reference -- used only to validate
    dequantize_fixed()'s relative error, not as an RTL-matching target."""
    xr = []
    for is_val, exponent in zip(values, exponents):
        if is_val == 0:
            xr.append(0.0)
            continue
        sign = -1.0 if is_val < 0 else 1.0
        mag = abs(is_val)
        xr.append(sign * (mag ** (4.0 / 3.0)) * (2.0 ** (exponent / 4.0)))
    return xr


def dequantize_one_fixed(is_val, exponent):
    """The actual hardware algorithm: table lookup + one multiply + a
    variable shift, matching rtl/mp3_dequant.sv exactly. Returns a signed
    integer at a fixed scale of 2^OUTPUT_SCALE_BITS relative to the true
    mathematical magnitude."""
    if is_val == 0:
        return 0
    mag = abs(is_val)
    if mag > MAX_MAGNITUDE:
        mag = MAX_MAGNITUDE  # fail-unsafe profile: never expected in-profile
    m43 = MAG43_TABLE[mag]
    frac = exponent & 3
    int_exp = exponent >> 2  # floor division, matching a two's-complement arithmetic shift
    product = m43 * FRAC_EXP_TABLE[frac]  # scaled by 2^(FRAC_BITS_TABLE + MAG43_FRAC_BITS)
    shift = OUTPUT_SCALE_BITS - FRAC_BITS_TABLE - MAG43_FRAC_BITS + int_exp
    if shift >= 0:
        result = product << shift
    else:
        n = -shift
        result = (product + (1 << (n - 1))) >> n  # round to nearest
    return -result if is_val < 0 else result


def dequantize_fixed(values, exponents):
    return [dequantize_one_fixed(v, e) for v, e in zip(values, exponents)]


if __name__ == "__main__":
    from mp3_header_reference import parse_frames, BitReader
    from mp3_granule_reference import decode_granule

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
        mo = f["offset"] + header_len + side_info_len
        ml = f["frame_len"] - header_len - side_info_len
        positions.append((len(main_data_stream), f["side_info"]["main_data_begin"], f, stereo))
        main_data_stream += data[mo:mo + ml]

    # Relative error is a misleading metric near the rounding boundary
    # (e.g. true=1.26 rounds to 2: <1 ULP absolute error, ~59% "relative
    # error" -- an artifact of dividing by a tiny number, not a real
    # precision problem). Absolute error in ULPs of the output scale is
    # the metric that actually matters: it should never exceed 1 (correct
    # rounding to nearest). Relative error is only meaningful, and worth
    # tracking separately, for values well clear of that boundary.
    worst_abs_err = 0.0
    worst_rel_err_significant = 0.0
    checked = 0
    SIGNIFICANT_THRESHOLD = 1000  # ULPs; below this, relative error isn't a meaningful signal
    for fi, (abs_pos, mdb, f, stereo) in enumerate(positions):
        br = BitReader(bytes(main_data_stream))
        br.bit_pos = (abs_pos - mdb) * 8
        nch = 2 if stereo else 1
        gr0_sf = [None, None]
        for gr in range(2):
            for ch in range(nch):
                g = f["side_info"]["granules"][gr][ch]
                scfsi = f["side_info"]["scfsi"][ch]
                values, sf, bits = decode_granule(br, g, f["sample_rate_hz"], gr == 0, scfsi, gr0_sf[ch])
                if gr == 0:
                    gr0_sf[ch] = sf
                exponents = compute_exponents(g, f["sample_rate_hz"], sf, f["mode_extension"])
                xr_float = dequantize_float(values, exponents)
                xr_fixed = dequantize_fixed(values, exponents)
                for i, (ff, fx) in enumerate(zip(xr_float, xr_fixed)):
                    true_fixed = ff * (2 ** OUTPUT_SCALE_BITS)
                    checked += 1
                    abs_err = abs(fx - true_fixed)
                    worst_abs_err = max(worst_abs_err, abs_err)
                    if abs(true_fixed) >= SIGNIFICANT_THRESHOLD:
                        rel_err = abs_err / abs(true_fixed)
                        worst_rel_err_significant = max(worst_rel_err_significant, rel_err)

    print(f"{mp3_path}: {checked} values, worst absolute error {worst_abs_err:.3f} ULP "
          f"(should be <=1 for correct rounding), worst relative error for values >= "
          f"{SIGNIFICANT_THRESHOLD} ULP: {worst_rel_err_significant:.6f}")
