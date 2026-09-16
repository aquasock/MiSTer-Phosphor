#!/usr/bin/env python3
"""IMDCT + windowing + overlap-add + frequency inversion, for both long
blocks and the short-block path (block_type == 2's short portion: three
12-point IMDCTs per subband with their own inter-window overlap) -- see
docs/MP3.md for the short-block derivation.

Deliberately NOT a transcription of FFmpeg's imdct36()/ff_imdct36_blocks()
-- that is a dense, algorithm-specific fast factorization (a particular
fast DCT-like decomposition, with a twiddle-factor cosine folded directly
into its window table as an optimization -- see the "merge last stage of
imdct into the window coefficients" comment in FFmpeg's own
mpegaudiodsp.c). Replicating it bit-for-bit would mean replicating an
implementation detail with no spec meaning. Instead this implements the
IMDCT from its direct mathematical definition (ISO/IEC 11172-3, IMDCT
formula in the Layer III decoding annex): a plain O(N*K) cosine sum,
verified by comparing its OUTPUT (after windowing and overlap-add) against
FFmpeg's real internal output over a run of several consecutive granules
of the same channel (to exercise the persistent overlap-add state across
calls, not just within one) -- see the __main__ block and docs/MP3.md.
Confirmed: a constant ratio of ~0.05497 against FFmpeg's real output
(std dev ~1.6e-5 across 350 significant values) -- expected, not a bug:
0.05497 * 32 = 1.759 = FFmpeg's own IMDCT_SCALAR constant, the same
FFmpeg-internal pre-scaling factor already discovered (and confirmed
irrelevant to this from-scratch design) back in the dequant stage.

Window shapes are the 3 handled here (long=0, start=1, stop=3; short=2 is
part of the not-yet-implemented short-block path) -- independently
confirmed to match FFmpeg's own window-generation code
(libavcodec/mpegaudiodsp.c's mpadsp_init_tabs(), stripped of its
IMDCT_SCALAR/twiddle-folding, which are FFmpeg-internal, not ISO-spec) by
direct comparison, not copied from its stored table values.

Fixed-point design: window[i]*cos(...) is folded into ONE precomputed
table (output[i] = window[i] * sum_k(x[k]*cos[i][k]) = sum_k(x[k] *
(window[i]*cos[i][k])), so the window multiply can be pushed inside the
same accumulation loop with no separate temporary array or extra rounding
step -- see tools/mp3_imdct_rom_gen.py, which generates the same table
this module computes inline. Matches rtl/mp3_imdct.sv's own single-
accumulate-then-round datapath exactly, so RTL vs. this reference is
bit-exact (unlike the FFmpeg comparison above, which is only checked for
a consistent scale ratio).
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

N = 36
K = 18
FRAC_BITS = 16
OUTPUT_SCALE_BITS = 23


def _window(block_type_idx):
    w = [0.0] * N
    for i in range(N):
        d = math.sin(math.pi * (i + 0.5) / 36.0)
        if block_type_idx == 1:  # start
            if i >= 30:
                d = 0.0
            elif i >= 24:
                d = math.sin(math.pi * (i - 18 + 0.5) / 12.0)
            elif i >= 18:
                d = 1.0
        elif block_type_idx == 3:  # stop
            if i < 6:
                d = 0.0
            elif i < 12:
                d = math.sin(math.pi * (i - 6 + 0.5) / 12.0)
            elif i < 18:
                d = 1.0
        w[i] = d
    return w


WINDOWS = {0: _window(0), 1: _window(1), 3: _window(3)}
COMBINED_FIXED = {
    bt: [
        [round(WINDOWS[bt][i] * math.cos(math.pi / (2 * N) * (2 * i + 1 + N // 2) * (2 * k + 1)) * (1 << FRAC_BITS))
         for k in range(K)]
        for i in range(N)
    ]
    for bt in (0, 1, 3)
}

# -- Short-block path (block_type == 2's short portion) ---------------------
# Three 12-point IMDCTs per subband (one per short window w=0,1,2), each
# independently windowed with the standard 12-tap short sine window
# (sin(pi*(i+0.5)/12), the same family of closed-form ISO window as the long
# window above, just N=12 instead of N=36 -- independently confirmed against
# FFmpeg's mpadsp_init_tabs() j==2 case, stripped of its "merge last stage of
# imdct into window" IMDCT_SCALAR/twiddle folding, same as the long windows).
#
# The three windows combine into the same 36-wide windowed[] shape the long
# path produces (so _combine_and_overlap below is shared verbatim): window w
# occupies output positions [6+6w, 18+6w), so windows 0/1 overlap-add in
# [12,18) and windows 1/2 overlap-add in [18,24); positions [0,6) and [30,36)
# get no contribution from this granule at all (pure carry-in / pure
# carry-out respectively, exactly like a long block's own overlap positions).
# Derived by hand-tracing FFmpeg's fused imdct12()+overlap-add implementation
# in compute_imdct() (mpegaudiodec_template.c) back to this equivalent
# explicit form -- not assumed from general MP3 knowledge alone, though it
# does match the well-known textbook description; see docs/MP3.md for the
# full trace and the real-FFmpeg-output cross-check.
#
# Input layout: after mp3_stereo's reorder_block(), a short-block subband's
# 18 values are interleaved by window (x[3*f + w] = window w's f-th
# frequency coefficient, f=0..5), NOT grouped as 3 contiguous sixes --
# confirmed directly from FFmpeg's imdct12(out2, ptr + w) call, where
# imdct12() itself reads its 6 inputs with stride 3 (in[0*3], in[1*3], ...).
SHORT_N = 12
SHORT_K = 6
SHORT_WINDOW = [math.sin(math.pi * (i + 0.5) / 12.0) for i in range(SHORT_N)]
COMBINED_SHORT_FIXED = [
    [round(SHORT_WINDOW[i] * math.cos(math.pi / (2 * SHORT_N) * (2 * i + 1 + SHORT_N // 2) * (2 * f + 1)) * (1 << FRAC_BITS))
     for f in range(SHORT_K)]
    for i in range(SHORT_N)
]


def _round_shift(acc, bits):
    half = 1 << (bits - 1)
    if acc >= 0:
        return (acc + half) >> bits
    return -((-acc + half) >> bits)


def _combine_and_overlap(windowed, subband_index, overlap_state):
    """Shared by both the long-block and short-block paths: apply
    frequency inversion (odd subbands negate every other output sample,
    exactly once per fresh value -- see imdct_long_block_fixed's docstring
    for the double-inversion bug this guards against) to a 36-wide
    pre-inversion windowed[] array, add the previous granule's carry-in to
    the first 18 positions, and save the last 18 as this granule's
    carry-out."""
    invert = (subband_index % 2) == 1

    def maybe_invert(i, v):
        return -v if (invert and (i % 2) == 1) else v

    out = [maybe_invert(i, windowed[i]) + overlap_state[i] for i in range(K)]
    new_overlap = [maybe_invert(i, windowed[K + i]) for i in range(K)]
    overlap_state[:] = new_overlap

    return out


def imdct_long_block_fixed(x, block_type, subband_index, overlap_state):
    """x: 18 fixed-point frequency-domain values for one subband of one
    granule. block_type: 0/1/3 (use 0 for a mixed block's long portion,
    per compute_imdct's win_idx = switch_point&&j<2 ? 0 : block_type).
    subband_index: 0..31, needed only for frequency inversion parity.
    overlap_state: this (channel, subband)'s persisted 18-value carry-in
    from the previous call for the SAME subband (list, mutated in place
    with the new carry-out for the caller's next call) -- pass a list of
    18 zeros for the very first granule of a stream.

    Returns the 18 time-domain output samples for this subband this
    granule. An earlier version re-inverted the carry-in AGAIN at the
    point of use, on top of the inversion already baked in when it was
    saved -- the two negations cancelled for the carried term while the
    fresh term stayed correctly inverted, so roughly half of each odd
    subband's output came out with the wrong sign relative to the other
    half, depending on their relative magnitudes. Caught by comparing
    against real FFmpeg output across several consecutive granules (a
    single-granule test can't expose it, since the very first granule's
    carry-in is zero either way). Now fixed by centralizing the
    invert+overlap step in _combine_and_overlap, shared with the
    short-block path below.
    """
    table = COMBINED_FIXED[block_type]
    windowed = [0] * N
    for i in range(N):
        row = table[i]
        acc = 0
        for k in range(K):
            acc += x[k] * row[k]
        windowed[i] = _round_shift(acc, FRAC_BITS)

    return _combine_and_overlap(windowed, subband_index, overlap_state)


def _raw_zw(i_local, xw):
    row = COMBINED_SHORT_FIXED[i_local]
    return sum(xw[f] * row[f] for f in range(SHORT_K))


def imdct_short_block_fixed(x, subband_index, overlap_state):
    """x: 18 reordered fixed-point values for one PURE short-block subband
    (window_switching_flag && block_type==2 && this subband is at or past
    mixed_block_flag's long_end -- 0 for a pure-short granule, 2 for a
    mixed one), interleaved by window per this module's header comment.
    subband_index/overlap_state: same contract as imdct_long_block_fixed.
    Kept unrounded (raw Q(2*FRAC_BITS)-ish accumulator, not yet
    right-shifted) through the two-window overlap-add in positions
    [12,18)/[18,24) before rounding ONCE per output position -- rounding
    each window's contribution separately first and only then adding would
    double-round (the same class of bug already fixed once in
    mp3_antialias_reference.py's _round_shift; see docs/MP3.md).
    """
    x0 = [x[3 * f + 0] for f in range(SHORT_K)]
    x1 = [x[3 * f + 1] for f in range(SHORT_K)]
    x2 = [x[3 * f + 2] for f in range(SHORT_K)]

    windowed = [0] * N
    for out_i in range(N):
        if out_i < 6 or out_i >= 30:
            acc = 0
        elif out_i < 12:
            acc = _raw_zw(out_i - 6, x0)
        elif out_i < 18:
            acc = _raw_zw(out_i - 12, x1) + _raw_zw(out_i - 6, x0)
        elif out_i < 24:
            acc = _raw_zw(out_i - 18, x2) + _raw_zw(out_i - 12, x1)
        else:
            acc = _raw_zw(out_i - 18, x2)
        windowed[out_i] = _round_shift(acc, FRAC_BITS)

    return _combine_and_overlap(windowed, subband_index, overlap_state)


if __name__ == "__main__":
    import re

    log = Path("/tmp/imdct_dbg.log").read_text().splitlines()
    aapost = []
    imdctout = []
    for line in log:
        if line.startswith("AAPOST gr=") and "ch=0" in line:
            aapost.append([int(x) for x in line.split(":")[1].split()])
        elif line.startswith("IMDCTOUT gr=") and "ch=0" in line:
            m = re.match(r"IMDCTOUT gr=(\d) ch=(\d) bt=(\d) mbf=(\d) :(.*)", line)
            gr, ch, bt, mbf, rest = m.groups()
            imdctout.append((int(bt), int(mbf), [int(x) for x in rest.split()]))

    # ffmpeg's format-probe phase decodes the first frame once before the
    # real decode pass restarts and re-decodes it (see docs/MP3.md) -- find
    # the first run of 2+ consecutive granules anywhere in the captured
    # sequence (short blocks now included, not skipped) and validate
    # overlap consistency across the whole run: granule N's carry-OUT is
    # self-contained (computable from granule N's own input alone,
    # independent of its own carry-IN), so seed from the run's first
    # granule without checking its own output (its carry-in is
    # unknown/contaminated by whatever preceded it), then check every
    # subsequent granule in the run, dispatching each subband to the long-
    # or short-block formula per its own block_type/mixed_block_flag.
    run_start = 0
    overlaps = [[0] * K for _ in range(32)]

    def process(gi):
        bt, mbf, ffmpeg_out_flat = imdctout[gi]
        xr = aapost[gi]
        long_end = (2 if mbf else 0) if bt == 2 else 0  # only meaningful when bt == 2
        mine_time_major = [[0] * 32 for _ in range(18)]
        for sb in range(32):
            x = xr[sb * 18:(sb + 1) * 18]
            if bt == 2 and sb >= long_end:
                out = imdct_short_block_fixed(x, sb, overlaps[sb])
            else:
                win_bt = 0 if (bt == 2 and sb < long_end) else bt
                out = imdct_long_block_fixed(x, win_bt, sb, overlaps[sb])
            for t in range(18):
                mine_time_major[t][sb] = out[t]
        mine_flat = [mine_time_major[t][sb] for t in range(18) for sb in range(32)]
        return mine_flat, ffmpeg_out_flat, bt, long_end

    process(run_start)  # seed carry-out only, don't check this one's own output
    worst_abs = 0
    checked = 0
    ratios = []
    short_checked = 0
    short_ratios = []
    gi = run_start + 1
    while gi < len(imdctout):
        mine_flat, ffmpeg_out_flat, bt, long_end = process(gi)
        for idx, (a, b) in enumerate(zip(mine_flat, ffmpeg_out_flat)):
            sb = idx % 32
            checked += 1
            worst_abs = max(worst_abs, abs(a - b))
            if abs(b) >= 1000:
                ratios.append(b / a)
                if bt == 2 and sb >= long_end:
                    short_checked += 1
                    short_ratios.append(b / a)
        gi += 1

    import statistics
    print(f"checked {checked} values across granules {run_start + 1}..{gi - 1}")
    if ratios:
        print(f"ratio (ffmpeg/mine) over {len(ratios)} significant values: "
              f"mean={statistics.mean(ratios):.6f} stdev={statistics.pstdev(ratios):.2e} "
              f"min={min(ratios):.6f} max={max(ratios):.6f}")
    if short_ratios:
        print(f"  of which {len(short_ratios)} are from short-block subbands: "
              f"mean={statistics.mean(short_ratios):.6f} stdev={statistics.pstdev(short_ratios):.2e}")
    else:
        print("  (no short-block subbands with significant values in this run)")
