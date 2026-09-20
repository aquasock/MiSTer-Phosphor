# Build qualification

The living record of Phosphor's builds: what was built, how it closed timing, what
was accepted on hardware, and where the artifacts came from. The build procedure is
in [BUILD.md](BUILD.md). MiSTer-Raster keeps the same kind of record.

## Summary

| # | Date | Build | Selected seed | RBF SHA-256 | Hardware status |
|---|---|---|---:|---|---|
| 1 | 2026-09-19 | Title/artwork fix for playlist entries 100 and above | 61 | `31ea7828…e9a` | Hardware validation passed (owner-reported) |
| 2 | 2026-09-20 | **Current source:** fix plus reset exemption in the SDC and the `Phosphor` project rename | **87** | `7ca53338…8121` | Not yet tested on hardware |

Build 1 is the validated release, `Phosphor_20260919.rbf`. Build 2 is what the
repository builds today; it has been compiled and timing-swept but not deployed.
Neither result is a claim of complete board-I/O timing coverage (see
[Timing coverage](#timing-coverage-and-limits)). Every hardware statement here is
the owner's report; no agent-run playback is claimed.

## Current source (build 2)

Quartus Prime Lite 17.0.2 Build 602, Cyclone V `5CSEBA6U23I7`, project revision
`Phosphor`, HIGH ALM register packing, six fitter threads. The source is the
repository at `ddb6106` plus the title/artwork fix, the corrected SDC and the
project rename. All three seeds compiled. Worst slack in ns across the eight
corners (slow and fast 1100 mV at -40, 0, 85 and 100 C):

| Seed | ALMs | RAM blocks | DSP | Setup | Hold | Recovery | Removal | Pulse width | Result |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 52 | 35,599 | 543 | 111 | +0.216 | +0.046 | +4.022 | +0.260 | +0.396 | Pass, zero TNS |
| 61 | 35,607 | 543 | 111 | **-0.160** | +0.090 | +3.700 | +0.254 | +0.396 | **Fails setup** (TNS -0.225) |
| **87** | 35,685 | 543 | 109 | +0.136 | +0.075 | +3.199 | +0.160 | +0.396 | Pass, zero TNS |

Seed 87 is pinned: it has the best minimum margin across the five categories
(+0.075 ns, against +0.046 ns for seed 52, whose hold margin is thinnest). Seed 61,
the seed of build 1, no longer closes setup on this source. Seed 87 uses 35,685 of
41,910 ALMs (85%), 543 of 553 RAM blocks (98%), 109 of 112 DSP blocks and 5 of 6
PLLs.

Unlike build 1, this fit sees the reset exemption from the start (see
[BUILD.md](BUILD.md#asynchronous-reset-paths)), so placement differs from the
validated bitstream and the seed ranking changed. Bitstreams (local, not in the
repository), 4,455,380 bytes for seed 87:

| Seed | SHA-256 |
|---|---|
| 52 | `9b4da565c01351e979b1d0c97df16c3e1d5218ab02fce0077454542410d9df47` |
| 61 | `f41a498cdfd74baa6acf011f3167f77a3a22948c49c96ac2057f8ed8d05d909d` |
| **87** | `7ca533386a8e2cb60f8249ba0173209ed921e4aee95e1dd96c350e95da578121` |

The build stamp inside the bitstream is the build date (`260920`). After the
`Phosphor.qsf` cleanup (398 to 63 lines, see [CHANGELOG.md](CHANGELOG.md)) and a
comment-only edit, seed 87 was rebuilt the same day and produced the same bitstream
byte for byte (SHA-256 `7ca53338…8121`) with identical resources, so the cleanup does
not change the design.

## Validated release (build 1)

Built from `ddb6106` plus `title-artwork-fix.patch` in an isolated copy. The old
metadata mux switched from M3U titles to FLAC/artwork at address 3240, which is
both the first artwork address and entry 100's virtual title address. The renderer
now supplies an explicit artwork-request bit (`metadata_artwork_request`), delayed
alongside the synchronous RAM read. Mixed-playlist titles use M3U memory through
entry 255; artwork and standalone FLAC keep their existing layout. No decoder,
audio or PLL logic changed.

| Seed | ALMs | RAM blocks | DSP | Setup | Hold | Recovery | Removal | Pulse width |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 52 | 35,537 | 543 | 111 | +0.042 | +0.092 | +3.942 | +0.112 | +0.396 |
| **61** | 35,550 | 543 | 111 | +0.448 | +0.098 | +3.962 | +0.189 | +0.396 |
| 87 | 35,687 | 543 | 109 | -0.038 | +0.036 | +3.779 | +0.214 | +0.396 |

Seeds 52 and 61 qualified; 87 failed setup (TNS -0.528). Seed 61 was selected.
Bitstream `Phosphor_20260919.rbf`: 4,459,916 bytes, SHA-256
`31ea7828503f146278ea20632b98c6859b4818f8d8e7bd3a7007f4ddd92e8e9a`, 35,550 ALMs,
543 RAM blocks, 111 DSP blocks, 5 PLLs.

**Post-fit constraint correction.** The first eight-corner sweeps failed recovery
into the native-audio reset and status synchronizers under the 44.1 and 48 kHz
audio clocks (worst recovery slack -9.9, -9.8 and -9.7 ns for seeds 52, 61 and 87;
TNS about -870 ns each). The paths end on `CLRN` pins of four synchronizer chains
that assert asynchronously and release synchronously, and the existing SDC listed
only some of the reset sources. The correction exempts only those 12 `CLRN` pins;
D-pin and stage-to-stage release timing remain enabled, and a focused check
confirmed the first-stage path is still timed (+39.5 and +43.1 ns setup at the
default corner). It changed no HDL, clock or netlist: the bitstream was not refit,
and timing was re-analyzed against the same fits. Recovery then passed with +3.78
to +3.96 ns. The original fit-time SDC and both source manifests are preserved in
the build folder.

**Checks on build 1.** The actual `Various.tar`: all 105 title records and lengths
match the playlist; exact rendered glyphs for entries 100 to 105 (including Trigun,
U2 and vcr). A synthetic 255-entry playlist: every title and length and the final
six rendered rows. Every cover-art byte and every rendered cover pixel match the
archive. Alternating title and artwork requests at one address verify the read
latency. Standalone FLAC keeps selecting its own metadata source.

**Hardware.** The build's own records still said "hardware validation pending". The
owner has since reported that it passes all hardware validation.

## Timing coverage and limits

Passing summaries establish closure for the constrained paths, not complete
board-level interface sign-off. The inherited external-I/O constraint limitations
(unconstrained interface ports and missing input and output delays, as in
MiSTer-Raster's audit) remain; no separate Phosphor audit figures are recorded here.
The reset exemption above changes no other constraint, and no clock frequency was
changed.

## Artifacts and provenance

Local paths, on the build machine only (not in the repository):

| Build | Location |
|---|---|
| 1 | `phosphor-title-fix-build-15a0_7gr/hardware-test-seed61/`: `Phosphor_20260919.rbf`, source archive `Phosphor_title_fix_source.tar.gz`, `title-artwork-fix.patch`, checksums, per-seed timing reports and the fit-time SDC. Every file in its `SHA256SUMS`, and all 210 source-manifest entries, were re-verified on 2026-09-20. |
| 2 | `phosphor-3seed-build/seed*/output_files/Phosphor.rbf` with `timing_results.json` |

Release copies are named `Phosphor_YYYYMMDD.rbf` and installed to
`/media/fat/_Other/`.

## Adding an entry

After a full three-seed build and eight-corner sweep: add a row to the summary
table and a section with the seed table (ALMs, RAM blocks, DSP blocks, the five
slacks, TNS), the selected seed's resources, the artifact's size and SHA-256, and
the source commit. Record hardware status only as the owner reports it, with the
date.
