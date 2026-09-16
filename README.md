# MiSTer-Phosphor

A media player core for [MiSTer](https://github.com/MiSTer-devel), targeting
QMTech DE10-Nano-compatible hardware (Cyclone V `5CSEBA6U23I7`). It plays
back DVD-style MPEG-2 Program Stream video with MP2 audio, standalone or
album FLAC music, SRT subtitles, and includes a transport UI overlay and
three PCM-driven audio visualizer modes — all implemented natively in FPGA
logic, no HPS software or soft CPU involved in the playback path.

## What it does

- **MPEG-2 / H.262 video decode** — progressive 4:2:0 video up to 720×480,
  full I/P/B-picture support including B-picture display-order reordering,
  at any of H.262's eight standard frame rates. One shared IDCT engine
  serves all three picture types.
- **MP2 audio** — MPEG-1 Layer II, 48 kHz, stereo/dual-channel/joint-stereo,
  demuxed from the same Program Stream as the video.
- **FLAC music and album playback** — a separate path from movie audio,
  handling both standalone `.flac` files and embedded-CUESHEET albums with
  full track navigation (next/previous track, seek-table-assisted direct
  seeking), covering the format's full subframe/residual/stereo-decorrelation
  syntax within a fixed 44.1 kHz/16-bit/stereo profile.
- **SRT subtitles** — a bounded streaming parser (no whole-file index),
  adjustable timing offset and playback speed, rendered as part of the same
  on-screen scene as the transport UI rather than a separate overlay layer.
- **Transport UI** — an on-screen time/progress-bar overlay with
  resolution-aware font scaling, a real proportional progress bar, and
  music-mode-aware track/album time display, shown on activity and hidden
  automatically afterward.
- **Audio visualizers** — Waveforms (dual-trace oscilloscope), FFT
  (quantized spectrum blocks with peak-hold), and O-Scope (a green-phosphor
  stereo XY vectorscope with genuine multi-level phosphor decay, compatible
  with music specifically authored for X/Y display).

## Current limitations

This is a deliberately scoped implementation, not a general-purpose decoder
— see the MPEG and FLAC documents for the full detail, but in short:
interlaced/field-structured video, non-4:2:0 chroma, resolutions above
720×480, and non-default quantization matrices are all valid H.262 that
this decoder doesn't implement yet (tracked explicitly as capability limits,
distinct from genuine stream corruption). FLAC and MP2 audio are both fixed
to a stereo-only profile; mono isn't accepted by either. Subtitles are
plain-text SRT only, two lines of 63 characters each, with in-line
formatting tags stripped rather than rendered.

## Building

Quartus Prime 17.0.2 Lite targeting the Cyclone V part above. The project
uses a three-seed build methodology — Quartus's fitter seed affects
placement and therefore timing closure on a design this close to full (block
RAM in particular regularly sits around 99% utilized), so a candidate build
sweeps three seeds and takes whichever one(s) actually close timing rather
than committing to a single seed in advance. Full details, including the
dedicated multi-corner timing validation pass beyond Quartus's default flow
check, are in the build document.

## Preparing media

`tools/create_mpg.txt` documents the project's ffmpeg recipe for encoding an
MPEG-2 Program Stream this core accepts, with quality/frame-rate/aspect
variants. `tools/pack_flac_album.py` bundles adjacent numbered tracks beside
it into a single CD-format embedded-CUESHEET album FLAC (N/P navigation in
the core); `tools/unpack_flac_album.py` splits one back into numbered tracks.
Both scripts require `ffmpeg`/`flac` and are run directly with Python 3.

## Documentation

- **Architecture** — the system map: top-level module structure, the
  decode/audio/session pipeline, DDR arbitration, and how everything above
  connects together.
- **MPEG** — H.262 video decode and MP2 audio decode in depth, including
  exactly what's a capability limit versus a genuine syntax error.
- **FLAC** — the music/album audio path: format coverage, DDR frame
  storage, and CUESHEET-driven track navigation.
- **Subtitles** — the SRT parser, timing controls, and how subtitle content
  merges into the shared on-screen scene.
- **UI** — the transport overlay: visibility timing, scene assembly, the
  full OSD menu structure, and what each menu entry actually does.
- **Visualizers** — how each of the three audio visualizer modes works,
  including a naming-history note for anyone cross-referencing source (the
  FFT mode's renderer is still named after its original "Fire" identity).
- **Build** — the actual Quartus build flow, seed/reproducibility
  requirements, and known build-process gotchas.

## License

Distributed under the GNU General Public License (v2 or later), matching
the license carried in the project's own source headers. Built on the
standard MiSTer platform framework (scaler, on-screen menu, platform
top-level wrapper) alongside this project's own playback/decode logic;
platform-provided components retain their own upstream licensing.

## Screenshots

<img width="1920" height="1080" alt="menu" src="https://github.com/user-attachments/assets/b6df0f47-79ab-48a0-ad97-20b447a1dd00" />

<img width="1920" height="1080" alt="static" src="https://github.com/user-attachments/assets/0009241c-e270-45b5-b348-db9a55c1d717" />

<img width="1920" height="1080" alt="motion" src="https://github.com/user-attachments/assets/eec4e23c-e21e-429c-82c6-b4ee51714a9f" />

<img width="1920" height="1080" alt="waveform" src="https://github.com/user-attachments/assets/f5f7a19d-b7f4-4d4e-99e9-edc9d59ebae3" />

<img width="1920" height="1080" alt="fft" src="https://github.com/user-attachments/assets/c6d45783-a5fa-4b2a-9f1e-53870e2c468e" />

<img width="1920" height="1080" alt="o-scope" src="https://github.com/user-attachments/assets/e84b4d29-6889-4a12-a8ab-138f2a3235c9" />

<img width="1920" height="1080" alt="o-scope cali" src="https://github.com/user-attachments/assets/22d84606-d87c-4a4e-a764-3fb5be39fff0" />

<img width="1920" height="1080" alt="o-scope music 1" src="https://github.com/user-attachments/assets/4bdbe9f6-3a03-4271-bc6c-bcb9853a4fcd" />

<img width="1920" height="1080" alt="o-scope music 2" src="https://github.com/user-attachments/assets/4a9c0585-fbbe-468f-8fe2-0daa74b1807e" />

<img width="1920" height="1080" alt="o-scope music 3" src="https://github.com/user-attachments/assets/92d672a3-989d-47c4-a4a4-004e1b7a82cb" />

<img width="1920" height="1080" alt="o-scope music 4" src="https://github.com/user-attachments/assets/75bdecee-df2a-47aa-9d7c-329dd79ee06d" />










