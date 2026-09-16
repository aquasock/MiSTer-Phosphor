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
