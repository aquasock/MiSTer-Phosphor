# Changelog

All notable changes to MiSTer-Phosphor. Phosphor shares its origin with MiSTer
Media Player (v0.1.0 to v0.9.5); that project's history is kept in
[history/](history/MEDIA_PLAYER_CHANGELOG.md). There is no tagged Phosphor release
yet, so everything below is unreleased. Build results, seeds and hardware
acceptance are in [QUALIFICATION.md](QUALIFICATION.md).

## [Unreleased]

### Fixed

- Mixed-playlist titles for entries 100 to 255. The metadata mux switched from M3U
  titles to FLAC/artwork at address 3240, which is both the first artwork address
  and entry 100's virtual title address; the renderer now supplies an explicit
  artwork-request bit. Standalone FLAC and artwork are unchanged. Validated on
  hardware.
- Recovery timing into the native-audio reset synchronizers. The asynchronous-assert
  `CLRN` pins of the four synchronizer chains (12 pins) are exempted in
  `Phosphor.sdc`; D-pin and release timing stay enabled. No HDL or clock changed.

### Added

- Gapless FLAC album builder: **Album title**, **Album artist** and **Album artwork**
  fields matching the playlist builder. They prefill from the source tracks' tags
  and can be overridden.
- Gapless FLAC album builder: an optional, off-by-default **Convert high-resolution
  FLACs** setting. Stereo 16- or 24-bit tracks above 44.1 kHz are downsampled to
  44.1 or 48 kHz / 16-bit, whichever needs the simpler conversions, with a polyphase
  Kaiser-windowed sinc resampler, TPDF dither, CD-sector CUESHEET markers and
  reported clipping. Tracks already in the target format are copied bit for bit.
- `validate_album.py` accepts 48 kHz albums and checks CD-sector alignment.
- Build tooling: `tools/build_seeds.sh` (isolated per-seed builds plus the timing
  sweep), `tools/run_timing_sweep.py` and `tools/check_timing_corners.tcl`.
- Documentation in `docs/` with a living [QUALIFICATION.md](QUALIFICATION.md).

### Changed

- The Quartus project is now `Phosphor` (it builds `Phosphor.rbf`) and the top-level
  source is `Phosphor.sv`.
- `Phosphor.qsf` pins seed 87 instead of the unqualified default. On the current
  source seeds 52 and 87 pass every timing corner and seed 61 fails setup.
- `Phosphor.qsf` cut from 398 to 63 lines, matching MiSTer-Raster's structure. The
  removed lines were 328 exact duplicates of assignments already made by
  `sys/sys.tcl`, `sys/sys_analog.tcl` and `files.qip` (the Quartus IDE rewrite
  described in [BUILD.md](BUILD.md#known-gotchas)), three unused source entries
  (`media_playlist_index`, `media_cue_index`, `media_cue_metadata`, which nothing
  instantiates; the three files are deleted) and three HPS location lines. The functional `SYNTHESIS` macro is
  kept. A rebuild of seed 87 produced a byte-identical bitstream.
- Comments in `Phosphor.sv`, `files.qip` and `Phosphor.sdc` that named the wrong
  project as the source of reused files now refer to the former MiSTer Media Player.
  Comment text only; the code is unchanged.
- `.gitignore` (Quartus output, generated files, `dist/`) and `.gitattributes`
  (every file stored byte for byte, so no tool rewrites line endings).

## Earlier history

From the repository's git history:

- 2026-09-19: restructure; architecture merge with MiSTer-Raster.
- 2026-09-18: preliminary MP3, Ogg, WAV and FLAC support.
- 2026-09-17: gapless FLAC, progress bar and visualizers; visualizers added;
  README with format support and resource details; debug release.
- 2026-09-16: MP3 Huffman transfer, IMDCT, CBR support verified.
- 2026-09-15: initial commit.
