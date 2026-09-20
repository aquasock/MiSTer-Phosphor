# MiSTer-Phosphor

An FPGA audio player and visualizer core for
[MiSTer](https://github.com/MiSTer-devel), targeting QMTech
DE10-Nano-compatible hardware (Cyclone V `5CSEBA6U23I7`). It plays MP3,
Ogg Vorbis, WAV, and FLAC files; supports gapless FLAC albums and mixed-format
TAR playlists; and renders three audio-driven visualizers with an optional
metadata and album-art interface. Playback and visualization are implemented
natively in FPGA logic, with no HPS software or soft CPU in the decode path.
[MiSTer-Raster](https://github.com/aquasock/MiSTer-Raster) is its video companion,
built and qualified the same way.

## What it does

- **Four native audio decoders** — MPEG-1 Layer III MP3, Ogg Vorbis, PCM WAV,
  and native FLAC decoding are present together in one bitstream. Files are
  identified from their contents after selection rather than by separate core
  modes.
- **Standalone file playback** — opens an individual `.mp3`, `.ogg`, `.wav`,
  or `.flac` file with pause/resume, direct seeking, a proportional progress
  bar, and automatic repeat.
- **Gapless FLAC albums** — opens a single FLAC containing an embedded standard
  CUESHEET and the project's compact display metadata. Tracks share one
  continuous decoded sample stream, enabling gapless track changes, cyclic
  last-to-first playback, previous/next navigation, seeking, metadata, and
  album artwork.
- **Mixed-format TAR playlists** — opens an uncompressed POSIX USTAR archive
  containing ordinary MP3, Ogg, WAV, and FLAC files plus a standard extended
  M3U playlist. The M3U controls playback order regardless of TAR member order.
  Mixed playlists support as many as 255 tracks, previous/next navigation,
  album and artist text, per-track titles, and optional album artwork. Original
  audio members remain byte-for-byte recoverable with ordinary TAR software.
- **Transport and library UI** — a progress/time overlay is available for all
  playable files. Album modes add a three-panel display with album artwork,
  album/artist/title information, and a six-row playlist. Long selected titles
  and metadata fields scroll horizontally; unused rows remain hidden.
- **Three visualizers** — Waveforms provides dual time-domain traces, FFT shows
  a spectrum with peak hold, and O-Scope interprets the stereo channels as X/Y
  beam coordinates with phosphor persistence. The native scene feeds both HDMI
  and analog video paths before output-specific processing.
- **Native-rate output** — supported 44.1 and 48 kHz material follows the
  corresponding audio clock family instead of being forced through one fixed
  output rate. HDMI, analog audio, and S/PDIF use the MiSTer platform output
  paths.

## Controls

Playback hotkeys operate while the MiSTer OSD is closed.

| Key | Action |
| --- | --- |
| `Space` | Play or pause |
| `Left` / `Right` | Seek backward or forward 10 seconds |
| `Ctrl` + `Left` / `Right` | Seek backward or forward 30 seconds |
| `Ctrl` + `Alt` + `Left` / `Right` | Seek backward or forward 60 seconds |
| `F1`–`F8` | Seek to 0/8 through 7/8 of the current file or track |
| `N` / `P` | Next or previous track in an album or TAR playlist |
| `I` | Show or hide album artwork, metadata, and playlist panels |
| `V` | Cycle Waveforms, FFT, and O-Scope visualizers |
| `A` | Toggle standard and widescreen presentation |

Previous/next controls and the three-panel library UI are intentionally absent
for standalone files because no playlist exists in that mode.

## Current limitations

This is a deliberately bounded hardware implementation rather than a
general-purpose software codec stack. WAV and FLAC input must be 16-bit stereo
at 44.1 or 48 kHz. MP3 support targets MPEG-1 Layer III mono or stereo at 32,
44.1, or 48 kHz using the standard bitrate modes; MPEG-2/2.5 LSF, free-format,
and dual-channel streams are outside the current profile. Ogg support targets
stereo Vorbis at 44.1 or 48 kHz within the setup limits implemented by the
hardware decoder.

Mixed TAR track transitions reset and start the decoder selected for the next
ordinary file, so they are not guaranteed gapless. Use a continuous embedded-
CUESHEET FLAC album when sample-continuous or cyclic playback matters. TAR
archives must be uncompressed USTAR, not TAR.GZ, TAR.XZ, ZIP, or 7z. JPEG and
PNG decoding is not implemented on the FPGA; the browser builder converts an
optional cover to the core's fixed 92×92 RGB332 `cover.art` representation.

## Installation

Copy the dated release RBF to MiSTer's `_Other` directory and place audio in
the core's games directory:

```text
/media/fat/_Other/Phosphor_YYYYMMDD.rbf
/media/fat/games/Phosphor/
```

Select **Phosphor** under `_Other`, open the MiSTer OSD, choose **Load Audio**,
and select a supported standalone file, FLAC album, or TAR playlist. The current
release is v0.1.0; see the [release notes](docs/RELEASE_NOTES.md).

## Building

The project targets Quartus Prime 17.0.2 Lite and the Cyclone V
`5CSEBA6U23I7`. Open `Phosphor.qpf`, or build from a Quartus command
shell with:

```sh
quartus_sh --flow compile Phosphor
```

The Quartus project is named Phosphor, so a build produces `Phosphor.rbf`; copy it to a
dated `Phosphor_YYYYMMDD.rbf` name when packaging.

`files.qip`, the complete `rtl/` and `sys/` trees, and all referenced `.hex`
and `.mem` initialization files must be present. `sys/build_id.tcl` generates
`build_id.v` automatically before compilation.

The design is close to the device's physical M10K and DSP limits, and fitter
placement materially affects timing closure. `Phosphor.qsf` pins **seed 87**, the
timing-qualified seed on the current source. `tools/build_seeds.sh` builds seeds in
isolated copies of the tree and runs the eight-corner timing sweep on each; see
[Building](docs/BUILD.md) for the procedure and [Qualification](docs/QUALIFICATION.md)
for every build's seeds, resources, timing coverage limits and hardware acceptance.

## Preparing media

Open `tools/media-builder/index.html` in a current Chromium-based browser.
The companion application performs all work locally and provides two modes:

- **Mixed Playlist TAR** packages as many as 255 original MP3, Ogg, WAV, and
  FLAC files with a standard M3U, display metadata, and optional artwork. Audio
  payloads are not decoded, transcoded, or modified.
- **Gapless FLAC Album** losslessly joins as many as 99 compatible FLAC tracks
  into one continuous FLAC with an embedded CUESHEET, SEEKTABLE, display
  metadata, and artwork. Every decoded source sample is retained in order. Album
  title, album artist, and artwork are prefilled from the tracks' tags and can be
  edited, as in the playlist builder. An optional **Convert high-resolution
  FLACs** setting (off by default) also accepts stereo 16- or 24-bit tracks above
  44.1 kHz and downsamples them to 44.1 or 48 kHz at 16 bits, choosing whichever
  needs the simpler conversion. Only the tracks that need it are converted
  (a lossy step with dither, and any clipping is reported); the rest are copied
  unchanged. See the [FLAC builder README](tools/media-builder/flac/README.md).
  Albums converted to 48 kHz have been played on hardware.

Neither format requires a proprietary extractor. Mixed-playlist files can be
recovered with ordinary TAR software, while the gapless album remains a
standards-compliant FLAC with an embedded CUESHEET.

## Source layout

- `Phosphor.sv` — core integration, format dispatch, playlist control,
  transport, and MiSTer-facing configuration.
- `rtl/` — audio decoders, visualizers, metadata/container parsers, UI, and
  platform-specific audio control.
- `sys/` — standard MiSTer framework, scaler, video, audio, HPS I/O, and
  top-level platform wrapper.
- `tools/media-builder/` — self-contained local browser application for creating
  supported albums and playlists.
- `tools/` — `build_seeds.sh`, `run_timing_sweep.py`, and
  `check_timing_corners.tcl` for isolated builds and timing sign-off.
- `docs/` — build, qualification, changelog, and shared-history documentation.

## Documentation

- [Building](docs/BUILD.md)
- [Build qualification](docs/QUALIFICATION.md)
- [Changelog](docs/CHANGELOG.md)
- [Release notes](docs/RELEASE_NOTES.md)
- [Media builder](tools/media-builder/README.md)
- [Media Player history](docs/history/MEDIA_PLAYER_CHANGELOG.md), the common origin of Phosphor and Raster

## License

Original project code is distributed under the GNU General Public License
version 2 or later, matching MiSTer-Raster and allowing original project code
to be shared between the two projects. Because each combined design includes
MiSTer framework modules under GPL version 3 or later, distribute the complete
source and RBF under GPL-3.0-or-later. LGPL and Intel/Altera-generated
components retain their respective upstream terms and notices.

See [`ATTRIBUTIONS.md`](ATTRIBUTIONS.md) for component provenance and
redistribution guidance. Full license texts are provided in `COPYING`,
`COPYING.GPL2`, and `COPYING.LESSER`.
