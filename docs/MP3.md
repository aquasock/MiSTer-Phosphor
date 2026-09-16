# Accepted profile and decode contract

This decoder targets a single fixed MPEG-1 Layer III profile and nothing
else. Unlike [MiSTer-Phosphor](https://github.com/aquasock/MiSTer-Phosphor)'s
FLAC/MP2 decoders — which validate every accepted parameter from the stream
itself and explicitly reject anything outside their profile — this decoder
spends **no FPGA resources on validation of any kind**. Every parameter
below is *assumed*, never checked. Input outside this profile is undefined
behavior: garbage output, a stuck decoder, or a hang are all acceptable
outcomes, not bugs to guard against. This is a deliberate resource-vs-
robustness tradeoff for this project, not an oversight.

## Fixed profile

- **MPEG-1 Layer III** only (no Layer I/II, no MPEG-2/2.5 low-sample-rate
  extension).
- **CBR only**, and only two bitrates: **128 kb/s or 192 kb/s**.
- **Sample rate: 44.1 kHz or 48 kHz** only (not 32 kHz).
- **Mono or stereo** (including joint stereo — see below). Dual-channel
  (two independent mono channels in one stream, used for
  bilingual/multitrack audio) is out of scope: nothing deliberately blocks
  it, but no decode path is built for it, so it falls under the general
  undefined-behavior contract above like any other out-of-profile input.

## Why joint stereo has to be a real decode path, not an edge case

MPEG-1 Layer III's `channel_mode` header field has four values: independent
stereo, **joint stereo** (mid-side and/or intensity stereo coding), dual
channel, and mono. It would be a mistake to read "stereo" as only meaning
the independent-stereo bit pattern: real encoders default to joint stereo
at these bitrates. Verified directly against `libmp3lame` (via ffmpeg) at
128 kb/s/44.1 kHz: two-channel content that is *highly correlated* (matched
frequency on both channels) encodes as `channel_mode = 1` (joint stereo)
with `mode_extension = 2`; even a maximally-decorrelated test signal (440 Hz
left / 880 Hz right, nothing shared between channels) still came out as
joint stereo in most encodes tested, independent stereo appearing only when
the encoder judged joint coding to add no benefit. Skipping MS/intensity
decode to save resources would mean the decoder gets typical real-world
128/192 kb/s stereo files *wrong* — not merely "outside the assumed
profile," but silently incorrect on exactly the content it's supposed to
handle. So: **independent stereo, joint stereo (MS and intensity), and mono
are all real, built decode paths.** The exact bit-level semantics of
`mode_extension` (which bit selects MS vs. intensity, and how the
per-granule/per-scalefactor-band split between them is actually signaled)
should be taken from ISO/IEC 11172-3 §2.4.3.4 directly during
implementation rather than assumed from this document — that level of
detail is verified against the standard text when the stereo-processing
stage is actually built, not asserted here.

## What's still real parsing, not validation

A few header fields have to be read correctly to walk the bitstream at all
— this is structural layout parsing, not conformance checking, and doesn't
contradict the no-validation contract:

- **`protection_bit`** — determines whether a 2-byte CRC field sits between
  the 4-byte header and the side information. The decoder reads this bit
  purely to compute the correct side-info offset; it never reads or
  verifies the CRC value itself.
- **`padding_bit`** — see the frame-length table below. Required to
  correctly locate the next frame's sync word for two of the four accepted
  configurations.
- **`main_data_begin`** (9 bits, in the side info) — the bit-reservoir
  backward offset. This is fully general regardless of the fixed bitrate
  set: even genuinely CBR-encoded content varies per-granule bit
  allocation frame to frame (that's the entire reason the reservoir exists
  at all), so this can't be simplified away just because the nominal
  bitrate is fixed.
- **`channel_mode`** — selects which of the mono/independent-stereo/joint-
  stereo decode paths applies to the current frame; see above.

Fields that don't affect bitstream layout or which decode path applies
(MPEG version ID, layer ID, the bitrate/sample-rate index values beyond a
direct table lookup, emphasis, copyright, original) are consumed as part of
reading the fixed 4-byte header but never examined or branched on.

## Frame length: a 4-entry constant, not an arithmetic circuit

Frame length in bytes is `floor(144 * bitrate / sample_rate) + padding_bit`.
With exactly two bitrates and two sample rates in scope, this reduces to
four known constants rather than a general multiply/divide — a direct
resource-saving consequence of the fixed profile. Verified empirically
(`ffprobe` packet sizes against `libmp3lame`-encoded CBR test files):

| Bitrate | Sample rate | Frame length              |
|---------|-------------|----------------------------|
| 128 kb/s | 44.1 kHz   | 417 bytes, or 418 with padding |
| 192 kb/s | 44.1 kHz   | 626 bytes, or 627 with padding |
| 128 kb/s | 48 kHz     | 384 bytes exactly, padding never set |
| 192 kb/s | 48 kHz     | 576 bytes exactly, padding never set |

The 48 kHz combinations divide evenly, so a genuine CBR encoder never needs
to set the padding bit for them — only the two 44.1 kHz combinations
actually exercise it. The padding bit still has to be read generically
(the decoder doesn't know at compile time which of the four combinations a
given file uses), but the frame-length computation itself is a 4-entry
lookup indexed by `(bitrate_index, sample_rate_index)` plus one conditional
+1, not a divider.

## Side information size

32 bytes for any two-channel mode (independent stereo, joint stereo, dual
channel — all three share this layout per ISO/IEC 11172-3), 17 bytes for
mono.

## Huffman decode: scale factors are part of part2_3_length

`part2_3_length` (in the per-granule side info) is not purely a Huffman
data length -- the name means what it says: "part2" (scale factors) plus
"part3" (Huffman-coded big_values/count1 data). The scale factor bits
sit *before* the Huffman-coded region, at a bit width that depends on
`scalefac_compress` (via the standard `ff_slen_table` lookup: `[slen1,
slen2]` per compress value) and, for non-short blocks, on the per-channel
`scfsi` bits (granule 1 can skip re-transmitting a scale-factor band group
entirely if it matches granule 0, consuming zero bits for that group).
Short/mixed blocks (`block_type == 2`) never use scfsi sharing and use a
different fixed group-size formula (17 or 18 bands depending on
`mixed_block_flag`, then 18 more).

This matters even before the scale factor *values* are needed for
requantization (a later step): the Huffman decoder cannot locate where its
own data begins without first walking past this many bits. `mp3_granule_reference.py`'s
`read_scalefactors()` now decodes the actual values too (not just the bit
count), since it's the same parsing pass and the values are needed by the
next stage regardless -- verified value-for-value against the real
decoder, including the scfsi group-copy path (granule 1 reusing granule
0's values for an unchanged band group, consuming zero bits for it). Getting this
wrong doesn't fail loudly -- it produces plausible-looking but wrong
Huffman decodes with an erratic, content-dependent bit-count drift, since
almost any bit pattern matches *some* valid codeword in a complete prefix
code. This was root-caused by comparing against an instrumented build of
FFmpeg's actual decoder (debug prints added directly to
`huffman_decode()`/`region_offset2size()` in a local build), not by
inspection -- worth remembering as a debugging approach if a similarly
opaque discrepancy shows up again in a later stage (IMDCT, stereo
processing): re-derive against real reference decoder output rather than
re-reading the same source text more carefully.

A second, unrelated bug fixed in the same pass: canonical Huffman code
construction from `mp3_huffman_source_data.py`'s (length, symbol) lists
must replicate FFmpeg's specific order-sensitive algorithm (`vlc.c`'s
`ff_vlc_init_from_lengths`: a running accumulator processed in listed
order), not the textbook "count codes per length, then assign" canonical
construction -- the two agree only when lengths happen to already be
sorted, which most of these tables' listed order is not.

## Requantization: not comparable to FFmpeg's raw dequantized output

Once `is[i]` (the raw Huffman-decoded integer) and its exponent (derived
from `global_gain`/`scalefac_scale`/the scale factor/`preflag` per
`exponents_from_scale_factors()`) are known, `xr[i] = sign(is[i]) *
|is[i]|^(4/3) * 2^(exponent[i]/4)` per the ISO formula. Unlike every
earlier stage, this one is *not* bit-exact-comparable against FFmpeg's own
internal `sb_hybrid[]`/dequantized values: FFmpeg's fixed-point dequant
tables (`mpegaudiodec_common_tablegen.h`, `mpegaudio_tablegen.h`) bake in
an extra `IMDCT_SCALAR = 1.759` divisor specifically so a compensating
factor can be skipped later in *their* IMDCT stage. That's an
implementation-specific optimization, not part of the ISO formula, and
diffing against it produces a spurious ~18x discrepancy that looks like a
real bug (it cost real debugging time before being root-caused). The
correct validation bar for this stage is internal consistency against a
full-precision float reference (`tools/mp3_dequant_reference.py`'s
`dequantize_float()` vs `dequantize_fixed()`), not bit-matching FFmpeg;
only the final PCM output, once IMDCT/synthesis exist, is meaningful to
compare end-to-end against a real reference decoder again.

Hardware design (`rtl/mp3_dequant.sv`), deliberately different from
FFmpeg's software-era approach: FFmpeg combines magnitude and the
exponent's fractional part into one 32,828-entry table specifically to
avoid a multiply -- sensible on a CPU, backwards on an FPGA with 112 idle
DSP blocks. Instead: a small `magnitude^(4/3)` table (8,207 entries, with
6 extra fractional bits -- 0 fractional bits loses too much *relative*
precision for small magnitudes, e.g. `2^(4/3)=2.52` rounding to `3`, a 19%
error, and small magnitudes are the common case in real audio) times a
4-entry fractional-exponent table, on a real 24x18 DSP multiply, then a
variable shift for the exponent's integer part. Verified against the float
reference: worst-case relative error ~0.17% for values large enough for
relative error to be a meaningful metric at all (below ~1000 ULP of the
output's `2^23` fixed-point scale, absolute error dominates and relative
error is a rounding-boundary artifact, not a real precision signal --
e.g. a true value of 1.26 rounding to 2 is <1 ULP off but ~59% "relative
error").

Two bugs found and fixed while validating this stage's RTL against
`tools/mp3_dequant_reference.py`, both are worth remembering as bug
*classes* for the still-unwritten stages (stereo/IMDCT/synthesis):

- **A stalled multi-cycle FSM silently drops input.** The first RTL
  version processed each dequantized value through a single shared 5-cycle
  FSM (lookup -> multiply -> shift -> emit), reused for every value. But
  `mp3_huffman_decoder`'s count1/zero states (`C1_ZERO`/`C1_EMIT`) can emit
  a new `value_valid` on every consecutive clock cycle for a run of
  zero-magnitude symbols -- common at high frequencies in real audio -- so
  the FSM missed any value that arrived while busy, with no error, no
  stall, just silently wrong output. Comparison against the reference
  showed entire runs of missing output indices, not a specific wrong
  value, which was the tell. Fixed by making the datapath a true 4-stage
  pipeline (lookup -> multiply -> shift -> output) that accepts a new
  value every cycle unconditionally, with a per-stage valid bit carried
  through as a bubble when idle. **Any future streaming stage fed directly
  by mp3_huffman_decoder's value stream must assume it can receive
  `value_valid` on back-to-back cycles indefinitely** -- there is no
  backpressure signal from this decoder's house style, so every consumer
  must either keep up unconditionally (pipeline, not a stall-capable FSM)
  or the testbench pacing trick used between frame_parser and
  huffman_decoder isn't available at this finer grain (huffman_decoder
  itself has no "wait" input to throttle).
- **An off-by-one in a countdown-vs-position check.** The value-side band
  tracker (which frequency position is covered by which scale-factor
  band's exponent) used a countdown register written one cycle *before*
  the index it was meant to describe was current, so "last position of the
  band" was detected one index too late -- the first value of every new
  band used the *previous* band's exponent instead of its own. It only
  showed up right at a band boundary (e.g. index 288, the 18/19 boundary
  in a real 44.1kHz long block, in one of the profile test files) --
  everywhere else within a band the wrong-by-one-cycle value happened to
  equal the right one. Fixed by comparing a position counter against the
  band size combinationally, evaluated for the value in flight *this*
  cycle, rather than checking a register that lagged by one cycle. General
  lesson: any register meant to answer "is this the last/first element of
  a group" must be evaluated using values that describe the *current*
  element, not values left over from updating for the *next* one --
  a one-cycle registration lag here is invisible except exactly at
  boundaries, making it easy to validate against a handful of frames and
  still ship a bug that only shows up on specific content.

A related testbench-only bug (not an RTL bug, but a real trap worth
avoiding again): a `#<delay> $finish` sitting inside the *same*
`always @(posedge clk)` block that also prints `out_valid` each cycle
silently truncates the last few cycles of output. Once the block enters
the blocking delay it cannot return to the top and re-trigger on
subsequent clock edges until the delay completes, so it misses exactly the
tail-end pulses (the last index of the last frame) that a "drain the
pipeline before finishing" delay is meant to *catch*. Fix: put the delay
in its own `always` block, separate from the one doing per-cycle
monitoring.

## MS-stereo-only renormalization is folded into global_gain, not applied later

FFmpeg's side-info parsing subtracts 2 from the parsed `global_gain` when
`mode_extension` is exactly `2` (MS-STEREO bit set, INTENSITY-STEREO bit
clear -- combined MS+intensity does *not* get this): "if MS stereo only is
selected, we precompute the 1/sqrt(2) renormalization factor." `-2` in the
exponent's quarter-power units is exactly `2^(-2/4) = 1/sqrt(2)`. This is a
parse-time correction, not a stereo-stage runtime decision, and it applies
to *both* channels' `global_gain` equally.

This was missed in the original `rtl/mp3_dequant.sv`/side-info work,
because every one of the 8 profile test files happens to use
`mode_extension == 0` (their L/R channels are uncorrelated synthetic tones,
so real encoders never choose MS or intensity for them -- see the stereo
section below) -- the condition simply never triggered, so the omission
was invisible until a real MS-only test file was created for stage 6.
Fixed in `rtl/mp3_frame_parser.sv`'s `F_GG` state (`global_gain[gci] <=
bits_value[7:0] - (mode_extension == 2'd2 ? 2 : 0)`), which means
`rtl/mp3_dequant.sv` itself needed no change at all -- it just consumes
`global_gain` as given, and now that value already has the correction
baked in by the time it arrives. `tools/mp3_header_reference.py` stays a
deliberately raw/uncorrected parser (per its own docstring); the
correction is applied in `tools/mp3_dequant_reference.py`'s
`compute_exponents()` and in `sim/compare_frame_parser.py`'s comparison
logic instead, both taking a `mode_extension` parameter for exactly this.

## Stereo processing (MS/intensity) and short-block reorder

Transcribed from FFmpeg's `compute_stereo()`/`reorder_block()`
(`mpegaudiodec_template.c`), not reasoned from the spec text alone --
`tools/mp3_stereo_reference.py` has the derivation. Two things worth
remembering if this stage is ever revisited:

- **Real LAME output never sets the intensity-stereo mode_ext bit.**
  Modern LAME dropped intensity-stereo *encoding* entirely (it still
  decodes it for compatibility) -- every attempt to generate a test file
  that exercises it (identical channels, correlated noise, bitrates down
  to 32k) produced `mode_extension` of only 0 or 2, never 1 or 3. The
  MS-only path (`mode_extension == 2`) *is* covered by a real file
  (`/tmp/test_identical.mp3`, two identical sine channels, not part of
  the checked-in profile set) and validated bit-exact against real
  FFmpeg's own `compute_stereo()` output. The intensity path (1 or 3) has
  no real bitstream to test against at all; it's validated instead by
  patching an instrumented FFmpeg build to force `mode_ext = 3` and zero
  part of one channel's spectrum on a real decode, using FFmpeg's own
  (real, unmodified) `compute_stereo()` as ground truth for that synthetic
  scenario, then re-validating the RTL against `mp3_stereo_reference.py`
  fed the identical inputs. Any future stage with no real bitstream
  coverage should use this same "force it through the real reference
  decoder on synthetic input" approach rather than trusting a
  hand-derived expectation alone.
- **Short block band 12 has no real transmitted scale factor.**
  `read_scalefactors` pads it with zeros; FFmpeg's intensity-stereo scan
  deliberately reuses band 11's scale factor for band 12 instead (its "for
  last band, use previous scale factor" comment) -- confirmed by hand-
  tracing FFmpeg's actual `k -= 3 unless i == 11` decrement arithmetic
  down to concrete indices, not by trusting the comment's wording alone.

**Architecture**: this is the first stage that cannot be a simple
streaming pass. Real intensity-stereo bands are found by scanning HIGH
frequency to LOW (is channel 1 all-zero there? if so, it's intensity-
coded), but `mp3_dequant` streams values low-to-high -- the wrong
direction for this scan. Reorder also needs a whole channel's data at
once. So `rtl/mp3_stereo.sv` buffers both channels of a granule pair
completely, then processes the buffered copy, then streams the (possibly
transformed, possibly reordered) result back out -- a fundamentally
different shape from every earlier streaming stage.

Buffering a whole granule pair before processing introduces exactly the
kind of cross-stage race this project has hit before (frame_parser vs.
huffman_decoder), at a new boundary: `mp3_huffman_decoder`/`mp3_dequant`
have no backpressure and can finish decoding *both* granules of a frame
well before this module finishes processing even the first (measured
directly: as few as ~300 cycles between two granule completions for a
simple frame, against 1150+ cycles just to stream one granule pair back
out). Retrofitting a real stall signal through `mp3_huffman_decoder`'s
large, already-validated state machine was judged too risky this late;
instead `mp3_stereo.sv` double-buffers (two full granule-pair banks) and
queues up to 2 pending pairs' worth of side-info, bounding the backlog to
one frame's worth (which is exactly the two banks available) rather than
requiring unbounded buffering.

**Three real bugs found validating this stage, each worth remembering as
a bug *class*:**
1. **A single proc_bank/active_gci register pair, clobbered mid-flight.**
   The first version reacted to the raw `trigger` signal directly,
   updating `proc_bank`/`active_gci0/1` unconditionally whenever a granule
   pair completed -- but a second completion can arrive before the first
   pair's processing has even started, silently overwriting the
   bookkeeping for a pair that hasn't been touched yet. Symptom: every
   value one full granule pair behind where it should be. Fixed with a
   real 2-deep queue, with each entry's side-info
   (`window_switching_flag`/`block_type`/`mixed_block_flag`/`stereo`/
   `mode_extension`) snapshotted at push time -- not re-read from the
   shared per-frame registers later, since those get overwritten by the
   very next `frame_valid` while a queued entry might still be waiting.
2. **`proc_bank == !wr_bank` is not actually an invariant.** With a
   2-deep queue, `wr_bank` can toggle twice (parking back on its original
   value) while `proc_bank` is still catching up to the first queued
   entry -- so code that infers one bank register from the complement of
   the other reads the wrong physical bank in that window. Symptom: one
   dropped (zeroed) value out of 69,120 checked -- rare, because it only
   manifests when both queue slots are genuinely occupied at once. Fixed
   by testing `wr_bank` and `proc_bank` independently everywhere, never
   assuming either is the other's complement.
3. **`21'sd1048576` silently wraps to -1048576.** A 21-bit signed literal
   can only hold up to `2^20 - 1 = 1048575` positively; `2^20` itself
   overflows into the sign bit. This broke exactly the two intensity-table
   entries that legitimately equal 1.0 in Q0.20 (`is_table0(6)` and
   `is_table1(0)`), producing a sign-flipped result only when a real
   silent/zero "other channel" caused pure intensity reconstruction with a
   scale factor of exactly 0. General lesson: when picking a fixed-point
   container width for a table living in `[0, 1.0]`, check whether the
   representation of *exactly* 1.0 needs one more bit than the largest
   value strictly less than 1.0 does -- it usually does, by exactly one.

**A related, real RAM-inference lesson** (not a functional bug --
`mp3_stereo.sv`'s behavior was already correct at this point -- but a
real resource-usage bug caught by the same real-Quartus-synthesis
discipline used at every prior stage): the buffer arrays
(`buf0`/`buf1`/`sf1_mem`) were declared as `reg [...][0:1][0:...]`, a
runtime-bank-indexed 2D array, written from two separate `always` blocks
(one for the continuous per-value buffering write, one for the FSM's own
processing read/write). Quartus refused to infer block RAM for this at
all ("uninferred due to unsupported read-during-write behavior" --
it cannot statically prove the two write sites' bank indices never
coincide, even though they never do by construction), instead expanding
it into ~98,000 logic cells of individual registers, in a module that
should cost a few hundred ALMs. Fixing it took two steps, and the first
one alone was not enough:
- Split each 2D array into two physically separate per-bank 1D arrays
  (`buf0_a`/`buf0_b`, etc.), unifying every access behind one address bus.
  This alone still failed to infer ("uninferred due to asynchronous read
  logic") once the two banks' outputs were combined in a single ternary
  feeding one register (`fsm_rd0 <= sel ? buf0_a[addr] : buf0_b[addr]`) --
  from each array's own perspective its output no longer feeds a register
  directly, it feeds a mux, and Quartus won't infer synchronous RAM read
  for that.
- Give each physical array its *own* dedicated registered read output
  (`buf0_a_rd <= buf0_a[addr]`; `buf0_b_rd <= buf0_b[addr]`), then mux the
  two already-registered values together as a separate combinational step.
  This is the pattern Quartus's inference actually recognizes. Real
  synthesis result after both fixes: 6,103 logic cells (matching the
  ballpark of every other stage), not 98,000+.

Full pipeline (parser + reservoir + Huffman decoder + dequant + stereo)
real Quartus fit on the `5CSEBA6U23I7`: 3,021 ALMs (7%), 2,146 registers,
55 M10K blocks / 361,510 bits (10%/6%), 14 DSP blocks (13%) -- comfortably
within budget.

## Alias reduction (antialiasing)

Transcribed from FFmpeg's `compute_antialias()` (`mpegaudiodec_template.c`)
-- see `tools/mp3_antialias_reference.py` for the derivation. Applies an
8-tap butterfly at each internal boundary between the 32 18-sample
subbands making up the 576-value spectrum (skipped entirely for pure
short blocks; only the first boundary for mixed blocks; all 31 boundaries
otherwise). The 8 coefficient pairs are the standard ISO 11172-3
antialiasing table, derived from its closed form (`cs[j] =
1/sqrt(1+c[j]^2)`, `ca[j] = c[j]*cs[j]`, `c = [-0.6, -0.535, -0.33,
-0.185, -0.095, -0.041, -0.0142, -0.0037]`) rather than copied from
FFmpeg's own stored floats -- worth noting this took one real false start:
a half-remembered version of the `c` table (with `c[4] = -0.080` instead
of the correct `-0.095`) matched FFmpeg's first four entries but silently
diverged on the rest, caught only by reversing FFmpeg's actual stored
`csa_table` floats back into implied `c` values and comparing, not by
trusting memory a second time. Validated against real FFmpeg internals to
~0.35% worst relative error for significant values, the same precision
profile as every earlier fixed-point stage.

**A real bug, worth remembering as a pattern for every future downstream
stage**: this module originally read `window_switching_flag`/`block_type`/
`mixed_block_flag` fresh from `mp3_frame_parser`'s shared per-frame arrays
(the same pattern `mp3_dequant` and `mp3_stereo` use successfully). It
silently misclassified a pure-short-block granule as needing antialiasing
-- caught by comparison against `tools/mp3_antialias_reference.py` showing
236 of 576 values wrong on one specific granule/channel, not a rounding
difference. Root cause: this module's *input* is `mp3_stereo`'s *output*,
and `mp3_stereo` can lag `frame_valid` by many frames' worth of
buffer+scan+reorder+stream processing time (not the few bounded cycles
`mp3_dequant`'s true pipeline lags by) -- by the time a value for an older
frame finally arrives here, the shared per-frame arrays may already
reflect a newer frame's side info entirely. **The fix, and the pattern to
follow from here on**: side info must travel *with* the value stream
itself once a stage's own processing latency can exceed roughly one
frame's worth of upstream production time, not be re-derived from a
shared array at the point of use. `mp3_stereo.sv` now exposes
`out_wsf`/`out_bt`/`out_mbf` alongside its `out_gci`/`out_data` (reusing
the value it already snapshotted per pending-pair in its own queue, at no
extra cost), and `mp3_antialias.sv` consumes those directly instead of
touching `mp3_frame_parser`'s arrays at all. Any stage downstream of
`mp3_antialias` (IMDCT included) needs the same treatment: consume side
info forwarded through the value stream, not read fresh from the
top-level per-frame arrays, once its own buffering can span more than
about a frame's worth of upstream production.

Full pipeline (parser + reservoir + Huffman decoder + dequant + stereo +
antialias) real Quartus fit on the `5CSEBA6U23I7`: 3,452 ALMs (8%), 2,248
registers, 63 M10K blocks / 398,374 bits (11%/7%), 26 DSP blocks (23%) --
still comfortably within budget.

## IMDCT + windowing + overlap-add + frequency inversion

`rtl/mp3_imdct.sv`. Implemented from the direct ISO 11172-3 mathematical
definition of the 36-point IMDCT plus its block-type-dependent window,
rather than transcribing FFmpeg's fast IMDCT-36 factorization -- a
deliberate choice, since the goal is a correct, maintainable decode path,
not a bit-for-bit replica of FFmpeg's specific fast-transform algorithm.
Validated by checking *output* against real FFmpeg internals (instrumented
`mpegaudiodec_template.c`, `IMDCTOUT` dumps) via constant-ratio consistency
(ratio mean 0.054970, stdev 1.28e-05 across several consecutive granules --
consistent with the same `IMDCTPRE`-style internal scale factor
(`1/(32/1.759)`) already seen in dequant and antialiasing, not a new
constant), then made bit-exact against `tools/mp3_imdct_reference.py`, a
from-scratch fixed-point Python model of the same direct-definition
transform. `window[block_type][i] * cos(...)` is folded into one
precomputed ROM (`tools/mp3_imdct_rom_gen.py` -> `rtl/mp3_imdct_coeff.hex`,
1944 entries, 18-bit signed) so the MAC loop produces the windowed output
directly, with no separate windowing pass.

**Short blocks are implemented too**, as three 12-point IMDCTs per subband
(one per short window) combined via a 6-sample-shifted overlap-add into
the same 36-wide shape the long-block path produces. The combination
structure -- window `w` occupies output positions `[6+6w, 18+6w)`, so
windows 0/1 overlap-add in `[12,18)` and windows 1/2 overlap-add in
`[18,24)`, with positions `[0,6)`/`[30,36)` getting no new contribution at
all (pure carry-in / pure carry-out) -- was not assumed from general MP3
knowledge, even though it matches the well-known textbook description:
it was derived by hand-tracing FFmpeg's actual fused `imdct12()` +
overlap-add implementation in `compute_imdct()`
(`mpegaudiodec_template.c`) back to this equivalent explicit form, then
confirmed by checking output against real FFmpeg internals the same way
as the long-block path (ratio mean 0.054970, stdev 2.81e-05 across the
short-block-specific subset of a real run -- the identical scale constant
as everywhere else, not a new one). See
`tools/mp3_imdct_reference.py`'s `imdct_short_block_fixed()` docstring for
the full derivation.

The short-block path needed **no new datapath at all**. Since at most 2 of
the 3 short windows ever contribute to a given output position,
`tools/mp3_imdct_rom_gen.py` precomputes a 4th 36x18 combined-coefficient
table (`bt_sel` index 3) with the inactive window's taps simply zero, and
the exact same 18-tap MAC loop that computes a long block's windowed
output computes a short-block output position correctly too, adding
nothing for the zeroed taps. The only RTL changes were: extending
`cur_bt_sel`'s selection logic to pick the short table for short-path
subbands (previously those subbands bypassed the MAC loop entirely via a
now-removed `S_ZERO_FILL` state), and widening the ROM and its address
bus for the extra table (see the bug below).

Confirmed after this input layout also came from hand-tracing FFmpeg's
code, not assumption: after `mp3_stereo`'s `reorder_block()`, a
short-block subband's 18 values are interleaved by window
(`x[3*f+w]` = window `w`'s `f`-th frequency coefficient, `f`=0..5) rather
than grouped as three contiguous sixes -- confirmed directly from
FFmpeg's `imdct12(out2, ptr + w)` call, where `imdct12()` itself reads its
6 inputs with stride 3.

**The first genuinely cross-frame persistent state in this project.**
Every earlier stage's buffering lives and dies within one channel or one
frame; the overlap-add carry (`overlap_mem`, 2 channels x 32 subbands x 18
values = 1152 entries) must survive from one granule to the *next*
granule's decode, indefinitely, reset only on module reset. Also the first
stage whose output is a genuine transpose of its input (input is
subband-major, `sb*18+k`; output must be time-major, `t*32+sb`, the layout
the not-yet-built polyphase synthesis filterbank needs) -- a third 576-
entry buffer holds the transposed result, since the transform can't be
computed in place over the input the way every earlier stage's position-
preserving processing could.

**Five real bugs found during validation (four against the long-block
path, mono test file first, which happened to not exercise two of them;
a fifth against the short-block path once it was added):**

1. `overlap_mem` uninitialized. The very first read of any position happens
   before anything has ever written it; leaving it as simulation-X (or
   real BRAM's undefined power-up state) X-propagated through the combine
   addition and poisoned every output sample of the first channel to touch
   each position. Fixed with an explicit `initial` zero-init for-loop
   (synthesizes as a BRAM with an all-zero `.mif`, the same mechanism as
   `$readmemh` elsewhere in this project -- not a runtime clear-on-reset
   sequence, which would cost real cycles for no benefit over a one-time
   initial value).
2. `bt_sel_of()` read `block_type`/`mixed_block_flag` without gating on
   `window_switching_flag` first. Per the established
   `long_end_of()`/`short_start_of()` convention (`mp3_dequant.sv`,
   `mp3_stereo.sv`), those fields are only ever *written* by
   `mp3_frame_parser` when `window_switching_flag=1`; for the very first
   non-window-switched granule in a stream they're still X (never written
   at all), and comparing them directly propagated that X through the ROM
   address, poisoning the whole granule. Fixed by adding a `wsf` parameter
   to `bt_sel_of()` and gating both comparisons on it.
3. `ov_addr` (the overlap-memory read/write address) was a registered
   (`<=`) signal set inside the `S_COMBINE_ISSUE` state body rather than
   driven combinationally. The dedicated registered-read process reads
   whatever the address held *before* the current clock edge regardless of
   which always-block sets it -- with a registered address, that meant
   every combine-step's read reflected the *previous* iteration's overlap
   position, one full step stale. This was the most consequential of the
   four: it silently produced wrong values for practically every access,
   masked in the test content by most overlap values being zero except at
   the very first-ever access (which showed as literal X, initially
   mistaken for bug 1 alone). Fixed by making `ov_addr` a pure
   combinational `wire`, so the address issued in `S_COMBINE_ISSUE` is
   exactly what's ready by `S_COMBINE_WRITE`, the same discipline as
   `fsm_addr`/`ob_addr` elsewhere in this module. **General lesson for any
   future stage**: any RAM read address a downstream cycle depends on must
   be combinational, driven straight from state/counters -- never set via
   a registered assignment inside an FSM state body, since the "issue this
   cycle, use next cycle" mental model doesn't account for the dedicated
   read process itself sampling the address's pre-edge value.
4. **2-deep buffering was insufficient for stereo.** Every earlier stage
   gets away with double-buffering (one channel processing, one more
   allowed to queue behind it) because each stage's own processing time is
   comfortably close to its input's production rate. That assumption
   breaks here: this module's own per-channel processing (~44,000 cycles,
   the 32-subband x 36-tap x 18-k MAC loop) is dramatically slower than
   everything upstream, and a single *stereo* frame completes four
   channels (2 granules x 2 channels) in the time this module drains just
   one. With only 2 queue slots / 2 physical input buffers, the 3rd and
   4th channel of a stereo frame could arrive before the queue ever
   drained once: the 3rd trigger silently overwrote the still-unpopped
   queue entry left by the 1st channel (that channel's data simply gone --
   surfaced as a "missing" granule/channel in comparison output), and the
   4th trigger's incoming `value_valid` writes landed in the same physical
   buffer bank still being re-read every cycle by the in-progress MAC loop
   for the 1st channel, corrupting a handful of its samples mid-read
   (surfaced as a numeric mismatch, not a missing result). A mono-only
   test file (max 2 channels/frame) never exercises this path, which is
   exactly why it passed bit-exact long before stereo was tried. Fixed by
   widening to 4-way buffering (4 physical 576-entry input buffers, 4-deep
   pending queue) -- the true worst case for this fixed profile (2
   granules x max 2 channels), not a margin-of-safety guess: a new frame's
   channels can't start arriving until the current frame fully drains
   through this module in real operation (bit-rate-limited input pacing
   gives roughly 26ms/frame vs. roughly 3.5ms to drain 4 channels), so
   in-flight channels never span a frame boundary.
5. **`rom_addr` stayed an 11-bit wire after the short-block table was
   added.** Addresses are `bt_sel*648 + out_i*18 + k`; with 3 block types
   the max address was 1925, comfortably inside 11 bits (max 2047). Adding
   the short table as `bt_sel=3` pushed the max address to 2591, which
   silently wrapped every address >= 2048 back into `bt_sel=0`'s table,
   pulling garbage coefficients into short-block subbands at higher
   `out_i` values. Symptom pointed straight at the cause once looked for:
   comparing RTL against `tools/mp3_imdct_reference.py` on a real
   short-block granule showed low `out_i` positions (small addresses)
   matching exactly and higher ones diverging sharply -- an address-space
   boundary effect, not a math error, since a real math bug would have no
   reason to respect an address value rather than an `out_i` value. Fixed
   by widening `rom_addr` (and the intermediate arithmetic constants) to
   12 bits. **General lesson**: widening a ROM's logical content (adding a
   table variant, extending a range) requires re-checking every address
   computation's bit width, not just the storage array's declared size --
   the array width alone doesn't fail to compile or simulate when the
   *address* wire is too narrow, it just silently wraps.

Validated bit-exact (RTL vs. `tools/mp3_imdct_reference.py`, all 576
values per granule/channel, long- and short-block subbands both) across
all 8 profile test files (mono/stereo x 128k/192k x 44.1k/48kHz), plus a
200-frame deep run on `mono_128k_44100.mp3` covering both of that file's
real short-block granules (a MP3 encoder transient at frame 1, and a
second one later in the file, not just the first occurrence).

Full pipeline (parser + reservoir + Huffman decoder + dequant + stereo +
antialias + IMDCT, short-block path included) real Quartus fit on the
`5CSEBA6U23I7`: 3,712 ALMs (9%), 2,518 registers, 99 M10K blocks / 574,054
bits (18%/10%), 29 DSP blocks (26%). Adding real short-block support
actually *reduced* ALM count slightly versus the long-block-only version
(removing the `S_ZERO_FILL` bypass state more than offset the wider
address bus) and added only 5 more M10K blocks (the short table's extra
648 ROM entries) -- the short-block path reuses the long-block path's
entire datapath, so it was essentially free in resource terms. Still
comfortably within budget.

## Undefined-behavior conditions (informational only, never checked)

Listed here so anyone reusing this decoder in another project knows the
actual contract, even though none of these are detected or guarded against
in hardware:

- Anything not MPEG-1 Layer III.
- VBR, ABR, or free-format bitstreams (bitrate index changing frame to
  frame, or bitrate index 0).
- Any bitrate other than 128/192 kb/s, or sample rate other than 44.1/48 kHz.
- Dual-channel mode.
- A corrupted or truncated stream (no CRC checking, no sync-loss recovery).
