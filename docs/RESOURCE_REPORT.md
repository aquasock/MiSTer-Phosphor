# MiSTer MP3 FPGA Resource Report

Generated from the final Quartus fit completed on 2026-09-17 at 07:52 local
time. This report describes the build containing FLAC album support, all three
pre-split HDMI/analog visualizers, the ordered O-Scope sample FIFO, the 2x
O-Scope half-band reconstruction filter, and the FLAC-CUE transport/status UI.

## Build identification

| Item | Value |
|---|---|
| Quartus | Prime Lite 17.0.2 Build 602 |
| Revision | `MiSTer_MP3` |
| Top-level entity | `sys_top` |
| FPGA | Cyclone V 5CSEBA6U23I7 |
| Timing model | Final |
| Fitter status | Successful |
| Full compilation | Successful, 0 errors |
| Source base commit | `653c414` (`Visualizers Added`) |
| RBF size | 3,352,072 bytes |
| RBF SHA-256 | `c31bd5718aa4bd5c54cf32f6083ae9952e0111ed39a4c0bcc96ae2f1f40cf730` |

The resource and O-Scope FIR/FIFO changes documented here are newer than the
listed source-base commit and may still be uncommitted in the working tree.

## Current utilization

| Resource | Used | Available | Utilization | Remaining |
|---|---:|---:|---:|---:|
| ALMs | 18,259 | 41,910 | 44% | 23,651 |
| Registers | 25,165 | — | — | — |
| Block-memory bits | 1,583,062 | 5,662,720 | 28% | 4,079,658 |
| M10K blocks | 238 | 553 | 43% | 315 |
| DSP blocks | 82 | 112 | 73% | 30 |
| PLLs | 4 | 6 | 67% | 2 |
| Pins | 145 | 314 | 46% | 169 |

DSP blocks are the most heavily used resource at 73%. There are still 30 DSP
blocks available. Logic and memory both retain substantial headroom.

## Feature progression

These figures are full board-level fits, so small ALM/register changes between
nearby builds can reflect fitter packing variation.

| Build stage | ALMs | Registers | M10Ks | DSPs | PLLs |
|---|---:|---:|---:|---:|---:|
| MP3 only | 11,271 | ~15,038 | — | — | 3 |
| MP3 + WAV | 11,577 | — | — | — | 3 |
| + FLAC | 13,512 | 16,686 | 191 | 67 | 4 |
| + FLAC albums | 14,354 | 18,074 | 196 | 67 | 4 |
| + three pre-split visualizers | 15,952 | 21,549 | 226 | 77 | 4 |
| + ordered 256-entry XY FIFO | 15,928 | 21,554 | 227 | 77 | 4 |
| + 2x XY half-band FIR | 16,161 | 21,909 | 227 | 78 | 4 |
| + FLAC-CUE transport/status UI | 18,357 | 25,147 | 238 | 82 | 4 |
| + post-seek FLAC FIFO prefill | 18,283 | 25,177 | 238 | 82 | 4 |
| + album-first UI and CUE repeat (current) | 18,259 | 25,165 | 238 | 82 | 4 |

### Measured O-Scope improvements

| Change | ALMs | Registers | M10Ks | DSPs |
|---|---:|---:|---:|---:|
| Ordered XY FIFO | -24 | +5 | +1 | 0 |
| 2x half-band FIR | +233 | +355 | 0 | +1 |
| FIFO + FIR versus pre-FIFO build | +209 | +360 | +1 | +1 |

The negative FIFO ALM delta is fitter variation, not negative physical logic.
The meaningful FIFO cost is one M10K. The FIR shares one multiplier across
both stereo channels and therefore consumes one DSP block.

## Timing closure

All reported timing checks are positive with zero total negative slack.

| Check | Worst-case slack |
|---|---:|
| Setup | +0.428 ns |
| Hold | +0.248 ns |
| Recovery | +3.713 ns |
| Removal | +0.546 ns |
| Minimum pulse width | +0.396 ns |

The native video clock is exactly 25.2 MHz. With the 800x525 total raster it
produces exactly 60 Hz, matching the HDMI cadence and providing conventional
640x480p60 timing for analog output.

## Generated artifact

The corresponding test image is
`output_files/MiSTer_MP3.rbf`. Resource figures come from
`output_files/MiSTer_MP3.fit.summary`; timing figures come from
`output_files/MiSTer_MP3.sta.rpt`.
