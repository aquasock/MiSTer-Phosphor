# Building

Target: Cyclone V `5CSEBA6U23I7` (QMTech DE10-Nano-compatible MiSTer), Quartus
Prime Lite 17.0.2. This is the same flow MiSTer-Raster uses, so the two projects
build and qualify the same way. Build records are in
[QUALIFICATION.md](QUALIFICATION.md).

## Quick start

`Phosphor.qsf` pins **seed 87**, the timing-qualified seed with the best minimum
margin on the current source. The Quartus project is named `Phosphor`, so a build
writes `Phosphor.rbf`; copy it to a dated `Phosphor_YYYYMMDD.rbf` name when
packaging.

```sh
tools/build_seeds.sh /path/to/isolated-output 87       # the pinned seed
tools/build_seeds.sh /path/to/isolated-output          # seeds 52, 61 and 87
```

The script copies the tree (without `.git` or `dist/`) into one directory per seed,
sets the seed, runs `quartus_sh --flow compile Phosphor`, then runs the eight-corner
timing sweep on each. Results land in `timing_results.json`; bitstreams in
`seed*/output_files/Phosphor.rbf`. It needs `quartus_sh`, `quartus_sta` and Python 3
on `PATH`. On the current source seed 52 (+0.216 ns setup) and seed 87 (+0.136 ns)
pass every corner and seed 61 **fails** setup at -0.16 ns, so do not use 61.

`files.qip`, the complete `rtl/` and `sys/` trees, and all referenced `.hex` and
`.mem` initialization files must be present. `sys/build_id.tcl` generates
`build_id.v` automatically before compilation.

## Two levels of build

**Fast sanity check** — analysis and synthesis only (elaborates and maps the design,
no placement or routing). Takes a couple of minutes. Good for catching a typo, a
missing module or a broken instantiation after a source change. It does **not**
produce a working bitstream and says nothing about timing.

**Full build** — the complete compile flow (analysis and synthesis, fit, assembler,
and the flow's own built-in timing pass), producing an actual `.rbf` and `.sof` to
run on hardware. It takes on the order of 15 to 25 minutes per seed on this target
and is what is needed before any hardware claim.

Neither level substitutes for the other: a clean fast check only proves the design
elaborates, and only a full build plus the dedicated timing pass below proves it
meets timing.

## Seeds, and why three

Quartus's fitter uses its seed as the starting point for placement search. A
different seed can produce meaningfully different placement, routing and timing
closure on the *same* source, especially on a design this close to the device's
limits (block RAM at 98% and DSP blocks at 99%). The standard practice is a
three-seed sweep per candidate, then pinning a seed that closes every corner. It is
normal for one of the three to fail; on the current source seed 61 does, although it
was the best seed for the earlier validated build (see below).

Three settings must match for a build to reproduce a previously validated result:

- the seed value,
- ALM register-packing effort (`HIGH`), and
- the parallel-processor count used during fitting (six; `build_seeds.sh` runs
  three seeds concurrently, and changing the count can change fitter scheduling
  and is not guaranteed to reproduce identical placement).

Matching all three reproduces a bit-for-bit identical bitstream from the same
source. This was verified for MiSTer-Raster from a fresh clone; the same flow and
scripts are used here.

## Timing validation beyond the default flow

The compile flow's own timing analysis checks a single operating condition. Real
sign-off needs a dedicated multi-corner pass: every available operating condition
(slow and fast process, voltage and temperature models), each with setup, hold,
recovery, removal and minimum-pulse-width summaries plus detailed worst-path
reports. A design can pass the default check and still fail setup, hold or
recovery at a corner it did not evaluate.

`tools/build_seeds.sh` runs this for you. To run it by hand after a full build,
from that isolated build directory:

```sh
quartus_sta -t tools/check_timing_corners.tcl
```

The script writes the summaries and worst paths to `timing_corners/`. A successful
exit means reports were generated, not that timing passed: inspect every category
at every corner. To sweep several already-compiled seed directories concurrently:

```sh
python3 tools/run_timing_sweep.py /path/to/isolated-build --wait-for-compile
```

Reading the reports: the summary reports list clocks by worst slack, worst first,
so the first data row is the number that matters. The data rows have no leading
space before the first `;`, so splitting on `;` puts the clock name in the second
field and the slack in the third, not the second.

Passing constrained timing is not complete board-I/O sign-off; see the coverage
note in [QUALIFICATION.md](QUALIFICATION.md#timing-coverage-and-limits).

### Asynchronous reset paths

The native-audio reset and status synchronizers (`wr_reset_sync`, `rd_reset_sync`,
`prefill_sync`, `eof_sync`) assert asynchronously and release synchronously. Their
`CLRN` pins are exempted from timing in `Phosphor.sdc` (12 pins, guarded by an
assertion on the match count); D-pin and stage-to-stage release timing stay
enabled. Without that exemption the recovery check fails by about 10 ns at every
seed. The fitter now sees the exemption, so a fresh build can place differently
from the 2026-09-19 validated bitstream, which was fitted before the exemption
reached the SDC and re-analyzed afterwards.

## Known gotchas

- **Do not run the synthesis-only tool directly against the live project for a
  quick check without expecting side effects.** Quartus can write several hundred
  lines of pin and device assignments, normally pulled in through the platform's
  included project fragment, into the top-level settings file. `Phosphor.qsf` once
  carried such a block (335 lines, almost all duplicates, since removed); diff it before
  committing and revert it if it reappears.
- **A killed or interrupted build leaves partial state behind** (fit database,
  incremental database, output files, the generated build-identifier file, a JTAG
  chain file). Clear it before relaunching.
- **The build-identifier file is regenerated on every build** by a pre-flow step
  and carries only a date stamp. It does not affect timing or placement, but the
  date is embedded in the bitstream, so builds on different days differ in those
  bytes only.

## Keeping the source tree clean

Every artifact Quartus produces (fit and incremental databases, all `output_files`,
timing reports, logs, the generated build-identifier file, the JTAG chain file and
the pin-model dump) belongs outside the source tree. Build in an isolated copy, as
`build_seeds.sh` does. `.gitignore` covers that output, and `.gitattributes` stores
every file byte for byte: the framework in `sys/` has mixed line endings, so do not
let an editor or script normalize them.

## Resource ceiling

Both block RAM and DSP blocks are nearly exhausted: the current build uses 543 of
553 RAM blocks (98%) and 111 of 112 DSP blocks (99%) with about 85% of the ALMs.
Budget any new RAM or multiplier use against those ceilings before adding a feature.

## Verification benches

The simulation benches used during development are not part of this repository.
[QUALIFICATION.md](QUALIFICATION.md) records what was verified. Passing simulation
never replaces hardware acceptance of a new bitstream.
