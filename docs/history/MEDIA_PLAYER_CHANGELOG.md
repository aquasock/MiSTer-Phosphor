# MiSTer Media Player changelog (legacy)

History of the MiSTer Media Player project (v0.1.0 to v0.9.5, August to September
2026), the common ancestor of MiSTer-Raster and MiSTer-Phosphor. It is kept for
reference and describes features Raster no longer has (DVD navigation, interlaced
480i, AC-3, standalone FLAC and visualizers). The Phosphor changelog is
[../CHANGELOG.md](../CHANGELOG.md).

## [0.9.5] - 2026-09-15 — Native-FPGA playback, visualizers and FLAC album milestone

Replaces the ARM-helper/DVD-navigation path from v0.7.0-v0.9.0 with playback
implemented entirely in FPGA logic: MPEG-2 Program Stream video with MP2
audio, standalone/album FLAC with CUESHEET track navigation, SRT subtitles,
a transport UI, and three native audio visualizers (Waveforms, FFT, O-Scope).
No HPS software or soft CPU is involved in the playback path.

- Release package: `MiSTer-Phosphor_v0.9.5.zip`, 2,098,997 bytes,
  SHA-256 `da1c8766d79b8184b467213e6e125a1a45c41c28ad3d5c2f9e98b2396fae02fa`.
- Source commit `1720960`, reorganized without RTL changes by the preceding
  Project Refresh; the qualified RBF reproduces byte-for-byte identical to
  the pre-reorganization `68f32c7` seed61 build.
- Clean Quartus Prime 17.0.2 build, fitter seed 61, HIGH ALM register
  packing: 35,817 / 41,910 ALMs (85%), 51,622 registers, 546 / 553 RAM
  blocks (99%), 75 DSP blocks, 4 PLLs. RBF: `MediaPlayer_20260915.rbf`,
  4,520,032 bytes, SHA-256
  `7ca9345347c88f689860a6fd6a0d13cdbc43019cbe678dfee4c73508fa3393fc`.
- All four TimeQuest sign-off corners pass with zero total negative slack:
  Slow 1100mV 100C +0.236/+0.237/+3.468/+0.561 ns, Slow 1100mV -40C
  +0.127/+0.166/+3.574/+0.482 ns, Fast 1100mV 100C +2.926/+0.133/+4.848/
  +0.262 ns, Fast 1100mV -40C +3.526/+0.045/+5.105/+0.179 ns (setup/hold/
  recovery/removal); minimum pulse width +0.925 ns on every corner. Two
  exploratory seeds (11, 12) were also swept and both fail setup on at
  least one slow corner; seed 61 remains the qualified candidate.
- The project owner accepted this exact RBF on the test MiSTer, covering
  the XY O-Scope, FFT peak-hold, Fire-block rendering, track-first audio
  UI, FLAC album navigation/seeking, aspect-correct audio graphics and the
  standing MPG/FLAC regression set.

### Changed

- **DVD-authored navigation and ARM-helper decode are no longer part of
  this core.** v0.9.0's disc/ISO menu navigation (libdvdnav), and its
  helper-decoded WAV/FLAC/Ogg Vorbis playback, are replaced outright by the
  native FPGA MPEG-2 Program Stream/MP2 path and native FLAC/album decode
  above. There is no helper binary, patched Main, or DVD launcher in this
  release.
- Add `tools/create_mpg.txt` (the project's ffmpeg Program Stream recipe,
  with quality/frame-rate/aspect variants) and `tools/pack_flac_album.py` /
  `tools/unpack_flac_album.py` (bundle adjacent tracks into a CD-format
  embedded-CUESHEET album FLAC, and split one back into numbered tracks).

- Double O-Scope to 256 by 256 positions using eight phosphor levels and 24
  M10Ks. Preserve native stereo mapping, square aspect geometry and short
  seven-sweep trails. Pipeline geometry and RAM fading for HDMI timing.
- Register resolution-derived Waveforms/FFT geometry.

- Show audio track progress before album progress on initial playback and
  natural track changes (three seconds each). Pause/resume and manual seeks
  show only three seconds of track progress, with track-relative seek previews.

- Shorten XY O-Scope phosphor persistence from fifteen to eight decay sweeps
  while preserving stereo geometry and the 128 by 128 drawing buffer.

- Add a green-phosphor stereo XY **O-Scope** with fading connected traces.
  Rename the original ribbons **Waveforms** and spectrum bars **FFT**. Move
  the FFT baseline to the viewport bottom while keeping the UI above it, and
  add thin red peak-hold markers with slow decay.

- Audio F1–F8 shortcuts divide the current track, independent of the display
  phase. Video retains its three-second UI and whole-video section shortcuts.

- Quantize Fire into separate spectrum blocks: one solid orange cap per band, yellow below, with no band or color blending.

- Add F1–F8 shortcuts to eight equal runtime section starts for known-duration video and audio, retaining pause and existing seek behavior.

- Audio and video playback controls now hide after three seconds of inactivity; Ctrl+Alt+Left/Right seeks backward/forward one minute.

### FFT Fire visualizer

- Add the audio-only Visualizers submenu with O-scope (the existing two ribbons)
  and Fire. Fire uses an original 256-point stereo FFT with a Hann window, 32
  frequency bands, logarithmic intensity and procedural flame rendering.
- Share the native post-volume tap, selected aspect rectangle and nine-cycle
  renderer boundary. Keep audio transport, player UI and stock OSD independent.
- Add reproducible coefficient generation, exact FFT oracles, full-frame
  renderer checks and RTL previews. Hardware-accepted with this release.

### Audio-mode menu controls

- Gray out Color matrix, Refresh rate and all Subtitles controls while native
  audio is active. Restore access on EOF or video replacement without changing
  saved settings; keep Aspect ratio available for the audio graphics.

### Audio graphics aspect ratio

- Fit the native audio waveform and player UI to the scaler's selected 4:3 or
  16:9 picture rectangle. Keep fonts integer-scaled, clip graphics to that area,
  and preserve full HDMI timing. Movie graphics retain their existing layout.

### FLAC album navigation and seeking

- Add N/P navigation through embedded CD CUESHEET INDEX 01 positions and video-style
  arrow seeks (+/-10 seconds, Ctrl +/-30 seconds, Ctrl+Alt +/-5 minutes) to FLAC.
  Track changes and seeks preserve pause, restart at a preceding FLAC seek point,
  and discard CRC-checked preroll to the exact target sample. Without a seek table,
  decoding starts from the first frame; unknown total sample counts disable seeking.
- Keep album-relative progress times and clear navigation state on media replacement.
  Bound the optional block-RAM index to 99 CD tracks and 512 seek points.

### Native music waveform visualizer

- Split waveform RAM reads, sample differences and interpolation products into separate pipeline stages, retaining aligned RGB/sync timing. Use HIGH ALM register packing by default for subsequent builds.

- Add cyan/orange stereo waveforms from post-volume native PCM, behind the player UI and OSD. A four-sample average and 256-point history provide a roughly 23 ms window; a frame snapshot prevents tearing. Silence and pause flatten the traces, and media replacement clears history. Movie pixels retain an aligned bypass path.
- Add asynchronous waveform simulation, complete-frame constant-signal pixel checks and 480p/720p/1080p previews, plus native-output tap ordering checks. Hardware-accepted with this release.


### Added

- Subtitles submenu with SRT loading, Yes/No visibility and directly selectable
  Offset/Speed pages: -5.0 to +5.0 seconds in 0.2-second steps and 0.50x to
  1.50x in 0.02x steps. Each page offers 51 values with the default first.
  Timing changes reload the subtitle reader without changing movie playback.

- First standalone native 44.1 kHz/16-bit stereo FLAC hardware candidate:
  content-based mounted-file selection, CRC-admitted DDR frames, exact PCM
  clock crossing, native HDMI/I2S/SPDIF and analog outputs, volume, Space pause,
  source-sample times and drained EOF. Preserve movie decoding and filtering;
  FLAC seeking and additional music processing remain later gates.

- Return to startup after physical EOF and drained audio/video, with a final-frame
  hold, pause/seek protection and generation-safe replacement-file handling. Clear
  subtitles, duration and controls without retaining a resume position.

- Manual SRT loading through a second stock Main file slot, with presentation-
  timed cues, pause/seek synchronization and an independent shared-overlay
  visibility group. Initial display supports two lines of printable ASCII.

### Fixed

- Normalize UTF-8 curly apostrophes, double quotes and en/em dialogue dashes
  (plus Windows-1252 equivalents) to existing ASCII subtitle glyphs instead
  of question marks.
  Truncated UTF-8 sequences no longer consume characters from the following line.

- Scope native audio power-up reset timing exceptions to the asynchronous
  reset-release chains, including fitted reset-source duplicates; verify that
  every synchronizer release stage remains timed.

- FLAC-to-MPG replacement deadlock: inactive movie memory requests remain
  quiesced while the handoff checks physical DDR readiness, allowing drained
  music ownership to return to video.

### Changed

- Scale overlay glyphs by exact 1x/2x/3x factors at 480p/720p/1080p, retain
  full 64-character subtitle lines, and center a taller progress bar beneath
  the subtitle area with its black time text centered vertically.

- Rename the picker to Load media with MPG and FL* filters; stock Main displays
  Load media *.MPG,FL* while retaining normal .flac filename support.

- Share one unchanged IDCT arithmetic engine across intra/P/B clients, using
  immediate uncontended capture and bounded per-client coefficient staging
  for overlap, with reset cancellation and per-client completion/error routing.

- Remove Audio test menu and hardware; connect movie PCM directly to outputs
  and reserve old status bits 1–3. Retain functional playback audio and filters.
- Draw all three clocks in black on the progress bar, remove Paused/Seeking
  labels and rendering logic, and lower the bar/subtitles one logical text line.

- Diagnostic-removal gate two removes reporting connections/crossings and
  legacy LED-success wiring, with named functional scheduler drain outputs.
  Keep live decode/transport protection and Audio test; retain standalone
  simulation observations and require fitted reporting registers to be absent.
- Remove the inactive MPEG2FPGA reference tree and its two unused wrappers;
  preserve provenance in documentation and Git history.

- Diagnostic-removal gate one removes the cadence profiler and telemetry screen
  from the production core, preserving functional seek/EOF checks and Audio test.
- Draw Paused/Seeking as opaque black glyphs with transparent gaps instead of
  dark text on a white inset; keep their progress-bar position unchanged.

- Allow 1 ms of audio timestamp lateness in the diagnostic warning, avoiding
  startup warnings from the measured 167 us PES timestamp step in Fellow/Groove.
  Audio samples, cadence and underrun detection are unchanged.

- Place time fields below the progress bar, Paused/Seeking on the bar with
  contrasting lettering, and subtitles two lines lower following hardware
  acceptance of manual SRT playback.

- Move Paused/Seeking down one text line and place subtitles directly above it.
  Complete the existing font ROM's printable ASCII character set.

- Lower the playback progress bar and three clocks by one bar height; show
  clock values without Elapsed, Total or Remaining prefixes.

- Store each IDCT's intermediate transform results in eight synchronous M10K
  row banks. Column-ahead prefetch preserves arithmetic, output order and cycle
  timing while replacing register storage. Hardware accepted with seed 52;
  actual placed ALMs fall from 37,790 to 35,774, using 24 additional M10Ks
  (508 of 553 total).

### Fixed

- Infer duration between sparse MPEG picture timestamps using presentation-order
  references, including reordered B-pictures and following groups without new
  timestamps. Groove and three other real-file tail checks match decoded video
  endpoints. Head/tail reads stay bounded; insufficient evidence remains unknown.

- Seeking now retires the stopped display reader's retained DDR bank protection
  after outstanding reads drain. This allows reconstruction to reuse the bank
  instead of stalling until its watchdog expires. Normal display and pause
  protection remain active. Hardware-accepted with this release.

### Added

- Shared post-filter HDMI player overlay with the DVD-era progress bar and
  Elapsed, Total and Remaining fields. Pause and seek feedback auto-hides after
  ten seconds; the stock MiSTer menu stays above the player UI.
- Bounded head/tail timestamp duration preflight through the existing mounted
  file reader. Unavailable duration displays `--:--:--` and a patterned track.
- Frame-atomic glyph/rectangle scenes and retained provider interfaces for
  future subtitles. Subtitle loading and cue selection are not implemented.
- Full-frame overlay pixel, scene lifetime, duration and response-retirement
  regressions. FPGA timing/resource and hardware qualification are pending.

- Direct timestamp-guided MPG seeking in both directions, including unseen
  destinations, with bounded byte-position probes and nearby reconstruction.
- Partial MP2 frame resynchronization and open-GOP leading B-picture removal
  at direct restart, with movie timestamp origin retained across seeks.
- Direct seek control, real-file probe, byte-filter and PCM recovery regressions.

- Exact-MPG combined replay harness with simulation audio-bypass comparison.
  The captured display-bank ownership freeze is addressed by the fix above.

- Space toggles play/pause; Left/Right seek backward/forward by 10 seconds,
  Ctrl by 30 seconds, and Ctrl+Alt by 5 minutes. Menu navigation is excluded.
- Transactional reconstruction seeks retain the requested paused state and
  clamp at the start/end of media. MPG uses direct file seeking; raw streams
  and missing restart timestamps retain reconstruction from the beginning.
  MP2 audio before the destination bypasses synthesis with a full frame of
  decoded preroll to restore filter history. Long seeks can still take time.
- Seek completion waits for the final restarted reader, preventing a stale
  completion from the old decoder session during storage retirement.

- Compact 25-word telemetry schema 10 retains playback errors, basic cadence, audio and transport health while removing detailed performance history from default synthesis; compile-time detailed schema 9 remains available.
- Screenshot decoding supports compact and legacy profiles, marks omitted diagnostics unavailable, and reports the correct final checksum word for each schema.

- Manual 59.94/50 Hz progressive refresh selection with unchanged 720x480 active video, frame-boundary switching, and exact untimestamped cadence at both rates; audio and PTS clocks retain playback speed. Hardware accepted, with visibly smoother 29.97 fps motion at 59.94 Hz.
- Deterministic 25/29.97 fps motion and stereo flash/beep checks from `tools/make_refresh_tests.py`.

- Frame-associated BT.601/BT.709 color matrix selection with Auto and manual OSD overrides; untagged or unsupported matrices retain the BT.601 compatibility fallback.
- Deterministic matching color clips and exhaustive RGB conversion tests, including exact legacy BT.601 output and BT.709 error bounded to one RGB code value.

- Stock-Main mounted MPG/M2V playback using bounded sector reads, leaving menu input available during playback; OSD and filter control validated on hardware.
- Coordinated playback-session restart with DDR response draining, exact byte/EOF transport, startup prefill, and reader offset/suspension interfaces for later pause and seeking.
- Telemetry schema 9 reports file-read requests/completions, maximum response wait, byte position, session generation, reservoir minimum and transport status; decoder retains older capture support.

- FPGA MPEG-1 Layer II decoding for 48 kHz stereo MPG, serialized subband
  synthesis, PCM timestamp scheduling and an independent DDR video reservoir.
- PES-to-picture timestamp binding and audio frame/sample/error telemetry.
- FFmpeg audio-oracle regressions and an executable A/V flash/beep test script.

### Fixed

- Make the aspect menu explicitly select 4:3 or 16:9, entirely under user control and independent of sequence metadata.
- Register B-frame fetch coordinates before address arithmetic and distribute the scaler's final fraction calculation across existing pipeline stages without changing filter precision or alignment.
- Register resolution-change blanking with the same assertion/release cycles to shorten the scaler control-to-pixel path.

- Enumerate every available Quartus operating corner in timing reports instead of relying on `-multi_corner` with file output.
- Hide Main's loading-message overlay once playback starts, preserving normal menus.
- Preserve configuration and VS synchronizer flip-flops through synthesis and
  transfer platform aspect and scaler mode settings into their consuming clocks.

- Keep HS/VS/DE continuous across frame-buffer bank resets, preventing extra
  negative-sync pulses during progressive playback.
- Transfer OSD and aspect settings through acknowledged clock-domain mailboxes;
  synchronize system-clock VS edge detectors and remove configuration gating
  from the HDMI adjustment circuit's input video clock.
- Align telemetry coordinates with the framebuffer RGB/DE pipeline.

### Changed

- Restore the P/B parser row buffers to synchronous block memory, with byte
  prefetch and rollover shadow registers, to recover logic capacity.

- Remove the diagnostic Seek audio bypass menu option; normal compressed-audio
  bypass with decoded preroll remains enabled during seeks.

- Remove the added persistent seek-fault snapshot, clock-domain mailbox and
  screen renderer from production hardware to recover placement capacity.
  Compact playback-health telemetry and historical screenshot decoding remain.

- Pause preserves queued movie PCM, sample phase, the displayed frame and the
  shared media clock while keeping raster, OSD and filters responsive.
- Raw elementary EOF now closes an unterminated sequence for final-frame drain.
- Cadence telemetry restarts its observation window after deliberate pause/seek.

- Restore progressive video from `a57079f` using stock MiSTer Main. Source
  `9233f07` seed 52 was hardware-accepted with the generated 30-second MPG.
- Source `1750154` seed 87 passed all timing classes and the user's playback
  test, using 40,132 ALMs and 470 RAM blocks. Seed 61 also passed timing;
  seed 52 exited with a Quartus fitter crash.
- Replace the 800x600 raster with progressive-only 720x480 at 60000/1001 Hz
  using a 27 MHz pixel clock. Retain 60 MHz decoding and FPGA MP2 audio.
- Center smaller pictures, align DE/sync with the RGB cache pipeline, adjust
  the blanking swap window and fallback cadence, and fit telemetry within
  480 lines. Native output hardware qualification remains pending.
- Source `ace6b7b` seed 87 passed the user's synchronized flash/beep playback
  test. Telemetry confirmed 1,250 MP2 frames, 1,440,000 stereo sample pairs,
  clean completion and zero error flags; one 106.6 ms video gap was recorded.
  Static setup timing still missed by 0.131 ns.
- Remove legacy LED blink diagnostics and disable the unused Linux ALSA path,
  explicitly tying inactive audio and memory-request inputs to zero. Retain
  screen telemetry and the FPGA MP2 playback path.
- Limit ASCAL output image width to 2048 pixels, retaining 1920x1080 support
  while eliminating the extended-width line-buffer path.
- Capture detailed HDMI/ASCAL setup and global hold paths with each timing run.
  Resource savings and timing qualification of this cleanup remain pending.
  Earlier DVD/helper/custom-Main implementations remain in Git history.

## [0.9.0] - 2026-09-03 — DVD navigation, native video and consumer-audio milestone

Encrypted ISO and direct USB-disc DVD-Video playback with authored menus,
expanded native 480i decoding, native 480p, file/audio seeking, standalone
consumer audio, the MPEG-2 visualizer and production telemetry.

- Release package: `MiSTer_Media_Player_v0.9.0.zip`, 6,580,818 compressed
  bytes, SHA-256
  `e8bc8e0c25291df85d6d53ad2688995d30ce156c547b7315b08058052863e1f9`.
  Its 16 files total 10,476,902 uncompressed bytes; all 15 manifest entries and
  ZIP integrity pass, and Main/helper retain executable mode.
- The project owner accepted the exact runtime set through functional and
  regression testing and directed that it be packaged without rebuilding.
  The source-`dfe1057` RBF was already a clean, reproducible, timing-qualified
  Quartus build; package assembly preserves every accepted artifact byte for
  byte.

### Added

- Added authored DVD first-play and root-menu navigation for ISO images and
  direct `/dev/sr0` playback. The helper follows libdvdnav menu state, decodes
  DVD subpicture RLE and authored CLUT/alpha/highlight data, and sends bounded
  double-buffered overlay records to a native-480i FPGA compositor. Main maps
  player-one D-pad/A/Start/Select and keyboard arrows/Enter/M to directional,
  activate and root-menu controls through the existing ready/go barrier.
- Added longest-title playback from decrypted or CSS-encrypted DVD ISO files.
  The static helper pins libdvdcss 1.6.0 beneath libdvdread/libdvdnav, with no
  target-installed shared-library dependency and no Main or FPGA change.  ISO
  PTS epochs are normalized across VOB or cell clock restarts so long-title
  audio scheduling remains continuous, and longest-title playback ends after
  one declared traversal instead of following post-title navigation commands.
- Added direct longest-title playback from the absolute USB optical-device path
  `/dev/sr0`, using the same pinned CSS, navigation, timestamp and audio paths
  without requiring an ISO image or filesystem mount.
- Added player-one Left/Right previous and next chapter controls for DVD ISO and
  direct optical playback through a private Main/helper ready-go channel.  The
  helper retains the authenticated navigation handle while both sides flush the
  old byte stream before Main resets the existing FPGA download boundary.
- Added player-one Start pause/resume as an ARM-side transport hold.  It keeps
  the helper and optical navigation session alive without an RBF change; a long
  pause may still set the FPGA's existing audio-underrun telemetry.
- Added keyboard Space play/pause and P/N previous/next chapter bindings, and
  corrected physical player-one Start so it reaches the same Main-side pause
  action without changing the helper or FPGA image.
- Added 720x480 interlaced frame-picture I/P/B decoding with frame or field
  motion, frame or field DCT, repeat-first-field scheduling and mixed ordinary
  interlaced/progressive-film frames. Deterministic fixtures cover the syntax
  and reconstruction paths, and the current timing-qualified RBF has been
  exercised with commercial DVD material.
- Added helper-only RIFF WAVE playback through the existing MediaPlayer picker and PCM transport. Pinned miniaudio source is compiled into the static helper to convert ordinary PCM/float mono, stereo or multichannel WAV input to 44.1 or 48 kHz signed stereo without an FPGA change.
- Added helper-only FLAC playback through the existing MediaPlayer picker and PCM transport. The same statically compiled miniaudio dependency converts 16- or 24-bit mono, stereo or multichannel FLAC input to 44.1 or 48 kHz signed stereo without an FPGA change.
- Added helper-only Ogg Vorbis playback through a dedicated audio picker. The
  miniaudio backend uses pinned stb_vorbis source and converts decoded audio to
  44.1 or 48 kHz signed stereo without a target runtime library or FPGA change.
- Added `.vob` selection and transactional fixed-step seeking for `.mpg` and
  `.mpeg` Program Streams, with 10-second, 1-minute and 5-minute keyboard jumps.
- Added an ARM-rendered standalone-audio interface with elapsed, total and
  remaining time, duration-relative progress, matching fixed-step seeking and
  replay-ready end-of-file behavior.
- Added an optional helper-driven MPEG-2 audio visualizer. Eight validated
  color/brightness grades follow decoded-PCM loudness while the player overlay
  remains visible for ten seconds after playback starts or user input.
- Added default-off production telemetry. Enabling it before playback exposes
  the hardware snapshot and writes the combined Main/helper log to
  `/tmp/MediaPlayer_ARM.log`.

### Changed

- Reorganized the core menu into separate DVD-Video, MPEG-2 video and consumer
  audio pickers; made 16:9 the default aspect ratio while retaining 4:3; and
  kept the existing Bob/Weave, Audio Test and Audio Output choices.
- Chapter changes now retain the established Program Stream codec and DVD
  private audio substream. AC-3 decode performs a bounded 64 KiB rescan and
  decoder reinitialization after a rejected boundary frame instead of exiting
  playback or selecting a different track because its PES arrived first.
- Native 480i ownership now remains active when an interlaced sequence moves
  between ordinary interlaced and progressive film frame pictures. Per-picture
  field order and repeat metadata drive film scheduling after that transition;
  field pictures and existing syntax, timing and decoder-error gates remain
  rejected.
- Direct USB-DVD playback now reuses its authenticated libdvdnav session across
  helper preflight rewinds instead of reopening and rescanning CSS keys. After
  preflight it reads through an 8 MiB asynchronous HPS-RAM ring with a 4 MiB
  launch reserve, insulating playback from transient optical-read stalls
  without consuming FPGA memory or changing file and ISO paths.
- Replaced the old progressive diagnostic raster with native 720x480p output at
  `60000/1001`, while supported interlaced material retains native 480i output.
- Made clean `.mpg`, `.mpeg` and standalone-audio EOF retain the final display
  in a paused replay-ready state; Play restarts the same file from its beginning.
- Hardened direct optical playback with session reuse, interruptible output
  discard and staged transitions for slow or picture-bearing authored menus.
- Preserved DVD menu state across overlay-only submenus, finite and indefinite
  stills, unsupported private audio, scene-page changes and title/menu returns.
- Skip unsupported DVD LPCM/private audio without terminating navigation, so a
  silent LPCM menu can still lead to a title with supported audio.
- Added a narrowly gated helper compatibility normalization for malformed DVD
  4:2:0 progressive-frame chroma flags, including repeated authored stills;
  conforming streams remain byte-identical.
- Reconciled current release, build, architecture and test guidance with the published v0.8.0 package; labelled older design and regression instructions as historical.
- Corrected v0.8.0 tag provenance, compressed ZIP size, the role of patched Main, and the distinction between a targeted hardware pixel comparison and comprehensive playback qualification. Runtime code, the release tag and packaged binaries are unchanged.

## [0.8.0] - 2026-08-27 — Interlaced 480i, AC-3 and passthrough milestone

Bounded 720x480 interlaced all-I playback with native 480i presentation, AC-3 decode, and AC-3/DTS passthrough to S/PDIF.

- Published as a pre-release on 2026-08-27 at 17:41:16 America/Phoenix. Annotated tag `v0.8.0` resolves to `af43de2`; all three runtime binaries use source baseline `2f1d32c`. The standalone release notes were added in later documentation commit `035807a`, without changing the tagged runtime source.
- Public package: `MiSTer_Media_Player_v0.8.0.zip`, 2,867,028 compressed bytes, SHA-256 `5f55b49eb863f74a777b548b4f42b744a9130b4161f176b687ca297deeffcaf3`. Its uncompressed members total 5,948,567 bytes. The downloaded ZIP and payload hashes match the qualified package.
- A clean from-scratch Quartus Prime 17.0.2 build reproduced the tested RBF byte-for-byte: 4,332,740 bytes, SHA-256 `61a2fed28425a461c8b886bdf809e3ef76a320e5688bb22a816135c36ef981ce`, fitter seed 17.
- The clean fit uses 31,464 ALMs (75%), 50,273 registers, 4,048,355 block-memory bits (71%), 512 RAM blocks (93%), 67 DSP blocks, and 3 PLLs.
- Timing is positive in every required category with zero total negative slack: +0.243 ns setup, +0.251 ns hold, +2.865 ns recovery, +0.564 ns removal, +0.925 ns minimum pulse width.
- The fitter seed moved from 16 to 17. At seed 16 the framework scaler's horizontal accumulator missed setup by 0.070 ns once the audio routing added logic; that path retains little margin and is a known risk for future changes.
- All three binaries were rebuilt from source baseline `2f1d32c` and reproduced byte for byte: the RBF from a clean export of tracked files only, and the helper and Main from a wiped dependency directory with a freshly extracted toolchain.
- ARM helper SHA-256 `f6206ba01459eefcc40b26d3d5b3b6ca4f70e496fbeadc317254f86f19f370c8`.
- Patched Main SHA-256 `01a15750476f3616385fe98dee2d4d832f34823df5ddfc7098966a5b786efad9`, built from pinned upstream `0a8fb44` with ARM GNU 10.2.
- Added liba52 0.7.4 as a pinned dependency for AC-3 decode, fetched by `host/build_arm_stack.sh` with its archive SHA-256 verified, and shipped its licence alongside minimp3's.
- Host regressions pass on the release binaries: cadence decoder layout, eleven DVD ceiling tests, and the Main integration profile including 168 RTL cases, 96 burst cases, 20 step-resume cases and guarded fault cases.
- Audio regressions pass on the release helper: AC-3 decode against an independent decoder at maximum sample difference 3 and correlation 0.999999972, correct downmix placement for all six channels including LFE absence, byte-identical passthrough bursts, and the unchanged MPEG Layer II PCM hash on the full-length fixture.

- Added a bounded 720x480 4:2:0 interlaced all-I frame-picture path with frame DCT, consistent TFF/BFF preservation, and native 480i timing.
- Added two explicit interlaced presentation tiers: MiSTer scaler processing with selectable Weave/Bob, and untouched native 480i for `direct_video`, external processing, and eventual HDMI-to-SDI conversion.
- Removed a redundant 64-clock inverse-quantization block replay by streaming finalized coefficients directly into the idle IDCT, restoring full-D1 all-I throughput headroom for 29.97-fps material without changing decoded pixels.
- Added AC-3 decode in the ARM helper through a pinned liba52 dependency, on DVD private stream 1 substreams `0x80`-`0x87`, downmixed to stereo using the stream's own coefficients. Verified against an independent decoder on both synthetic fixtures and a commercial DVD track, the latter confirming that dynamic range control is applied.
- Added AC-3 and DTS passthrough to S/PDIF as IEC 61937 bursts, so an external decoder receives the original bitstream. Verified byte-identical on synthetic fixtures and a commercial DVD track. DTS is passthrough only; a DTS track selected for HDMI output is refused rather than played as silence.
- Added an `Audio output` menu option selecting HDMI or S/PDIF, muting the output it does not drive, and forked the framework audio path so a passthrough burst reaches the S/PDIF pin unaltered and is announced as non-PCM.
- Fixed S/PDIF selection for decoded MP2, MP3, WAV and FLAC: decoded samples now use ordinary PCM channel status, while only AC-3/DTS IEC 61937 bursts are announced as non-audio.
- Added a set of seven hand-test Program Streams covering interlaced TFF and BFF field order, Bob versus Weave deinterlacing, progressive all-I and progressive I/P/B, and AC-3 and DTS 5.1 channel sweeps.
- Confirmed on hardware that the progressive path decodes I, P and B pictures, correcting an earlier description of the decoder as accepting I-pictures only; that restriction applies to the interlaced 480i path.
- Reduced Main's media-transfer event-loop occupancy, which had reached about 160 ms per poll on low-bitrate material and made the menu sluggish; measured maximum poll time fell by roughly seventeen times and the acknowledged-write fallback disappeared.
- Known limitation recorded: sharp colour transitions show one blended pixel column that an independent software decoder does not produce, and playback pixel accuracy remains unqualified.
- A targeted hardware-screenshot pixel comparison measured that chroma-edge difference; earlier wording that all pixel comparisons were simulated was incorrect. Comprehensive playback pixel qualification remains open.
- The hand tests used the released RBF/helper hashes; the final Main was separately exercised after the initial six-test capture. A confirmation run after installation from the final package remains unrecorded. Publication and package verification do not close that gate.

## [0.7.0] - 2026-08-24 — Program Stream audio and PTS milestone

Hardware-qualified bounded MPEG-2 Program Stream playback with MPEG Layer II audio, real picture-PTS scheduling, and a matching MiSTer ARM helper.

- Added a pinned, reproducible ARM helper that accepts raw MPEG-2 Video or bounded MPEG-2 Program Streams, preserves video bytes exactly, extracts picture PTS, decodes MPEG Layer II audio, and sends packed video/PTS/PCM records to the FPGA.
- Added a matching pinned MiSTer Main patch that invokes `/media/fat/linux/MediaPlayer_Helper` for Media Player files while preserving the existing raw-file path.
- Added 44.1 and 48 kHz signed stereo PCM playback through an 8,192-frame FPGA FIFO, with bounded startup and steady-state batching, explicit end markers, underrun/error telemetry, and clean no-reboot recovery between silent and audio-video files.
- Added a clean-video queue so decoder backpressure cannot block PCM delivery and cause periodic audio/video disturbance.
- Made Program Stream picture PTS drive the FPGA 33-bit / 90 kHz presentation timeline. Encoded H.262 cadence remains a mandatory floor, so PTS can delay a frame but cannot present it early.
- Extended native presentation pacing through H.262 frame-rate codes 4 and 5: exact `30000/1001` and exact 30 fps, alongside the existing `24000/1001`, exact 24, and 25 fps paths. Codes 6 through 8 are rejected before transport.
- Added deterministic Program Stream finalization, compatibility checks, input-envelope generation, helper transport analysis, PCM comparison, protocol verification, and native/sanitized host regressions.
- Qualified the full 14,315-picture Big Buck Bunny audio-video soak, including opening motion, high-motion scenes, transitions, and rolling credits. The final cadence-floor build completed without the recurring one-second credits jump.
- Passed the final four-file release gate on the exact packaged binaries: power-cycle 48 kHz audio-video startup, no-reboot video-only playback, no-reboot 44.1 kHz audio recovery, and a fresh-boot full-movie soak. Every run completed with normal LEDs and zero aggregate, decoder, presentation, PCM protocol, or underrun errors; the soak recorded zero credits-window cadence outliers.
- Preserved raw `.m2v` as a byte-exact path with synthetic H.262-derived presentation timing and clean terminal behavior.
- Release FPGA source baseline: `9a5eea3`; host/helper source baseline: `acdbf8b`.
- A clean Quartus Prime 17.0.2 build reproduced the accepted 4,184,380-byte RBF exactly, with SHA-256 `484328e51c6e764890bf2bdcd947448e2eaaaac2c603e93da28009475e44dafc`.
- The clean fit uses 29,325 ALMs, 45,259 registers, 3,655,139 block-memory bits, 464 RAM blocks, 65 DSP blocks, and 3 PLLs.
- Timing is positive in every required category: +0.311 ns global setup, +0.238 ns hold, +3.365 ns recovery, +0.497 ns removal, +1.122 ns minimum pulse width, +1.782 ns decoder setup, +11.294 ns decoder recovery, and +8.284 ns video setup.
- Reproducible release helper: 361,452 bytes, SHA-256 `c99237246416ecd8278d90ff6e15e7a00cd8ab1d49c960b8c77fbe00f4ba0483`.
- Reproducible matching Main: 1,166,244 bytes, SHA-256 `16517a9927c659616796b45c8e2488da2a26f0595c91418ed09dc0eb7a5787aa`.
- The release package contains the date-coded RBF, matching Main, executable `linux/MediaPlayer_Helper`, checksums, source provenance, installation instructions, and applicable licenses. Generated regression media is not shipped.
- Current limits remain deliberate: progressive 4:2:0 video through the qualified 720x480 envelope, MPEG Layer II audio at 44.1/48 kHz, bounded Program Stream structure, fixed 800x600 output, and no seeking, pause/resume, Transport Stream, DVD navigation, subpictures, or optical-disc integration.

## [0.6.0] - 2026-08-22 — Real-stream MPEG-2 playback milestone

Hardware-qualified sustained playback of progressive 720x480 4:2:0 MPEG-2 Video elementary streams, with native `24000/1001`, exact-24-fps, and 25-fps presentation cadence.

- Reworked compressed-data ingress around a 16-bit MiSTer host path and a 32 KiB mixed-width asynchronous FIFO while retaining 8-bit decoder consumption and explicit backpressure.
- Raised the decoder clock from 54 MHz to 60 MHz and pipelined the real-stream prediction, coefficient, cache, and DDR paths needed to maintain positive timing at the higher rate.
- Extended picture-signaled P forward horizontal/vertical motion-vector `f_code` support from 1..4 to 1..9 with a 13-bit vector datapath, and extended independently signaled B forward/backward horizontal/vertical support from 1..4 to 1..5.
- Corrected long-GOP parsing, reference ownership, pending-future-reference binding, repeated-GOP publication, queued-B presentation, P/B persistence accounting, and final-reference release so streams continue across former stutter points and terminate cleanly.
- Overlapped reference-picture decoding with B-picture presentation while preserving retained-bank ownership, B scratch storage, display order, blanking-aligned publication, and protected DDR access.
- Added native H.262 frame-rate-code 2 pacing for exact 24 fps and exact rational frame-rate-code 1 pacing for `24000/1001`, alongside the existing accepted frame-rate-code 3 / 25-fps path.
- Added hardware cadence telemetry for accepted byte counts, decoded/reference/B picture counts, presentation swaps, measured frame rate, sequence-end state, decoder errors, and cadence-gap outliers.
- Qualified a focused four-stream hardware gate covering P skip/motion, B prediction, repeated multi-slice pictures, and the high-motion large-picture/long-GOP scene that originally exposed compressed-input starvation.
- Completed visual endurance qualification with the full native-rate Big Buck Bunny movie and a separate 642 MB real-world 720x480 progressive `24000/1001` stream. Both completed with smooth motion, no perceptible speed error, and no observed recurring stutter or frame-drop defect.
- Release-candidate source baseline: `b64ec6a`. A preserved incremental Quartus build and an independent clean/from-scratch Quartus Prime 17.0.2 build produced byte-identical RBFs.
- The clean build completed with zero errors and positive timing in every required category: +0.303 ns global setup, +0.386 ns decoder setup, +8.066 ns video setup, +0.244 ns hold, +3.706 ns recovery, +0.768 ns removal, and +1.122 ns minimum pulse width.
- The qualified fit uses 34,565 ALMs, 50,960 registers, 4,306,375 block-memory bits, 538 RAM blocks, and 65 DSP blocks.
- The qualified 4,455,376-byte RBF has SHA-256 `e95e9ec43cb11917d5a904fdd8016bcc23dcbe2d8f36f678544f42ad1a6d5f10`; its release asset name is `MediaPlayer_20260822.rbf`.
- Current limits remain deliberate: raw `.m2v` elementary-stream input, progressive frame pictures, 4:2:0 chroma, the proven 720x480 envelope, synthetic rather than PES-derived timing, fixed 800x600 diagnostic output, and no audio, container/program-stream demux, real PTS, seeking, pause/resume, DVD navigation, or optical-drive integration.
- H.262 frame-rate codes 4 through 8—29.97, 30, 50, 59.94, and 60 fps—remain unpaced and are not supported by this milestone.

## [0.5.0] - 2026-08-17 — 720x480 progressive P/B `f_code` milestone

Hardware-qualified 720x480 progressive 4:2:0 I/P/B regression coverage with independently picture-signaled P/B motion-vector `f_code` handling from 1 through 4.

- Widened the bounded B syntax and raster path to 45x30 macroblocks / 720x480 while retaining separate B scratch storage and coded-order/display-order presentation.
- Generalized B residual parsing across all six 4:2:0 blocks and generalized B macroblock-address increments, escaped gaps, internal skips, and restricted same-row slice coverage within the accepted progressive envelope.
- Replaced the earlier mixed legacy/controlled P acceptance path with deterministic full-width 720x480 generators and completed generalized P parsing, raster execution, reference reads, prediction-plus-residual reconstruction, persistence, publication, and presentation through sequence end.
- Added leading P skips, macroblock-address Escape coverage, up to 32 residual descriptors, full coded-block-pattern coverage, quantiser changes, and visible P-presentation discrimination.
- Generalized P forward horizontal/vertical and B forward/backward horizontal/vertical `f_code` fields independently across values 1 through 4, including zero through three residual bits, both signs, predictor reuse/independence, H.262 wraparound, and chained references.
- Corrected the vendored ASCAL `MODE[4]` width mismatch and pipelined its vertical boundary predicate, preserving positive HDMI timing margin through the final release-candidate build.
- Replaced overlapping playback-time LED indications with a settled post-stream report and aligned acceptance with durable generalized publication/reference completion. Successful streams settle with USER and POWER solid and DISK dark.
- Established the authoritative seven-stream hardware matrix: `test_i_baseline.m2v`, `test_p_motion_residual.m2v`, `test_p_mba_escape.m2v`, `test_b_bidirectional.m2v`, `test_p_visual_discriminator.m2v`, `test_p_f_code_range.m2v`, and `test_b_f_code_range.m2v`. The former nine-stream matrix is not a release gate going forward.
- Hardware qualification accepted all seven streams with the expected LED result and clean images; the P visual discriminator retained all four quadrants and both center seams.
- Release qualification checkout: `424eec43b0d0b4f8085e6591a15543eafab394e7`; synthesized RTL baseline: `b1bde49df3831669b577a1ed78404e026f19382d`.
- The clean GitHub-clone Quartus Prime 17.0.2 build completed with no Critical Warning, zero TNS, +0.387 ns global setup, +0.207 ns global hold, +2.012 ns decoder setup, 31,625 ALMs, 42,223 registers, 592,333 block-memory bits, 90 RAM blocks, 69 DSP blocks, and 3 PLLs.
- The fresh-clone RBF is bit-identical to the already hardware-accepted Commit-194 artifact and has SHA-256 `a3eeeb285c427f313987ce6c62cdef560d6293defb1841e96c66aab026d63d8e`.
- Audio project `fd90c775a129995544ea7aa9d9369408d949ca63` remains integration-compatible.
- Current limits remain deliberate: raw MPEG-2 Video elementary streams, progressive frame pictures, 4:2:0 chroma, the proven 720x480 regression envelope, synthetic rather than PES-derived timing, fixed diagnostic video output, no audio, and no DVD/program-stream navigation.

## [0.4.0] - 2026-08-16 — Progressive 4:2:0 I/P/B milestone

Hardware-qualified progressive 4:2:0 I/P/B decoding and presentation within the current bounded implementation envelope.

- Preserved the hardware-proven continuous progressive 4:2:0 all-I decode, DDR-backed presentation, blanking-aligned publication, and synthetic 90 kHz elementary-stream timing baseline from v0.3.0.
- Generalized P-picture reconstruction around syntax-derived per-macroblock motion and residual execution, including signed horizontal/vertical forward vectors, predictor reuse/reset, H.262 wrap behavior, integer and half-sample interpolation, 4:2:0 chroma-vector scaling, coded-block-pattern handling, sparse residual placement, run/level and Escape coefficient syntax, q_scale_type, alternate_scan, and quantiser-scale changes within the proven regression envelope.
- Preserved consecutive reconstructed-P reference promotion and corrected the publication-versus-presentation destination-ownership race by pacing a following P until its destination retained bank is no longer display-owned.
- Added the first hardware-proven B-picture core path with forward, backward, and bidirectional prediction, internal macroblock-address skips, bounded residual reconstruction, and 128x96 mixed I/P/B deterministic regressions.
- Added a dedicated B scratch DDR region and corrected frame-region identity to use the full two-bit region selector so retained bank 0, retained bank 1, and B scratch remain distinct under display-write protection.
- Added blanking-aligned B presentation/reorder handling that preserves the future P reference while the intervening B picture reconstructs and presents from scratch, then presents the retained future reference in display order.
- Split the large top-level integration into `MediaPlayer_top_00.svh` through `MediaPlayer_top_07.svh` without changing the MiSTer-facing top entity.
- Consolidated the active IDCT arithmetic around a shared multiplier bank, reducing DSP use from the earlier 92-DSP development point to 68 DSP blocks while preserving the accepted regression behavior.
- Added comments-only Audio-fork integration anchors without establishing a permanent ABI or altering synthesized behavior.
- Localized and corrected an intermittent consecutive-P failure to a display/reference destination-ownership race; the temporary first-fault, timeout-phase, writer, cache, and arbiter diagnostic layer was completely retired after the functional fix was accepted.
- Restored normal USER completion behavior after the diagnostic investigation.
- Hardware-qualified RTL baseline: `1370c28e3d34b1fd603c17130986bc336da29a32`.
- Release qualification used a fresh clone of GitHub `master`, Quartus Prime 17.0.2 Lite, the standard Phase 1P timing reports, and the full required MiSTer matrix: 20 consecutive passes of `test_p_consecutive_reference.m2v`, plus passes of `test_b_mixed_gop.m2v`, `test_b_core_decode.m2v`, `test_p_general_decode.m2v`, and `test_all_i.m2v`.
- Qualified fit: 31,782 / 41,910 ALMs (76%), 43,812 registers, 461,345 block-memory bits in 73 RAM blocks, 68 / 112 DSP blocks, and 3 / 6 PLLs.
- Qualified timing: global setup +0.167 ns, hold +0.248 ns, recovery +4.117 ns, removal +0.704 ns, decoder setup +1.311 ns with 0/100 violations, video setup +6.987 ns with 0/80 violations, and setup endpoint TNS 0.
- Current implementation limits remain deliberate engineering bounds: established I-picture coverage reaches 720x480, while the generalized P/B hardware regressions use 128x96 / 8x6 macroblocks. General arbitrary H.262 P/B playback, interlaced/broader picture structures, non-4:2:0 chroma, H.222.0 Program Stream/PES demux and real PTS, audio, and DVD/VOB navigation remain future work.

## [0.3.0] - 2026-08-14 — Phase 1T

Reference-picture management and the first hardware-proven predictive-picture reconstruction paths.

- Preserved the hardware-proven continuous progressive 4:2:0 all-I decode, DDR ping-pong storage, blanking-aligned publication, and synthetic 90 kHz elementary-stream timing baseline from v0.2.0.
- Added reference-picture bookkeeping and controlled reference/destination DDR-bank ownership for predictive-picture work.
- Added P-picture diagnostic syntax, motion-vector, stream-hold, and reference-read paths developed against ITU-T H.262 semantics.
- Added controlled forward-prediction reconstruction paths, including zero-vector reference copying, explicit reference sampling, and the established half-sample interpolation behavior used by the hardware diagnostics.
- Added non-intra P residual parsing, inverse quantization / transform handling, prediction-plus-residual reconstruction, and ordinary DDR persistence for the controlled supported path.
- Extended the controlled P reconstruction proof from one complete 4:2:0 macroblock to two adjacent macroblocks and then to four macroblocks over two raster rows.
- Replaced fixed macroblock-index placement in the four-macroblock path with explicit raster row/column tracking and then fed that path from live coded horizontal geometry using the H.262 `(horizontal_size + 15) / 16` macroblock-width rule.
- Preserved the existing all-I hardware regressions while adding dedicated P-picture regression streams for reference reads, residual reconstruction, two-macroblock placement, and four-macroblock/two-row placement.
- Preserved the Phase 1P timing/CDC discipline throughout the predictive-picture increments.
- Current limitation: P-picture support remains a deliberately controlled hardware-proven diagnostic subset, not general arbitrary MPEG-2 P-picture playback. B pictures are not supported.
- Current input remains raw MPEG-2 Video elementary stream data; H.222.0/MPEG program-stream demux, PES timestamps, audio, and DVD/VOB playback remain future work.

## [0.2.0] - 2026-08-12 — Phase 1S

Continuous all-I playback and presentation-timing foundation.

- Extended the single re-armed H.262 parser from two pictures to continuous supported all-I picture decode.
- Reused the two planar DDR frame banks as a repeated bank 0 / bank 1 ping-pong store.
- Protected the displayed DDR bank from reconstruction writes while it remained owned by the display reader.
- Moved repeated frame publication and framebuffer re-arm into true vertical blanking so active video remains continuous.
- Removed the old asynchronous multi-bit line-number CDC bus; the line-cache handoff now crosses only a synchronized one-bit event and derives source-line identity locally in the DDR clock domain.
- Eliminated all observed playback artifacts from the continuous-all-I diagnostic stream, including mixed-frame distortion, black flicker, the bottom-edge white bar, and faint horizontal line artifacts.
- Added the first presentation-timing metadata foundation using H.262 frame-rate information and `temporal_reference` with a 33-bit 90 kHz representation compatible with later H.222.0 PTS handling.
- Kept the current elementary-stream timing explicitly synthetic: `.m2v` input has no PES layer, so the generated schedule is not represented as a normative PES PTS.
- Hardware acceptance: `test_all_i.m2v` plays to completion with USER completion correct and no observed flicker, tearing, corruption, bars, or other image artifacts.
- Final proven Phase 1S RTL commit before release documentation: `37d6268080d6d14f2e2e2d91345bc4a0132747ee`.
- Final proven Phase 1S Quartus fit at that commit: 11,349 / 41,910 ALMs (27%), 18,231 registers, 63 / 553 RAM blocks (11%), and 55 / 112 DSP blocks (49%).
- Final focused timing at that commit: decoder setup +4.838 ns, video setup +7.945 ns, decoder recovery +15.683 ns, video recovery +21.572 ns, all with TNS 0; hold and removal checks are positive.

## [0.1.0] - 2026-08-12 — Phase 1R

First hardware-proven milestone release.

- Added an alternate DDR frame bank for the second decoded picture.
- Added explicit DDR arbitration so display reads and reconstructed-frame writes can safely share the MiSTer DDRAM interface.
- Preserved picture 1 on screen while picture 2 is decoded and stored in the alternate bank.
- Made the parser wait for DDR persistence on both pictures so second-picture completion means the full frame has been stored.
- Added controlled framebuffer re-arm and frame-bank publication after picture 2 completes.
- Proved a visible picture 1 -> picture 2 transition on MiSTer hardware.
- Hardware acceptance: USER completion correct, stable color output, no tearing observed, and no flicker observed.
- Final Quartus fit: 11,342 / 41,910 ALMs (27%), 18,142 registers, 63 / 553 RAM blocks (11%), and 55 / 112 DSP blocks (49%).
- Final focused timing: decoder setup +5.265 ns, video setup +7.619 ns, decoder recovery +16.147 ns, video recovery +21.712 ns, with TNS 0; hold and removal checks are positive.
- Published GitHub pre-release tag: `v0.1.0`.
- MiSTer binary asset: `MediaPlayer_20260812.rbf`.

## Phase 1Q — Successive I-picture decode

- Proved two consecutive supported I-picture decodes in hardware.
- Reused a single proven H.262 parser by locally re-arming it between pictures.
- Kept picture 1 stored/displayed while picture 2 traverses parser, inverse quantization, IDCT, and reconstruction.
- Removed an earlier duplicated-parser diagnostic that introduced slight color-image flicker.
- Hardware acceptance: both diagnostic streams pass, image is stable, USER completion behavior is correct.

## Phase 1P — Timing and CDC closure

- Closed the real 54 MHz decoder and 40 MHz video timing paths.
- Pipelined and balanced inverse-quantization and IDCT arithmetic where required.
- Synchronized reset release independently in each destination clock domain.
- Enabled synchronized DCFIFO asynchronous-clear handling.
- Narrowed timing exceptions to intentional synchronizer boundaries rather than broad clock-domain false paths.
- Final accepted setup and recovery reports had zero total negative slack on the decoder and video clocks.

## Phase 1O — Full-precision DDR frame storage and readback

### Phase 1Oa

- Added full-precision planar Y/Cb/Cr DDR3 writes.
- Serialized block persistence so the parser could not advance until reconstructed block data reached DDR.
- Kept the existing on-chip framebuffer active temporarily to isolate DDR-write verification.

### Phase 1Ob

- Removed the large full-picture on-chip framebuffer.
- Added DDR3 readback through small dual-clock ping-pong line caches.
- Restored full 8-bit chroma presentation.
- Moved decoder frame storage away from the MiSTer system-video DDR region after identifying an address collision.
- Reduced M10K use dramatically compared with full-frame on-chip storage.

## Phase 1N — Full color reconstruction

- Added Cb and Cr to the serialized inverse-quantization, IDCT, and reconstruction pipeline.
- Implemented 4:2:0 component storage and BT.601 YCbCr-to-RGB conversion.
- Proved the first complete color picture in hardware.
- Used a temporary reduced-chroma on-chip storage format before the later DDR architecture removed the M10K pressure.

## Phase 1M — Complete first picture

- Continued parsing across all slices of the first supported I picture.
- Correctly reset slice-local DC predictors and macroblock address state.
- Produced the first complete 720x480 grayscale MPEG-2 picture.

## Phase 1L — Complete slice decode

- Removed the temporary fixed macroblock-count stop.
- Decoded an entire slice.
- Used H.262 slice termination rather than assuming a fixed row length.

## Phase 1K — Streaming bitreader

- Replaced the bounded whole-slice capture buffer with a streaming bitreader.
- Added exact byte/bit consumption and FIFO backpressure while downstream arithmetic was busy.
- Removed an implementation capture limit that had previously appeared as a decode failure.

## Phase 1J — Multi-macroblock diagnostics

- Expanded decode beyond the first macroblock.
- Parsed Cb/Cr block syntax sufficiently to advance through consecutive 4:2:0 intra macroblocks.
- Added detailed diagnostics that localized a failure to exhaustion of the temporary slice capture buffer.

## Phase 1I — First full luma macroblock

- Decoded all four Y blocks of the first 4:2:0 intra macroblock.
- Produced a stable 16x16 decoded luma region in hardware.

## Phase 1H — Legacy decoder removed from active build

- Removed MPEG2FPGA and its DDR bridge from the active Quartus design.
- Retained the source tree only as a frozen reference implementation.
- Reduced FPGA resource usage substantially and improved hardware stability.

## Phase 1G — Independent display timing

- Decoupled display timing from the legacy decoder.
- Added a fixed 800x600 / 40 MHz diagnostic timing generator.
- Eliminated raster shifts caused by the earlier timing path.

## Earlier clean-decoder milestones

- Began a standards-driven H.262 decoder.
- Parsed slice and first intra-macroblock syntax.
- Decoded intra DC and AC VLC data, including run/level and end-of-block handling.
- Implemented inverse quantization.
- Implemented a fixed-point two-pass 8x8 IDCT.
- Displayed the first decoded 8x8 luma block.
