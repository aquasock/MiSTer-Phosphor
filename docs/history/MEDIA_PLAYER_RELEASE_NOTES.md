# MiSTer Media Player release notes (legacy)

Release notes for MiSTer Media Player v0.4.0 to v0.9.5, the common ancestor of
MiSTer-Raster and MiSTer-Phosphor, joined newest first and otherwise unchanged
apart from one heading level. File names, runtime layouts and features described
here (`MediaPlayer_*.rbf`, the ARM helper, DVD, FLAC, visualizers) are historical.

- [v0.9.5](#mister-media-player-v095-release-notes)
- [v0.9.0](#mister-media-player-v090-release-notes)
- [v0.8.0](#mister-media-player-v080-release-notes)
- [v0.7.0](#mister-media-player-v070-release-notes)
- [v0.6.0](#mister-media-player-v060-release-notes)
- [v0.5.0](#mister-media-player-v050-release-notes)
- [v0.4.0](#mister-media-player-v040-release-notes)


---

## MiSTer Media Player v0.9.5 release notes

v0.9.5 replaces the ARM-helper/DVD-navigation path introduced in v0.7.0-v0.9.0
with playback implemented entirely in FPGA logic: MPEG-2 Program Stream video
with MP2 audio, standalone or embedded-CUESHEET album FLAC with full track
navigation, SRT subtitles, a transport UI, and three native audio visualizers.
No HPS software or soft CPU is involved in the playback path.

This remains a developer-oriented pre-release with a deliberately bounded
subset rather than general MPEG-2 systems or DVD conformance.

### Highlights

- Native FPGA FLAC album playback: embedded CD CUESHEET/SEEKTABLE parsing,
  N/P track navigation, and video-style keyboard seeking (+/-10s, Ctrl
  +/-30s, Ctrl+Alt +/-5min), all in RTL with no HPS involvement.
- Three native audio visualizers sharing the post-volume PCM tap: Waveforms
  (dual-trace oscilloscope), FFT (quantized spectrum blocks with red
  peak-hold markers), and O-Scope (green-phosphor stereo XY vectorscope
  with genuine multi-level phosphor decay).
- Track-first audio transport UI: three seconds of track progress before
  album progress on playback start and natural track changes; pause, seek
  and F1-F8 (which now always divide the current track) show track-only
  feedback.
- Audio graphics respect the selected 4:3/16:9 aspect ratio, and video-only
  menu entries (Color matrix, Refresh rate, Subtitles) gray out during
  native audio playback.
- `tools/create_mpg.txt` documents the project's ffmpeg Program Stream
  recipe (quality/frame-rate/aspect variants); `tools/pack_flac_album.py`
  and `tools/unpack_flac_album.py` bundle adjacent tracks into a CD-format
  embedded-CUESHEET album FLAC and split one back into numbered tracks.

### Changed from v0.9.0: DVD/ARM-helper path removed

**DVD-authored navigation and ARM-helper decode are no longer part of this
core.** v0.9.0 added encrypted/decrypted DVD ISO and direct-disc playback
with authored menus (via libdvdnav) and helper-decoded WAV/FLAC/Ogg Vorbis
audio. None of that remains: there is no helper binary, no patched Main, and
no DVD launcher file in this release. Program Stream `.mpg`/`.mpeg` video and
FLAC audio are decoded natively in the FPGA instead. Anyone relying on DVD
disc/ISO playback or the ARM-helper audio formats (WAV, Ogg Vorbis) should
stay on v0.9.0 until/unless that capability returns in a later release.

### Required runtime files

This release is FPGA-only — there is no Main patch or helper to match.

| Release file | Size | SHA-256 |
| --- | ---: | --- |
| `MediaPlayer_20260915.rbf` | 4,520,032 | `7ca9345347c88f689860a6fd6a0d13cdbc43019cbe678dfee4c73508fa3393fc` |

Copy the RBF to the SD card root alongside `menu.rbf`, same as any other
MiSTer core; see `INSTALL.md` for the full walkthrough.

### Supported v0.9.5 subset

- MPEG-2/H.262 progressive 4:2:0 video up to 720x480, full I/P/B-picture
  support including B-picture display-order reordering, at any of H.262's
  eight standard frame rates.
- MP2 audio: MPEG-1 Layer II, 48 kHz, stereo/dual-channel/joint-stereo,
  demuxed from the Program Stream.
- FLAC: standalone files and embedded-CUESHEET albums, fixed 44.1 kHz/
  16-bit/stereo profile, full subframe/residual/stereo-decorrelation syntax.
- SRT subtitles: bounded streaming parser, adjustable timing offset and
  playback speed, two lines of 63 characters.
- Audio visualizers: Waveforms, FFT, O-Scope (see `docs/VISUALIZERS.md`).

### Known limitations

- This remains a pre-1.0 compatibility release, not complete MPEG-2
  conformance.
- No DVD ISO/disc navigation, no ARM-helper audio formats (WAV, Ogg
  Vorbis) — see the DVD/ARM-helper removal note above.
- Interlaced/field-structured video, non-4:2:0 chroma, resolutions above
  720x480, and non-default quantization matrices are valid H.262 this
  decoder does not implement.
- FLAC and MP2 audio are both fixed to a stereo-only profile; mono is not
  accepted by either.
- Subtitles are plain-text SRT only, with in-line formatting tags stripped
  rather than rendered.

### Reproducible qualification

- FPGA toolchain: Quartus Prime Lite 17.0.2 Build 602, fitter seed 61, HIGH
  ALM register-packing effort, 6 parallel processors.
- Source commit `1720960`. The preceding Project Refresh reorganized file
  layout and documentation without changing RTL content; this build's RBF
  is byte-for-byte identical (SHA-256 above) to the pre-reorganization
  `68f32c7` seed61 build.

### Quartus and timing

- Fit: 35,817 / 41,910 ALMs (85%), 51,622 registers, 4,158,522 / 5,662,720
  block-memory bits (73%), 546 / 553 RAM blocks (99%), 75 / 112 DSP blocks
  (67%), 4 / 6 PLLs (67%).
- All four TimeQuest sign-off corners pass with zero total negative slack:

  | Corner | Setup | Hold | Recovery | Removal | Min pulse width |
  | --- | ---: | ---: | ---: | ---: | ---: |
  | Slow 1100mV 100C | +0.236 ns | +0.237 ns | +3.468 ns | +0.561 ns | +0.925 ns |
  | Slow 1100mV -40C | +0.127 ns | +0.166 ns | +3.574 ns | +0.482 ns | +0.925 ns |
  | Fast 1100mV 100C | +2.926 ns | +0.133 ns | +4.848 ns | +0.262 ns | +0.925 ns |
  | Fast 1100mV -40C | +3.526 ns | +0.045 ns | +5.105 ns | +0.179 ns | +0.925 ns |

- Two exploratory seeds were also swept from the same source: seed 12 fails
  setup on the Slow 1100mV -40C corner (-0.068 ns); seed 11 fails setup on
  both slow corners (-0.124 ns, -0.139 ns). Seed 61 is the only one of the
  three that closes timing on every corner and remains the qualified
  candidate.

### Hardware evidence

The project owner accepted this exact RBF on the test MiSTer, covering the
XY O-Scope, FFT peak-hold markers, Fire-block spectrum rendering, track-first
audio transport UI, FLAC album navigation and keyboard seeking, aspect-correct
audio graphics, and the standing MPG/FLAC regression set.

### Packaging

`MiSTer-Phosphor_v0.9.5.zip` contains the RBF, `tools/` (the ffmpeg
recipe and FLAC album pack/unpack scripts), `INSTALL.md`, `SOURCE.txt`
(build provenance), `SHA256SUMS`, and the project license.

- ZIP size: **2,098,997 bytes**.
- ZIP SHA-256: `da1c8766d79b8184b467213e6e125a1a45c41c28ad3d5c2f9e98b2396fae02fa`.
- Uncompressed member total: 4,553,165 bytes across 9 entries (8 files, 1
  directory). All `SHA256SUMS` entries pass and ZIP integrity reports no
  errors.


---

## MiSTer Media Player v0.9.0 release notes

v0.9.0 is the DVD navigation, native-video, consumer-audio and playback-control
milestone. It advances the v0.8.0 native-480i foundation into practical DVD
ISO and direct optical-disc playback with authored menus, expands interlaced
I/P/B decoding, replaces the progressive diagnostic raster with native 480p,
and adds a complete standalone-audio experience.

The project owner accepted the complete runtime set through functional and
regression testing. The release package is ready for the owner to attach to the
annotated `v0.9.0` GitHub pre-release; no tag or release was created during
package preparation.

### Highlights since v0.8.0

- Play decrypted or CSS-encrypted DVD-Video from `.iso` images or a USB drive
  exposed as `/dev/sr0`. DVD libraries and CSS support are linked into the
  helper; MiSTer does not need a separately installed `libdvdcss` package.
- Use authored first-play, root and submenu navigation with button highlights,
  scene-selection pages and automatic actions. DVD stills and overlay-only
  transitions retain an interactive, stable presentation.
- Navigate with player-one D-pad/A/Start/Select or keyboard arrows/Enter/M;
  use player-one Left/Right or P/N for chapters and Start or Space to pause.
- Decode 720x480 interlaced frame-picture I, P and B video with frame or field
  motion and DCT modes, field-order metadata, repeat-first-field scheduling and
  mixed ordinary-interlaced/progressive-film frames. Field pictures and 576i
  remain outside the implementation envelope.
- Present progressive video as native 720x480p at `60000/1001` and supported
  interlaced video as native 720x480i at `30000/1001`.
- Seek ordinary `.mpg` and `.mpeg` files by 10 seconds, 1 minute or 5 minutes;
  `.vob` files are now visible in the MPEG-2 picker.
- Play standalone MP3, WAV, FLAC and Ogg Vorbis through a 720x480 player screen
  with elapsed, total and remaining time, progress, fixed-step seeking and
  clean replay from the beginning after EOF.
- Use the optional MPEG-2 visualizer pack during standalone audio. Its eight
  color/brightness grades track PCM loudness, the player interface remains as
  a translucent scanline-style overlay for ten seconds after user activity,
  and animation cadence remains constant while playing or paused.
- Enable production telemetry only when needed. Telemetry defaults Off; On
  exposes the hardware snapshot and creates `/tmp/MediaPlayer_ARM.log` for the
  next playback.

### DVD behavior

The release uses libdvdnav for first-play and authored-menu state. Stream hops
cross a private helper/Main READY/GO barrier that drains old data, resets the
download session and prevents stale bytes from entering the next menu, still,
scene or title. Direct optical playback reuses its authenticated navigation
session and reads through an 8 MiB HPS-RAM ring with a 4 MiB startup reserve to
absorb normal drive stalls.

Unsupported DVD LPCM and other unsupported private-audio substreams are skipped
rather than treated as fatal. A menu authored with LPCM can therefore remain
interactive but silent and then transition to a title with supported AC-3,
MPEG audio or DTS passthrough. DVD LPCM is not decoded in v0.9.0.

Some commercial discs contain a nonconforming 4:2:0 progressive-frame chroma
flag in authored stills. The helper contains a narrow, syntax-validated
compatibility normalization for that one-bit contradiction, including repeated
sequence boundaries. It does not change conforming streams or alter the FPGA
decoder's H.262 validation rules.

### Required runtime set

The package contains a matching date-coded RBF, patched `MiSTer`, executable
`linux/MediaPlayer_Helper`, and optional
`linux/MediaPlayer_Visualizer.mmpvis`. Direct USB-disc playback additionally
uses `games/MediaPlayer/USB DVD Drive.dvd`. The RBF, Main and helper must remain
a matched set; standalone audio falls back to its ordinary interface when the
visualizer is omitted.

The v0.9.0 runtime set combines:

- timing-qualified RBF source `dfe1057`, built as
  `MediaPlayer_20260901.rbf`;
- patched Main source `3689cca`;
- visualizer/interface source `932dc22`, using the native-interlaced visualizer
  pack introduced at `366a227`;
- final helper compatibility source `0f1165c`.

The exact packaged runtime artifacts are:

| Release file | Size | SHA-256 |
| --- | ---: | --- |
| `MediaPlayer_20260901.rbf` | 4,480,236 | `6389fa57b2d642b5b4e85980c6ccf8746ea8d20869cbe480f80b0ea172bcdb4b` |
| `MiSTer` | 1,182,692 | `1b3387170083be269831bf4c3a828f1cce6bcb3b93c519d8cde32cb9768bedf9` |
| `linux/MediaPlayer_Helper` | 966,052 | `613d35de5ace0622584ae14b4540423c2c56b1f923c02c599f47b55722e21e56` |
| `linux/MediaPlayer_Visualizer.mmpvis` | 3,740,562 | `448407cdd7e6c79fbe13cbb435241116127f726aca5af9f99d75b32fc2519f47` |
| `games/MediaPlayer/USB DVD Drive.dvd` | 111 | `4757d49e9d1b94d88f554b3bd3157ed5d2064caaa65a6cf0f856e8ab6fbe2d2e` |

The project owner directed that these accepted artifacts not be rebuilt during
packaging. Their bytes match the previously tested files exactly. The
source-`dfe1057` RBF was already produced by a clean, reproducible Quartus
build; the package's `SHA256SUMS` is authoritative for every member.

### FPGA qualification

The unchanged source-`dfe1057` RBF was built with Quartus Prime Lite 17.0.2 and
fitter seed 24. It completed with zero errors and positive timing in every
required category: +0.180 ns setup, +0.190 ns hold, +3.758 ns recovery,
+0.644 ns removal and +0.925 ns minimum pulse width, with zero violated paths.
Dedicated 60 MHz decoder and 54 MHz video setup margins were +1.220 ns and
+2.215 ns. The fit used 34,859 ALMs, 54,492 registers, 4,187,219 block-memory
bits in 536 RAM blocks, 70 DSP blocks and 3 PLLs.

That RBF is 4,480,236 bytes with SHA-256
`6389fa57b2d642b5b4e85980c6ccf8746ea8d20869cbe480f80b0ea172bcdb4b`.
This is the existing clean, reproducible and hardware-tested RBF retained for
the release without another build.

### Validation scope

Deterministic host and simulation coverage accumulated since v0.8.0 includes
interlaced field-motion and field-DCT reconstruction, mixed-film scheduling,
audio FIFO pacing, native output timing, DDR arbitration, audio-interface and
visualizer transport, Program Stream/audio seeking and EOF, DVD random access,
subpicture rendering, menu navigation, still termination, staged transitions,
reserve cancellation, unsupported LPCM handling and the malformed-chroma
compatibility boundary.

Physical release testing covered `.mpg` playback, standalone MP3/WAV/
FLAC/Ogg playback, the ten-second visualizer transition, encrypted direct-disc
startup, root menus, scene selection, scene-page changes, chapter navigation,
pause/resume and repeated title/menu transitions across multiple commercial
DVDs. The project owner reports that the complete functional and regression
matrix looks good and accepts this exact runtime set for v0.9.0.

### Packaging

`MiSTer_Media_Player_v0.9.0.zip` contains the RBF, patched Main, executable
helper, visualizer pack, USB DVD launcher, installation/source provenance,
project licence and all seven bundled dependency licences.

- ZIP size: **6,580,818 bytes**.
- ZIP SHA-256:
  `e8bc8e0c25291df85d6d53ad2688995d30ce156c547b7315b08058052863e1f9`.
- Uncompressed member total: **10,476,902 bytes** across 16 files.
- All 15 `SHA256SUMS` entries pass and ZIP integrity reports no errors.
- Fresh extraction preserves mode 755 on `MiSTer` and
  `linux/MediaPlayer_Helper`; all other files use mode 644.
- A fresh extraction is byte-identical to the bounded staging directory.

Package assembly performed no compile or rebuild at the project owner's
direction. The RBF qualification above records its earlier clean build; the
other component source commits and exact payload hashes are listed above.

### Known limitations

- This remains a pre-1.0 compatibility release, not complete MPEG-2 or DVD
  conformance.
- Field-picture H.262 structures, 576i and frame-rate codes 6 through 8 are not
  supported.
- MPEG Transport Streams, AAC, DVD LPCM decode, DVD subtitle presentation,
  title/angle/audio/subtitle switching and general DVD seeking are not present.
- DTS is passthrough-only. AC-3 decoded output is stereo and discards LFE;
  discrete surround requires S/PDIF passthrough and an external decoder.
- Only the first supported Program Stream/DVD audio track is selected.
- The optical launcher targets `/dev/sr0`; automatic drive discovery and
  software-controlled eject are not implemented.
- File seeking uses fixed keyboard jumps. Raw `.m2v`, DVD ISO and optical-disc
  playback do not support arbitrary-position scrubbing.
- Pause is an ARM-side transport hold. A long pause can set the existing FPGA
  audio-underrun telemetry even though playback resumes normally.
- The audio-player artwork, metadata and playlist regions remain reserved UI;
  album-art/tag parsing and playlist population are not implemented.
- The visualizer uses fixed loudness thresholds rather than per-track automatic
  gain and falls back to the ordinary audio-player screen if its pack is absent.
- A targeted hardware comparison found one blended pixel column at sharp color
  transitions; comprehensive playback pixel accuracy remains unqualified.

### Preparing `.mpg` files

Use the project's recommended FFmpeg recipe (`MEDIA_CONVERSION.md`, no longer present) for a
conservative 720x480 exact-24-fps Program Stream with stereo MP2 audio.


---

## MiSTer Media Player v0.8.0 release notes

v0.8.0 adds a bounded 720x480 interlaced all-I path with native 480i presentation, AC-3 decode, and AC-3 or DTS passthrough to S/PDIF. The v0.7.0 Program Stream, PTS, and ARM-helper foundation is unchanged.

This remains a developer-oriented pre-release with a deliberately bounded subset rather than general MPEG-2 systems or video conformance. Read the limitations before reporting a file as broken: most material that fails does so because of picture structure, not encoding quality.

### Publication and provenance

[v0.8.0](https://github.com/aquasock/MiSTer-Media-Player/releases/tag/v0.8.0) was published on 2026-08-27 at 17:41:16 America/Phoenix (`2026-08-27T17:41:16-07:00`) as a pre-release. The annotated tag resolves to `af43de2`; all three runtime binaries reproduce from source baseline `2f1d32c`.

The standalone release-notes file was added afterward in `035807a`. Subsequent documentation corrections describe the existing release without moving its tag or changing its assets. GitHub source archives therefore reflect the tagged documentation, while the current notes include these corrections.

### Highlights

- Bounded 720x480 interlaced frame-picture, frame-DCT, all-I decoding with preserved top- or bottom-field-first order and native 480i timing.
- AC-3 decode in the ARM helper through pinned liba52, downmixed to stereo using the stream's own coefficients.
- AC-3 and DTS passthrough to S/PDIF as IEC 61937 bursts, so an external decoder receives the original bitstream. DTS is passthrough only; there is no DTS decoder.
- An `Audio output` menu option selecting HDMI or S/PDIF, muting the output it does not drive.
- Seven hand-test Program Streams covering field order, Bob versus Weave, progressive all-I and progressive I/P/B, and AC-3 and DTS 5.1 channel sweeps.
- Media transfers no longer hold Main's event loop for long periods, which had made the menu sluggish on low-bitrate files.

### Required runtime files

The RBF, helper, and patched Main form one matched release. Do not mix them with components from another build.

| Release path | Install path | Size | SHA-256 |
| --- | --- | ---: | --- |
| `MediaPlayer_20260827.rbf` | `/media/fat/MediaPlayer_20260827.rbf` | 4,332,740 | `61a2fed28425a461c8b886bdf809e3ef76a320e5688bb22a816135c36ef981ce` |
| `linux/MediaPlayer_Helper` | `/media/fat/linux/MediaPlayer_Helper` | 399,340 | `f6206ba01459eefcc40b26d3d5b3b6ca4f70e496fbeadc317254f86f19f370c8` |
| `MiSTer` | `/media/fat/MiSTer` | 1,170,340 | `01a15750476f3616385fe98dee2d4d832f34823df5ddfc7098966a5b786efad9` |

Main is patched and is not optional: it passes the core's `Audio output` selection to the helper and yields during backpressured transfers to keep the menu responsive. An older Main may display the core's option without passing its selection to the helper. The helper must be executable. Back up the current files, install all three, and reboot before the first test.

### Supported v0.8.0 subset

The two video paths differ sharply and are stated separately.

- Progressive: 4:2:0 I, P and B pictures through 720x480.
- Interlaced: 720x480 at `30000/1001` only, 4:2:0, **I-pictures only**, frame-structured, frame DCT and frame prediction only, top- or bottom-field-first, no `repeat_first_field`.
- H.262 frame-rate codes 1 through 5; codes 6 through 8 are rejected before transport.
- Raw `.m2v` elementary streams or bounded MPEG-2 Program Streams.
- Audio decode: MPEG Layer II at 44.1 or 48 kHz, and AC-3 at 48 kHz, to stereo.
- Audio passthrough: AC-3 and DTS to S/PDIF for an external decoder.

### Known limitations

- Field pictures, field DCT, interlaced P and B pictures, `repeat_first_field` (3:2 pulldown) and 576i are all rejected before decode. Most commercial DVDs use several of these and will not play.
- The AC-3 stereo downmix discards LFE. Discrete surround requires passthrough and an external decoder.
- Only the first audio track is played. Track switching needs a control channel that protocol one does not implement.
- Passthrough carries the bitstream untouched, so volume and mixing do not apply to it, and the unused output is muted rather than duplicated.
- On material whose peak coded picture is large enough, one or two display slots are missed at that picture and appear as a repeated frame rather than a dropped one. This is a property of input buffer depth against peak picture size. The qualified full-length fixture hits it once, at a scene cut, and it was not visible in normal viewing.
- Sharp colour transitions carry one blended pixel column that an independent software decoder does not produce, consistent with horizontal chroma upsampling in the display path. It is obvious on synthetic colour bars and subtle on ordinary material, and it is not specific to any picture type.
- **Comprehensive playback pixel accuracy remains unqualified.** Decoder reconstruction has simulation comparisons, and a targeted hardware-screenshot comparison against the same software-decoded frame found the chroma-edge difference above. That measurement is not a full playback pixel-validation suite; the exact cause of the blended column remains unproven.
- The framework scaler retains little setup margin. At fitter seed 16 its horizontal accumulator missed timing by 0.070 ns once this release's audio routing was added; seed 17 places it at +0.243 ns. The next change that adds comparable logic may expose it again.
- Seeking, scrubbing, pause/resume, DVD navigation, and optical-drive integration are not implemented.

### Reproducible qualification

All three binaries were rebuilt from source baseline `2f1d32c` and reproduced byte for byte: the RBF from a clean export of tracked files only, and the helper and Main from a wiped dependency directory with a freshly extracted toolchain.

- FPGA toolchain: Quartus Prime Lite 17.0.2 Build 602, fitter seed 17.
- ARM toolchain: `gcc-arm-10.2-2020.11-x86_64-arm-none-linux-gnueabihf`.
- MiSTer Main upstream baseline: `0a8fb44ccec6d69c8b7f158abd5fe8065ab2bf4f`.
- minimp3 baseline `ea99364f61c14656440e8d77e9c233ccf3124633`; liba52 baseline 0.7.4.

### Quartus and timing

- 0 errors, 208 warnings, with the warning identifier set identical to the accepted build: none new, none missing.
- Fit: 31,464 ALMs (75%), 50,273 registers, 4,048,355 block-memory bits (71%), 512 RAM blocks (93%), 67 DSP blocks, 3 PLLs.
- Timing positive in every required category with zero total negative slack: +0.243 ns setup, +0.251 ns hold, +2.865 ns recovery, +0.564 ns removal, +0.925 ns minimum pulse width.

### Host and audio regressions

- Host suites pass on the release binaries: cadence decoder layout, eleven DVD ceiling tests, and the Main integration profile covering 168 RTL cases, 96 burst cases, 20 step-resume cases and guarded fault cases.
- Synthetic AC-3 decode against an independent decoder: maximum sample difference 3, correlation 0.999999972. A separate commercial AC-3 track comparison had maximum difference 299, RMS difference 2.60 and correlation 0.999976; the synthetic figure is not a bound on all material.
- AC-3 downmix placement: front channels hard left and right, centre equally in both, surrounds on their own side attenuated, LFE absent.
- Passthrough: bursts carry source frames byte for byte, verified for both AC-3 and DTS, and on a commercial DVD AC-3 track as well as synthetic fixtures.
- MPEG Layer II remains byte-identical on the full-length fixture across both audio output modes.

### Hardware evidence

- The seven hand tests each completed 360 of 360 pictures with zero error flags. Native interlaced runs had zero deadline gaps; those native timing counters do not establish progressive cadence, whose different presentation timing was recorded separately.
- Interlaced top- and bottom-field-first, Bob versus Weave, progressive all-I and progressive I/P/B all played correctly; the progressive I/P/B test displayed 121 reference and 239 B pictures.
- AC-3 was confirmed audible through both HDMI decode and S/PDIF passthrough, the latter reproducing LFE on a receiver for the first time.
- Audio claims marked as measured come from decoder comparison; claims about how playback sounded are user reports and are not independently measured.
- One receiver tested here reproduces LFE from AC-3 but not from DTS, although the transmitted DTS provably carries it. That is a device observation, not a core limitation.

The hand tests used the released RBF and helper hashes. Tests one through six were initially captured with the older Main; the released Main's yield fix was separately confirmed on test one after installation, followed by progressive tests four and seven. The public package contains that released Main, RBF and helper. A confirmation hardware run following installation from the final package remains unrecorded. Publication and binary identity do not constitute a new hardware test.

### Packaging

`MiSTer_Media_Player_v0.8.0.zip` contains the three runtime files, `SHA256SUMS`, `INSTALL.txt`, `SOURCE.txt`, and licences for the project, minimp3 and liba52. Generated test media is not shipped.

- Download size: **2,867,028 bytes**.
- ZIP SHA-256: `5f55b49eb863f74a777b548b4f42b744a9130b4161f176b687ca297deeffcaf3`.
- Total uncompressed member size: 5,948,567 bytes. Earlier engineering notes incorrectly used this as the ZIP size.

The public ZIP passes its integrity checks, and all files covered by its `SHA256SUMS` match the retained package checksums. The runtime sizes and hashes above identify the released files; later documentation edits do not replace the installation or provenance files inside the ZIP.


---

## MiSTer Media Player v0.7.0 release notes

v0.7.0 adds bounded MPEG-2 Program Stream playback, MPEG Layer II audio, real picture-PTS presentation, and a matching MiSTer ARM helper. Raw MPEG-2 Video elementary streams remain supported through their byte-exact path.

This remains a developer-oriented pre-release with a deliberately bounded subset rather than general MPEG-2 systems or video conformance.

### Highlights

- Bounded `.mpg` / `.mpeg` Program Stream demultiplexing in the ARM helper.
- MPEG Layer II audio decoded to signed stereo PCM at 44.1 or 48 kHz.
- Picture PTS transported to the FPGA and applied on its 33-bit / 90 kHz presentation timeline.
- Encoded frame cadence remains a mandatory floor; PTS may delay a picture but never advances it early.
- Native pacing for H.262 frame-rate codes 1 through 5: `24000/1001`, exact 24, 25, `30000/1001`, and exact 30 fps.
- Clean-video and PCM queues that keep audio delivery independent of decoder backpressure.
- Byte-exact raw `.m2v` playback with synthetic H.262-derived timing.
- Clean recovery without reboot between audio-video and video-only files.

### Required runtime files

The RBF, helper, and patched Main form one matched release. Do not mix them with components from another build.

| Release path | Install path | Size | SHA-256 |
| --- | --- | ---: | --- |
| `MediaPlayer_20260824.rbf` | `/media/fat/MediaPlayer_20260824.rbf` | 4,184,380 | `484328e51c6e764890bf2bdcd947448e2eaaaac2c603e93da28009475e44dafc` |
| `linux/MediaPlayer_Helper` | `/media/fat/linux/MediaPlayer_Helper` | 361,452 | `c99237246416ecd8278d90ff6e15e7a00cd8ab1d49c960b8c77fbe00f4ba0483` |
| `MiSTer` | `/media/fat/MiSTer` | 1,166,244 | `16517a9927c659616796b45c8e2488da2a26f0595c91418ed09dc0eb7a5787aa` |

The helper must be executable. Back up the current Main and Media Player files, install all three matching files, and reboot before the first test.

### Supported v0.7.0 subset

- Raw MPEG-2 Video elementary streams or bounded MPEG-2 Program Streams.
- Progressive frame pictures with 4:2:0 chroma.
- Hardware-qualified video geometry through 720x480 / 45x30 macroblocks.
- Continuous supported I/P/B decode and coded-order/display-order presentation.
- H.262 frame-rate codes 1 through 5.
- Program Stream picture PTS or synthetic raw-stream presentation timing.
- MPEG Layer II audio at 44.1 or 48 kHz; stereo is the hardware-qualified path.
- Two retained DDR3 I/P reference banks, separate B scratch storage, and blanking-aligned presentation.

### Known limitations

- MPEG Transport Stream, DVD/VOB navigation, subpictures, private-stream audio, and arbitrary Program Stream layouts are unsupported.
- Audio codecs other than MPEG Layer II and sample rates other than 44.1/48 kHz are rejected.
- Interlaced pictures, chroma formats other than 4:2:0, and H.262 frame-rate codes 6 through 8 are outside the release envelope.
- Seeking, scrubbing, pause/resume, DVD navigation, and optical-drive integration are not implemented.
- Video output remains the fixed 800x600 engineering presentation path.
- Files must be opened through the normal MiSTer file menu; MGL injection is not qualified.

### Reproducible qualification

- FPGA source baseline: `9a5eea3`.
- Host/helper source baseline: `acdbf8b`.
- MiSTer Main upstream baseline: `0a8fb44ccec6d69c8b7f158abd5fe8065ab2bf4f` plus `host/main_mister/0001-mediaplayer-arm-loader.patch`.
- ARM toolchain: GNU Arm 10.2.1, archive SHA-256 `102825ae56c9e00142d06f35d2bdd3299edb6060e84a275a25b095e66fd3fc2a`.
- minimp3 baseline: `ea99364f61c14656440e8d77e9c233ccf3124633` with pinned source and license hashes.

Two clean ARM helper builds and two patched-Main builds were byte-identical. The currently installed target helper and Main also match the hashes above.

Native and ASAN/UBSAN host tests passed exact-video, picture-PTS, PCM, video-only, unsupported-input rejection, source-path, terminal, rate-gate, recovery, and protocol cases. The full 14,315-picture soak produced exact scheduled video and PCM hashes, one clean PCM end marker, bounded batching, zero audio deficit, and clean terminal state.

### Quartus and timing

A clean Quartus Prime 17.0.2 build reproduced the installed and hardware-accepted RBF byte-for-byte.

- ALMs: 29,325 / 41,910 (70%)
- Registers: 45,259
- Block memory: 3,655,139 / 5,662,720 bits (65%)
- RAM blocks: 464 / 553 (84%)
- DSP blocks: 65 / 112 (58%)
- PLLs: 3 / 6 (50%)
- Global setup slack: +0.311 ns
- Global hold slack: +0.238 ns
- Global recovery slack: +3.365 ns
- Global removal slack: +0.497 ns
- Minimum pulse-width slack: +1.122 ns
- Decoder setup slack: +1.782 ns, no violations
- Decoder recovery slack: +11.294 ns, no violations
- Video setup slack: +8.284 ns, no violations
- Quartus errors: 0

TimeQuest retains the established incomplete external-I/O constraint warning class. Every required internal timing category is positive with zero endpoint TNS.

### Four-file MiSTer release gate

Generated regression media is deliberately excluded from the release package. The final gate passed with these exact local files:

| Order | File | Size | SHA-256 | Purpose |
| ---: | --- | ---: | --- | --- |
| 1 | `00_good_480p_48k.mpg` | 690,193 | `1455af94803b1d9958a93fbdb978aa2a42c1d8045a9491f904ad1ad9b8ccdad5` | Normal 48 kHz audio-video startup after reboot |
| 2 | `02_good_video_only.mpg` | 591,889 | `a3e675cad7b3142d2ea25d5b27d2e84e898572c0b6d080bbd2b0a3d01ac76a95` | Video-only Program Stream |
| 3 | `01_good_480p_44k.mpg` | 690,193 | `417db70be8cadc8ca829984d149cb0a5ccda82b0dfc065869578789290a1c83e` | 44.1 kHz recovery immediately after silent playback |
| 4 | `20_bbb_full_48k.mpg` | 100,059,153 | `fdc480e6b16bcbc7c143eb8f7e7edfe0d0bbd8e46a1035b728f07639e71b2357` | Complete 14,315-picture cadence, sync, credits, and endurance soak |

All four runs completed with correct video and audio behavior, USER solid on, POWER solid on, DISK blinking its normal eleven-count progress code, and clean schema-nine telemetry:

- The power-cycle 48 kHz control delivered all 48 pictures and 47 swaps with healthy PCM activity, zero gap outliers, and zero errors. Capture SHA-256: `f57df09f5f3da51e9eceec797e52fd5369fe5a35324566b382cd56c602bf7cd0`.
- The immediately following video-only stream delivered all 48 pictures and 47 swaps with exactly zero PCM samples, zero gap outliers, and zero errors. Capture SHA-256: `9f9d3fccab5e20c6b0e932065b3960e5b4f80ff30ed0d13cc6bf50c7591df586`.
- The immediately following 44.1 kHz control restarted audio cleanly, delivered all 48 pictures and 47 swaps, and retained zero gap outliers and zero errors. Capture SHA-256: `4220305dabf9759e02c8f6c573fffb7768a43a338055d8a27ea77058f5fc8b8f`.
- The fresh-boot full soak accepted all 84,423,309 H.262 bytes and completed all 14,315 pictures and 14,314 swaps. PCM activity was healthy, audio underrun, PCM protocol, presentation, and aggregate errors were clear, sequence end and normal quiet completion were present at STC second 596, and zero credits-window cadence outliers were recorded. The three largest late-window gaps were each 49.7376 ms. The user reported smooth motion, synchronization, and credits with no remaining cadence jump. Capture SHA-256: `08b075111ee41b2621db28abfde247ca676764ef6d78f5ed79c144e173418d7d`.

### Packaging

The public archive contains:

- `MediaPlayer_20260824.rbf`
- `MiSTer`
- `linux/MediaPlayer_Helper`
- `SHA256SUMS`
- `INSTALL.txt`
- `SOURCE.txt`
- `LICENSE`
- `LICENSE.minimp3`

The 2,749,946-byte archive is named `MiSTer_Media_Player_v0.7.0.zip` and has SHA-256 `bae3c3c17d2381cb91e2baff98ec9cf22fed88b04d01bc1349574ae57b917377`. The public regression `.mpg` files are not included. Source is available from the tagged repository state, and `SOURCE.txt` records the exact binary-producing baselines.


---

## MiSTer Media Player v0.6.0 release notes

v0.6.0 advances MiSTer Media Player from deterministic 720x480 I/P/B regressions to sustained playback of real progressive 4:2:0 MPEG-2 Video elementary streams. The milestone adds native `24000/1001`, exact-24-fps, and 25-fps presentation cadence and fixes the compressed-input starvation, GOP-boundary stutters, and end-of-stream stalls exposed by full-length video.

This remains a developer-oriented pre-release and intentionally covers a narrower subset than general MPEG-2 Video / ITU-T H.262 conformance.

### Highlights

- Reworked the MiSTer compressed-data path around 16-bit host writes into a 32 KiB mixed-width asynchronous FIFO while retaining 8-bit decoder consumption and explicit backpressure.
- Raised the decoder clock from 54 MHz to 60 MHz and pipelined prediction, coefficient, reference-cache, and DDR work to sustain demanding real-stream pictures.
- Extended independently signaled P horizontal/vertical motion-vector `f_code` support to 1..9 with a 13-bit vector datapath.
- Extended independently signaled B forward/backward horizontal/vertical motion-vector `f_code` support to 1..5.
- Corrected long-GOP parsing, reference ownership, future-reference binding, repeated-GOP publication, queued-B presentation, persistence accounting, and final-reference release.
- Overlapped reference-picture decoding with B-picture presentation without surrendering retained-bank ownership, B scratch isolation, display ordering, or blanking-aligned publication.
- Added native presentation pacing for H.262 frame-rate code 2 / exact 24 fps and exact rational pacing for frame-rate code 1 / `24000/1001`, alongside the accepted frame-rate code 3 / 25-fps path.
- Added hardware cadence telemetry covering accepted bytes, decoded reference and B pictures, presentation swaps, elapsed playback rate, sequence-end state, decoder errors, and cadence outliers.
- Formally exposed the repository's `.ai` project-control workflow and recovery bootstrap for contributors who want to experiment with repository-driven AI-assisted FPGA development.

### Supported v0.6.0 development subset

- Raw MPEG-2 Video elementary-stream input (`.m2v`).
- Progressive frame pictures with 4:2:0 chroma.
- Hardware-proven geometry up to 720x480 / 45x30 macroblocks on the accepted paths.
- Continuous I/P/B decode and coded-order/display-order presentation on the qualified streams.
- H.262 frame-rate codes 1, 2, and 3: `24000/1001`, exact 24 fps, and 25 fps.
- P forward horizontal/vertical `f_code` values from 1 through 9.
- B forward/backward horizontal/vertical `f_code` values from 1 through 5; deterministic range regressions cover values 1 through 4.
- Signed motion vectors, predictor reset/reuse, H.262 wraparound, integer and half-sample interpolation, and 4:2:0 chroma-vector scaling.
- P/B coded-block-pattern selection, bounded non-intra residual parsing and reconstruction, quantiser changes, and the established inverse-transform path.
- Two retained planar MiSTer DDR3 I/P reference banks plus a separate B scratch region, display-write protection, and blanking-aligned publication.
- Full 8-bit Y/Cb/Cr reconstruction and fixed 800x600 diagnostic video output.
- Synthetic 33-bit / 90 kHz elementary-stream presentation timing.

These are implementation limits, not limits of ITU-T H.262 / ISO/IEC 13818-2.

### Known limitations

The following remain outside the v0.6.0 supported development subset:

- H.262 frame-rate codes 4 through 8: 29.97, 30, 50, 59.94, and 60 fps. These rates are not cadence-paced, so playback follows the decoder's unpaced rate rather than the encoded cadence.
- Interlaced frame or field pictures and broader H.262 picture structures.
- Chroma formats other than 4:2:0.
- General arbitrary MPEG-2/H.262 playback outside the qualified progressive envelope.
- MPEG-2 Program Stream (`.mpg` / `.mpeg`), Transport Stream, VOB, or other container demux.
- H.222.0 PES-derived timestamps and real PTS scheduling.
- Audio decode or playback.
- Seeking, scrubbing, pause/resume, DVD navigation, and direct optical-disc playback.
- A consumer-facing playback UI; the LEDs, loading display, diagnostic matrix, and fixed output timing remain engineering diagnostics.

Full-length files should be selected through the normal MiSTer file menu. Automatic MGL injection of the 642 MB qualification stream did not enter the normal streaming path and is not a supported loading method.

### Release qualification

The synthesized release-candidate source baseline is:

`b64ec6a`

A complete accepted incremental Quartus state was preserved before an independent clean/from-scratch build of the same seed-ten source. Both builds produced the exact same RBF. Later release-documentation commits do not alter the qualified RTL.

The clean build used Quartus Prime 17.0.2 Lite for Cyclone V `5CSEBA6U23I7`. Quartus Flow, Fitter, Assembler, and TimeQuest completed with zero errors and zero endpoint TNS.

The resulting 4,455,376-byte RBF has SHA-256:

`e95e9ec43cb11917d5a904fdd8016bcc23dcbe2d8f36f678544f42ad1a6d5f10`

### Focused hardware regression

The four-file v0.6.0 gate passed on the target MiSTer with complete stream and picture progress, sequence-end completion, and zero decoder errors. The long cadence stress clip additionally reported zero cadence outliers:

- `01_p_skips_and_motion.m2v` — P skip/motion regression; 180,948 bytes, 2 pictures; SHA-256 `ca2d050ce6a32ffa4a7360c142ff619b615c13b0a691bb85144008a934159948`.
- `02_b_prediction_range.m2v` — B forward/backward/bidirectional prediction regression; 185,054 bytes, 5 pictures; SHA-256 `d0aad59a546114c7fe36680902c2bb912c7bcc2a43201ae9d0fd790d6f877725`.
- `03_multi_slice.m2v` — repeated multi-slice regression; 185,393 bytes, 5 pictures; SHA-256 `bcd25c393f42aa1ccb8dc076a87ad14560357db4613093c93472d49d13ec3be8`. The 16-bit transport correctly supplies one final pad byte for its odd stream length.
- `04_bbb_squirrel_15sec.m2v` — native-rate high-motion/large-picture stress clip; 2,603,570 bytes, 121 reference plus 239 B pictures; SHA-256 `9257ffadc24eb6696fc9760f3253764b396c993dfc3640e921c97611bad2edce`.

The 15-second stress clip reached sequence-end quiet at a measured 23.991197 fps with zero decoder errors and zero cadence-gap outliers. Its 8-bit display and swap diagnostics wrap as expected after 255 and do not indicate dropped pictures.

### Full-length playback validation

Two full-length real-video paths supplement the focused telemetry gate:

- The complete native-rate Big Buck Bunny movie was inspected through high-motion scenes, camera pans, scene transitions, and rolling credits. It completed with sharp transitions, smooth credits, and no recurring one-second stutter.
- A separate 642,033,469-byte 720x480 progressive Main Profile 4:2:0 stream with direct `24000/1001` timing was manually selected through the normal MiSTer file menu. The complete movie played at a visually correct rate with smooth motion and no observed dropped-frame defect.

The high-motion Big Buck Bunny scene around the wooden-spike sequence was the principal decoder-throughput stress point. The accepted 60 MHz decoder and mixed-width 32 KiB ingress remove the clean frame drops seen by earlier builds.

### Quartus / timing

- ALMs: 34,565 / 41,910 (82%)
- Registers: 50,960
- Block memory bits: 4,306,375 / 5,662,720 (76%)
- RAM blocks: 538 / 553 (97%)
- DSP blocks: 65 / 112 (58%)
- PLLs: 3 / 6 (50%)
- Global setup slack: +0.303 ns
- Decoder-clock setup slack: +0.386 ns
- Video-clock setup slack: +8.066 ns
- Global hold slack: +0.244 ns
- Global recovery slack: +3.706 ns
- Global removal slack: +0.768 ns
- Minimum pulse-width slack: +1.122 ns
- Endpoint TNS: 0 for every reported timing category
- Quartus errors: 0

TimeQuest continues to report the established incomplete external-I/O constraint warning class. The accepted qualification has positive reported setup, hold, recovery, removal, and minimum-pulse-width slack with zero endpoint TNS.

### MiSTer binary

The release binary follows the normal MiSTer date-coded naming convention:

`MediaPlayer_20260822.rbf`

Do not rename the binary to include the semantic version. The RBF attached to the GitHub pre-release must be exactly 4,455,376 bytes and match SHA-256 `e95e9ec43cb11917d5a904fdd8016bcc23dcbe2d8f36f678544f42ad1a6d5f10`.


---

## MiSTer Media Player v0.5.0 release notes

v0.5.0 expands the hardware-proven MiSTer Media Player development subset to 720x480 progressive 4:2:0 I/P/B regression streams and independently applies picture-signaled P/B motion-vector `f_code` values from 1 through 4. The milestone remains developer-oriented and intentionally narrower than general MPEG-2/H.262 conformance.

### Highlights

- Widened the bounded B parser and raster path from the earlier small diagnostic geometry to 45x30 macroblocks / 720x480.
- Generalized B coded-block-pattern and residual handling across all six 4:2:0 blocks, with ordinary run/level VLCs, Escape syntax, quantiser behavior, inverse transform, and prediction-plus-residual reconstruction inside the established storage caps.
- Generalized B macroblock-address increments, escaped gaps, internal skipped macroblocks, and restricted same-row slice coverage within the accepted progressive envelope.
- Consolidated the full-width P path around deterministic 720x480 streams and completed sequence-end handling, leading skipped macroblocks, macroblock-address Escape coverage, up to 32 residual descriptors, reference reads, persistence, publication, and presentation.
- Generalized P forward horizontal/vertical and B forward/backward horizontal/vertical `f_code` fields independently from 1 through 4. The parsers consume zero through three residual bits per applicable component and apply signed H.262 reconstruction, predictor reuse or independence, and wraparound.
- Added pixel-verified P and B `f_code` range streams covering unequal component fields, nonzero residuals, positive and negative vectors, predictor reuse, and range-boundary wraparound.
- Added a visible P-presentation discriminator whose accepted image has four quadrants divided by horizontal and vertical center seams.
- Reworked the board-LED diagnostics into a settled post-stream snapshot. Accepted streams report USER and POWER solid with DISK dark, avoiding mutable overlapping playback-time indications.
- Corrected the vendored ASCAL `MODE[4]` width mismatch and pipelined its vertical boundary comparison, preserving positive HDMI timing margin in the release-candidate build.

### Current supported development subset

- Raw MPEG-2 Video elementary-stream input (`.m2v`).
- Progressive frame pictures with 4:2:0 chroma on the hardware-proven paths.
- Deterministic I, P, and B regression coverage up to 720x480 / 45x30 macroblocks.
- Independently signaled P horizontal/vertical and B forward/backward horizontal/vertical `f_code` values from 1 through 4.
- Signed motion vectors, predictor reset/reuse, H.262 wraparound, integer and half-sample interpolation, and 4:2:0 chroma-vector scaling.
- P and B coded-block-pattern selection, bounded non-intra residual parsing and reconstruction, quantiser changes, and the established inverse-transform path.
- Two retained planar MiSTer DDR3 I/P reference banks plus a distinct B scratch region, with display-write protection and blanking-aligned publication.
- Mixed I/P/B coded-order and display-order handling on the accepted streams.
- Full 8-bit Y/Cb/Cr reconstruction and fixed 800x600 diagnostic video output.
- Synthetic 33-bit / 90 kHz elementary-stream presentation timing metadata.

These are implementation limits, not limits of ITU-T H.262 / ISO/IEC 13818-2.

### Known limitations

The following remain outside the v0.5.0 supported development subset:

- General arbitrary MPEG-2/H.262 playback outside the hardware-proven deterministic regression envelope.
- Interlaced frame or field pictures and broader H.262 picture structures.
- Chroma formats other than 4:2:0.
- Removal of the current parser, residual-descriptor, coefficient-event, geometry, and diagnostic resource caps.
- MPEG-2 Program Stream (`.mpg` / `.mpeg`) demux and H.222.0 PES-derived timestamps.
- Audio decode or playback.
- DVD/VOB navigation and direct optical-disc playback.
- A consumer-facing playback UI; the current LEDs and fixed output timing remain engineering diagnostics.

### Release qualification

The fresh GitHub-clone qualification checkout is:

`424eec43b0d0b4f8085e6591a15543eafab394e7`

The synthesized RTL was last changed by:

`b1bde49df3831669b577a1ed78404e026f19382d`

The qualification checkout was cloned from GitHub `master` with no prior Quartus databases or output files and compiled from scratch using Quartus Prime 17.0.2 Lite for Cyclone V `5CSEBA6U23I7`. Quartus Flow, Fitter, Assembler, and TimeQuest completed successfully with no Critical Warning and zero endpoint TNS.

The resulting RBF has SHA-256:

`a3eeeb285c427f313987ce6c62cdef560d6293defb1841e96c66aab026d63d8e`

That fresh-clone RBF is bit-for-bit identical to the Commit-194 RBF already accepted on MiSTer hardware. The later release-documentation commits do not change synthesized RTL.

### Authoritative hardware regression

The seven-stream matrix below replaces the former nine-stream matrix as the release gate going forward. All seven streams passed on MiSTer hardware with USER and POWER solid, DISK dark, and accepted images:

- `test_i_baseline.m2v` — continuous 720x480 all-I baseline; SHA-256 `ac7183a653be10aa44c2a1083f87abc77a971916a69678e9cf528de4dd2bff55`.
- `test_p_motion_residual.m2v` — P half-sample motion, coded-block-pattern residuals, and quantiser changes; SHA-256 `ad72f15d69b03c830208e786bcda21622b06cda83a74c91c3121808b14117f96`.
- `test_p_mba_escape.m2v` — ordinary and escaped P macroblock-address gaps plus leading skips; SHA-256 `ca2d050ce6a32ffa4a7360c142ff619b615c13b0a691bb85144008a934159948`.
- `test_b_bidirectional.m2v` — mixed I/P/B order, forward/backward/bidirectional prediction, residuals, and predictor independence; SHA-256 `4886ad9f0f6363c018edce6095e757151a435a4ee9f016e71a3c9a5851de3196`.
- `test_p_visual_discriminator.m2v` — visible P publication with four quadrants and both center seams; SHA-256 `e1ed0a7da39b52b9633124bc2d142e2b84f307d8e7d42781541bdf3d891c3a34`.
- `test_p_f_code_range.m2v` — independent P horizontal/vertical `f_code` 1..4, residual bits, signs, reuse, wraparound, and chained references; SHA-256 `b6a9ad050171446b2c55cd18e37d0727063858d49f4c4bdad6a817894fc6d437`.
- `test_b_f_code_range.m2v` — independent B forward/backward horizontal/vertical `f_code` 1..4 across two B reference pairs; SHA-256 `70da72fd53a1e3a6c2ac5b87bcf26dbfbf7398fb6ae526903d06e0402d54dacd`.

All seven generators were rerun from the fresh release clone and reproduced these hashes while passing their FFmpeg/shared-model pixel-exact or established IDCT-tolerance checks.

### Quartus / timing

- ALMs: 31,625 / 41,910 (75%)
- Registers: 42,223
- Block memory bits: 592,333 / 5,662,720 (10%)
- RAM blocks: 90 / 553 (16%)
- DSP blocks: 69 / 112 (62%)
- PLLs: 3 / 6 (50%)
- Global setup slack: +0.387 ns
- Global hold slack: +0.207 ns
- Global recovery slack: +3.756 ns
- Global removal slack: +0.601 ns
- Minimum pulse-width slack: +0.462 ns
- Decoder-clock setup slack: +2.012 ns
- Endpoint TNS: 0 for every reported setup and hold clock
- Critical Warnings: 0

TimeQuest continues to report the established incomplete external-I/O constraint warning class; the accepted qualification has positive reported setup, hold, recovery, removal, and minimum-pulse-width slack with zero endpoint TNS.

### Audio integration

The companion MiSTer Media Player Audio repository remains integration-compatible at commit:

`fd90c775a129995544ea7aa9d9369408d949ca63`

Audio is not included in this video-core release.

### MiSTer binary

The release binary follows the normal MiSTer date-coded naming convention:

`MediaPlayer_20260817.rbf`

Do not rename the binary to include the semantic version. The user-packaged RBF attached to the GitHub pre-release should match SHA-256 `a3eeeb285c427f313987ce6c62cdef560d6293defb1841e96c66aab026d63d8e`.


---

## MiSTer Media Player v0.4.0 release notes

v0.4.0 is the first hardware-qualified MiSTer Media Player milestone that combines the established progressive 4:2:0 I-picture path, the generalized P-picture reconstruction path, and a bounded hardware-proven B-picture decode/presentation path. The milestone remains developer-oriented and intentionally narrower than general MPEG-2/H.262 conformance.

### Highlights

- Preserved the continuous progressive 4:2:0 all-I playback path and generalized syntax-derived P-picture reconstruction introduced during the v0.4.0 development cycle.
- Added a hardware-proven B-picture reconstruction path with forward, backward, and bidirectional prediction on deterministic mixed I/P/B regression streams.
- Added B-picture residual reconstruction, macroblock-address skip handling, reference selection, and coded-order/display-order handling for the proven progressive 4:2:0 subset.
- Added a dedicated B scratch DDR region so B reconstruction does not overwrite retained I/P references.
- Corrected DDR region identity to use the full two-bit region selector, keeping retained bank 0, retained bank 1, and B scratch distinct during display-write protection.
- Added blanking-aligned B presentation/reorder handling that retains the future P reference while presenting the intervening B picture from scratch, then publishes the retained future reference in display order.
- Corrected the consecutive-P publication-versus-presentation ownership race by pacing a following P picture until its selected destination bank is no longer display-owned, without weakening DDR write protection or changing the B reorder path.
- Consolidated the active inverse-transform implementation around a shared IDCT multiplier bank, reducing DSP use from the earlier 92-DSP development point to 68 DSP blocks while preserving accepted decode behavior.
- Retired the temporary consecutive-P first-fault/timeout/arbiter diagnostic layer after root-cause localization and restored normal USER completion behavior.

### Current supported development subset

- Raw MPEG-2 Video elementary-stream input (`.m2v`).
- Progressive frame pictures on the hardware-proven paths.
- 4:2:0 chroma.
- Continuous supported I-picture playback up to the established 720x480 diagnostic geometry.
- Generalized P-picture regression coverage at 128x96 / 8x6 macroblocks, including signed forward motion, predictor reuse/reset, integer and half-sample interpolation, coded-block-pattern selection, sparse residual placement, quantiser changes, and consecutive reconstructed-P reference use.
- Hardware-proven B-picture regression coverage at 128x96 using deterministic mixed I/P/B streams with forward, backward, and bidirectional prediction, internal macroblock skips, bounded residuals, and display reordering.
- Two retained planar MiSTer DDR3 frame banks for I/P ping-pong/reference ownership plus a separate B scratch region.
- Full 8-bit Y/Cb/Cr reconstruction.
- Fixed 800x600 diagnostic video output.
- Synthetic 33-bit / 90 kHz elementary-stream presentation timing metadata.

The P and B regression paths still have explicit engineering limits. These are implementation limits, not limits of ITU-T H.262 / ISO/IEC 13818-2.

### Known limitations

The following remain outside the v0.4.0 supported development subset:

- General arbitrary MPEG-2/H.262 P- and B-picture playback outside the hardware-proven regression envelope.
- Interlaced frame/field-picture support and broader H.262 picture structures.
- Chroma formats other than 4:2:0.
- General MPEG-2 Program Stream (`.mpg` / `.mpeg`) demux and H.222.0 PES-derived timestamps.
- Audio.
- DVD/VOB navigation and direct optical-disc playback.
- Removal of the current diagnostic geometry/resource caps.

### Release qualification

The hardware-qualified RTL baseline is:

`1370c28e3d34b1fd603c17130986bc336da29a32`

The qualification build was made from a fresh clone of GitHub `master` using Quartus Prime 17.0.2 Lite for Cyclone V `5CSEBA6U23I7`. Quartus Flow and Fitter completed successfully, the standard Phase 1P timing reports were reviewed, and setup endpoint TNS was zero.

Required MiSTer hardware regression:

- `test_p_consecutive_reference.m2v` — PASS for 20 consecutive runs with normal USER acceptance.
- `test_b_mixed_gop.m2v` — PASS.
- `test_b_core_decode.m2v` — PASS.
- `test_p_general_decode.m2v` — PASS.
- `test_all_i.m2v` — PASS.

The release-documentation commits following `1370c28` change documentation only; the synthesized RTL qualified above is unchanged.

### Quartus / timing

- ALMs: 31,782 / 41,910 (76%)
- Registers: 43,812
- Block memory bits: 461,345 / 5,662,720 (8%)
- RAM blocks: 73 / 553 (13%)
- DSP blocks: 68 / 112 (61%)
- PLLs: 3 / 6 (50%)
- Global setup slack: +0.167 ns
- Global hold slack: +0.248 ns
- Global recovery slack: +4.117 ns
- Global removal slack: +0.704 ns
- Minimum pulse-width slack: +0.462 ns
- Focused decoder setup: +1.311 ns, 0 / 100 violations
- Focused video setup: +6.987 ns, 0 / 80 violations
- Setup endpoint TNS: 0

TimeQuest continues to report the established incomplete external-I/O constraint warning class; the accepted qualification has positive reported setup/hold/recovery/removal slack and zero setup endpoint TNS.

### MiSTer binary

The release binary follows the normal MiSTer date-coded naming convention:

`MediaPlayer_20260816.rbf`

The user-built binary attached to the GitHub release should be the hardware-qualified artifact corresponding to the `1370c28` RTL baseline.
