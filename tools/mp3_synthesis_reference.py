#!/usr/bin/env python3
"""Polyphase synthesis filterbank (step 8): converts 32 subband samples per
time slot (this project's IMDCT output, time-major: index = t*32+sb) into
32 interleaved PCM samples per time slot, per ISO/IEC 11172-3's direct
synthesis subband filter definition (the same algorithm used by Layer I,
II and III -- MP3's own "Layer III" contribution ends at the IMDCT; this
stage is shared, unmodified spec machinery). Implemented from the direct
O(64*32 + 512) definition, not FFmpeg's fast algorithm (`ff_dct32`, a
hand-factorized 32-point DCT-III fused with a circular 512-entry buffer
trick) -- same policy as every earlier stage in this project.

Matrixing formula: V[i] = sum_{k=0}^{31} S[k] * cos((16+i)*(2k+1)*pi/64),
i=0..63. Verified NOT by trusting this from memory alone but by measuring
it against real FFmpeg output two different ways:
  1. Confirmed `ff_dct32`'s OWN 32-output basis empirically (feeding unit
     impulses through the real compiled dct32_float object file) is
     cos(pi/32*(k+0.5)*i) -- a plain DCT-III, structurally different from
     the (16+i) matrixing formula above, confirming dct32+its circular
     buffer trick is a genuinely different (though output-equivalent)
     fast reformulation, not something to reverse-engineer index-by-index.
  2. Ran the (16+i)(2k+1) formula's FULL algorithm (V shift, U extract, D
     window multiply, 16-term sum) end-to-end against real FFmpeg PCM
     output (`PCMOUT`/`DCT32IN` debug dumps) using FFmpeg's own real
     internal sb_samples as input: after properly warming up the 1024-deep
     V history (processing frames 0..5 before checking frame 6+, not
     starting the comparison cold at an arbitrary later frame -- an early
     draft of this check got this wrong and produced garbage-looking
     ratios that looked like an algorithm bug but were actually a warm-up
     bug in the TEST, not the algorithm), the ratio (raw accumulator,
     unscaled float cosines / real int16 PCM) came out to a rock-solid
     constant 2^24 (mean 16,777,216-ish, relative stdev ~2e-4) -- 2^24
     exactly matches FFmpeg's own `OUT_SHIFT = WFRAC_BITS + FRAC_BITS - 15
     = 16 + 23 - 15` internal convention, confirming both the formula and
     that the algorithm's own inherent gain (independent of any FRAC_BITS
     bookkeeping choice) needs a 24-bit final shift when the window table
     is used at its natural (raw-integer, ~WFRAC_BITS=16) scale.

Window table: `ENWINDOW`, the ISO-standard 512-tap polyphase prototype
filter coefficients (shared by every compliant MP3/Layer I/II/III
decoder, encoder and reference implementation -- not FFmpeg-specific,
unlike the matrixing formula's proof above). Unlike every other window
this project has built, there's no simple closed-form cosine to
independently derive and cross-check this against -- it's just the
standard's published constants. Transcribed programmatically from
FFmpeg's own `mpegaudiodsp_data.c` (`ff_mpa_enwindow`, 257 values) to
avoid manual transcription error (the antialiasing-stage lesson), then
expanded to the full 512-entry table via the documented construction
rule (`window[i]=v`; sign-flip unless `i` is a multiple of 64; mirror to
`window[512-i]`) -- the same expansion `mpa_synth_init()` uses, itself
just bookkeeping, not an algorithm choice.

This project's own upstream pipeline (dequant -> stereo -> antialias ->
imdct) was found, when actually measured end-to-end here, to already
produce sb_samples on essentially the SAME absolute scale as FFmpeg's own
real internal sb_samples (ratio 1.0000, ~0.02% noise) --
*not* the ~18x-larger scale a much earlier stage-by-stage ratio check
might suggest in isolation. Confirmed directly, not assumed: this
project's own already-validated reference chain's sb_samples were run
through this exact quantized algorithm and diffed against real FFmpeg
PCM output, landing within +/-1 LSB (int16) on every one of 50,688
checked samples across 44 real frames. This is why this module reuses
FFmpeg's own real WFRAC_BITS=16-scale window table AND its 24-bit final
shift directly, unlike the deliberate independent-scale choices made at
every earlier stage -- this is the final stage, its output must BE
correctly-scaled 16-bit PCM, not an arbitrarily-scaled intermediate value.

Fixed-point design: matrixing coefficients are quantized to Q16
(`MATRIX_FIXED`), rounded once immediately after the 32-term matrixing
sum (produces V[i] in the same scale as the input sb_samples -- this
project's usual "round once per stage boundary" discipline, appropriate
here because the window-multiply stage's own 16-term sum genuinely can't
be algebraically pre-folded with the matrixing coefficients the way
IMDCT's window and cosine WERE folded: the U-extraction step means a
single V[i] value gets reused across MULTIPLE different final output
positions (paired with a DIFFERENT window coefficient each time as it
ages through the 1024-deep history), so there is no single per-(output,
input) coefficient to fold into -- V must exist as real, rounded,
persistent state, not a partial unrounded accumulator). The window
multiply's own 16-term sum is kept unrounded (raw accumulate) and rounded
ONCE at the very end (by 24 bits, per the derivation above) -- avoiding
the double-rounding bug class already hit once in mp3_antialias_reference.py.
"""
import math
import re
import subprocess
import sys
from pathlib import Path

FRAC_BITS = 16  # matrixing coefficient quantization (V is rounded back to sb_samples' own scale immediately after)
FINAL_SHIFT = 24  # final shift after the window-multiply 16-term sum; see module docstring for the derivation

# ISO/IEC 11172-3's standard 512-tap polyphase synthesis prototype filter,
# half-table form (indices 0..256; the full 512-entry table is built from
# this by _build_window() below) -- transcribed programmatically from
# FFmpeg's ff_mpa_enwindow (libavcodec/mpegaudiodsp_data.c), itself just a
# faithful copy of the ISO-published constants, not an FFmpeg invention.
ENWINDOW = [
    0, -1, -1, -1, -1, -1, -1, -2,
    -2, -2, -2, -3, -3, -4, -4, -5,
    -5, -6, -7, -7, -8, -9, -10, -11,
    -13, -14, -16, -17, -19, -21, -24, -26,
    -29, -31, -35, -38, -41, -45, -49, -53,
    -58, -63, -68, -73, -79, -85, -91, -97,
    -104, -111, -117, -125, -132, -139, -147, -154,
    -161, -169, -176, -183, -190, -196, -202, -208,
    213, 218, 222, 225, 227, 228, 228, 227,
    224, 221, 215, 208, 200, 189, 177, 163,
    146, 127, 106, 83, 57, 29, -2, -36,
    -72, -111, -153, -197, -244, -294, -347, -401,
    -459, -519, -581, -645, -711, -779, -848, -919,
    -991, -1064, -1137, -1210, -1283, -1356, -1428, -1498,
    -1567, -1634, -1698, -1759, -1817, -1870, -1919, -1962,
    -2001, -2032, -2057, -2075, -2085, -2087, -2080, -2063,
    2037, 2000, 1952, 1893, 1822, 1739, 1644, 1535,
    1414, 1280, 1131, 970, 794, 605, 402, 185,
    -45, -288, -545, -814, -1095, -1388, -1692, -2006,
    -2330, -2663, -3004, -3351, -3705, -4063, -4425, -4788,
    -5153, -5517, -5879, -6237, -6589, -6935, -7271, -7597,
    -7910, -8209, -8491, -8755, -8998, -9219, -9416, -9585,
    -9727, -9838, -9916, -9959, -9966, -9935, -9863, -9750,
    -9592, -9389, -9139, -8840, -8492, -8092, -7640, -7134,
    6574, 5959, 5288, 4561, 3776, 2935, 2037, 1082,
    70, -998, -2122, -3300, -4533, -5818, -7154, -8540,
    -9975, -11455, -12980, -14548, -16155, -17799, -19478, -21189,
    -22929, -24694, -26482, -28289, -30112, -31947, -33791, -35640,
    -37489, -39336, -41176, -43006, -44821, -46617, -48390, -50137,
    -51853, -53534, -55178, -56778, -58333, -59838, -61289, -62684,
    -64019, -65290, -66494, -67629, -68692, -69679, -70590, -71420,
    -72169, -72835, -73415, -73908, -74313, -74630, -74856, -74992,
    75038,
]


def _build_window():
    window = [0] * 513
    for i in range(257):
        v = ENWINDOW[i]
        window[i] = v
        if (i & 63) != 0:
            v = -v
        if i != 0:
            window[512 - i] = v
    return window[:512]


WINDOW = _build_window()

MATRIX_FIXED = [
    [round(math.cos((16 + i) * (2 * k + 1) * math.pi / 64) * (1 << FRAC_BITS)) for k in range(32)]
    for i in range(64)
]


def _round_shift(acc, bits):
    half = 1 << (bits - 1)
    if acc >= 0:
        return (acc + half) >> bits
    return -((-acc + half) >> bits)


class SynthesisState:
    """Persistent per-channel state: the 1024-entry V history FIFO. The
    first NEW kind of persistent state in this project that isn't an
    overlap-add correction term but the primary working data itself --
    every one of a channel's PCM outputs depends on up to 16 of its most
    recent time slots' matrixing results, not just the current one."""

    def __init__(self):
        self.V = [0] * 1024


def synthesize_timeslot(S, state):
    """S: 32 fixed-point subband samples for one time slot (this project's
    IMDCT output scale, matching real FFmpeg's own sb_samples scale almost
    exactly -- see module docstring). state: this channel's SynthesisState,
    mutated in place. Returns 32 PCM samples (not yet clipped to int16;
    the RTL clips at the output port, matching every real decoder's
    av_clip_int16-style final safety clip)."""
    V = state.V
    state.V = [0] * 64 + V[:960]
    V = state.V
    for i in range(64):
        row = MATRIX_FIXED[i]
        acc = 0
        for k in range(32):
            acc += S[k] * row[k]
        V[i] = _round_shift(acc, FRAC_BITS)

    U = [0] * 512
    for a in range(8):
        for j in range(32):
            U[64 * a + j] = V[128 * a + j]
            U[64 * a + 32 + j] = V[128 * a + 96 + j]

    out = []
    for j in range(32):
        acc = 0
        for i in range(16):
            acc += U[j + 32 * i] * WINDOW[j + 32 * i]
        out.append(_round_shift(acc, FINAL_SHIFT))
    return out


def clip_int16(v):
    if v > 32767:
        return 32767
    if v < -32768:
        return -32768
    return v


if __name__ == "__main__":
    # Validate the algorithm+scale derivation directly against real FFmpeg
    # PCM output, using this project's OWN already-validated sb_samples
    # (via sim/compare_imdct.py's run_reference()) as input -- not
    # FFmpeg's, since the whole point is confirming THIS pipeline's actual
    # output scale, not just the algorithm in isolation. Requires a
    # /tmp/pcm_dbg.log captured from an instrumented FFmpeg build with
    # PCMOUT dumps added right after the per-channel ff_mpa_synth_filter
    # loop in mpegaudiodec_template.c's decode_frame() -- see docs/MP3.md
    # for the exact debug hook and mono_128k_44100.mp3 as the default
    # target (real short-block content notwithstanding, this stage only
    # cares about IMDCT's OUTPUT, agnostic to how it was produced).
    REPO = Path(__file__).resolve().parent.parent
    sys.path.insert(0, str(REPO / "tools"))
    sys.path.insert(0, str(REPO / "sim"))
    import compare_imdct as C  # noqa: E402

    mp3_path = sys.argv[1] if len(sys.argv) > 1 else str(REPO / "test_vectors/mono_128k_44100.mp3")
    num_frames = int(sys.argv[2]) if len(sys.argv) > 2 else 50
    log_path = sys.argv[3] if len(sys.argv) > 3 else "/tmp/pcm_dbg.log"

    ref = C.run_reference(mp3_path, num_frames)
    pcm_frames = []
    for line in Path(log_path).read_text().splitlines():
        if line.startswith("PCMOUT ch=0"):
            pcm_frames.append([int(x) for x in line.split(":")[1].split()])

    state = SynthesisState()
    total = 0
    exact = 0
    within1 = 0
    maxdiff = 0
    for fi in range(min(num_frames, len(pcm_frames))):
        for gr in range(2):
            gci = gr * 2 + 0
            arr = ref.get((fi, gci))
            if arr is None:
                continue
            for t in range(18):
                S = arr[t * 32:(t + 1) * 32]
                out = [clip_int16(v) for v in synthesize_timeslot(S, state)]
                if fi < 6:
                    continue  # let the 1024-deep V history warm up first
                global_t = gr * 18 + t
                real = pcm_frames[fi][global_t * 32:(global_t + 1) * 32]
                for a, b in zip(out, real):
                    total += 1
                    d = a - b
                    maxdiff = max(maxdiff, abs(d))
                    if d == 0:
                        exact += 1
                    if abs(d) <= 1:
                        within1 += 1

    print(f"{mp3_path}: {total} PCM samples checked against real FFmpeg output "
          f"(frames 6+, after V history warm-up)")
    print(f"  exact matches: {exact} ({100*exact/total:.2f}%)")
    print(f"  within +/-1 LSB: {within1} ({100*within1/total:.2f}%)")
    print(f"  max abs difference: {maxdiff}")
