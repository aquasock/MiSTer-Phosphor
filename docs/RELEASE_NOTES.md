# Release notes

Newest first. MiSTer-Phosphor's version numbers start here. They are unrelated to
the v0.1.0 to v0.9.5 releases of MiSTer Media Player, the common ancestor of
MiSTer-Phosphor and MiSTer-Raster, whose notes are in
[history/](history/MEDIA_PLAYER_RELEASE_NOTES.md). The full list of changes is in
[CHANGELOG.md](CHANGELOG.md).

## MiSTer-Phosphor v0.1.0

Released 2026-09-20. This is the first Phosphor release.

### Highlights

- **Four native audio decoders in one bitstream.** MP3 (MPEG-1 Layer III), Ogg Vorbis,
  PCM WAV and FLAC, identified from file contents after you select a file. Decoding
  runs entirely in FPGA logic, with no HPS software or soft CPU in the decode path.
- **Gapless FLAC albums.** One FLAC with an embedded CUESHEET and display metadata
  plays as a single continuous stream, with previous/next, seeking, cyclic
  last-to-first playback and album artwork, at 44.1 or 48 kHz.
- **Mixed-format TAR playlists** of up to 255 MP3, Ogg, WAV and FLAC files, ordered by
  a standard M3U, with per-track titles, album and artist text and optional artwork.
- **Three visualizers:** Waveforms, FFT with peak hold, and O-Scope with phosphor
  persistence, on both HDMI and analog video.
- **Native-rate audio output** for 44.1 and 48 kHz material over HDMI, analog and
  S/PDIF.
- **Browser media builder** for playlists and gapless albums. The album builder can
  now convert high-resolution FLACs down to 44.1 or 48 kHz.

### New since the last recorded build

- **Playlist titles for entries 100 to 255** now show correctly. The metadata mux
  read the first artwork address as entry 100's title; the renderer now supplies an
  explicit artwork-request bit. Standalone FLAC and artwork are unchanged.
- **Timing constraint fix** for the native-audio reset synchronizers: only their 12
  asynchronous-assert `CLRN` pins are exempted, and no HDL or clock changed.
- **FLAC album builder:** album title, artist and artwork fields prefill from the
  tracks' tags and can be edited, and the optional **Convert high-resolution FLACs**
  setting (off by default) downsamples stereo 16- or 24-bit tracks above 44.1 kHz to
  44.1 or 48 kHz at 16 bits.
- **Project housekeeping:** the project is now `Phosphor` (it builds `Phosphor.rbf`),
  the seed is pinned, and the build tooling and documentation are in the repository.

### Required runtime files

| Release file | Install path | Size | SHA-256 |
| --- | --- | ---: | --- |
| `Phosphor_20260920.rbf` | `/media/fat/_Other/Phosphor_20260920.rbf` | 4,455,380 | `7ca533386a8e2cb60f8249ba0173209ed921e4aee95e1dd96c350e95da578121` |

Put media in `/media/fat/games/Phosphor/`, select **Phosphor** under `_Other`, open
the OSD, choose **Load Audio** and pick a file, a FLAC album or a TAR playlist. The
OSD identifies the build by its date stamp (`260920`). Keep the previous working RBF
when trying a new one. See the [README](../README.md) for the controls.

### Supported v0.1.0 subset

- **WAV and FLAC:** 16-bit stereo at 44.1 or 48 kHz.
- **MP3:** MPEG-1 Layer III, mono or stereo, at 32, 44.1 or 48 kHz with the standard
  bitrate modes. Not supported: MPEG-2/2.5 LSF, free-format and dual-channel streams.
- **Ogg:** stereo Vorbis at 44.1 or 48 kHz within the hardware decoder's setup limits.
- **Gapless FLAC albums:** up to 99 tracks, with a CD-sector-aligned CUESHEET.
- **Playlists:** uncompressed USTAR only (not TAR.GZ, TAR.XZ, ZIP or 7z), up to 255
  tracks. Cover art is the core's fixed 92×92 RGB332 format, which the builder makes.

### Known limitations

- **Mixed TAR track changes are not gapless:** each one resets and starts the decoder
  for the next file. Use a gapless FLAC album when continuity or cyclic playback
  matters.
- **No JPEG or PNG decoding on the FPGA;** the builder converts cover art.
- **Timing sign-off** covers the constrained paths only, not every board I/O path.
- **Hardware coverage of this build is partial** (see below).
- **Builder conversion is lossy.** It dithers, reports clipping, and does not accept
  mono, sources below 44.1 kHz, or bit depths other than 16 and 24. Keep your sources.

### Qualification

Quartus Prime Lite 17.0.2 Build 602, Cyclone V `5CSEBA6U23I7`, HIGH ALM register
packing, six fitter threads, project `Phosphor` with `SEED 87` pinned. Worst slack in
ns across the eight corners (slow and fast 1100 mV at -40, 0, 85 and 100 C):

| Seed | ALMs | RAM blocks | DSP | Setup | Hold | Recovery | Removal | Pulse width | Result |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 52 | 35,599 | 543 | 111 | +0.216 | +0.046 | +4.022 | +0.260 | +0.396 | Pass, zero TNS |
| 61 | 35,607 | 543 | 111 | **-0.160** | +0.090 | +3.700 | +0.254 | +0.396 | **Fails setup** |
| **87** | 35,685 | 543 | 109 | +0.136 | +0.075 | +3.199 | +0.160 | +0.396 | Pass, zero TNS |

Seed 87 has the best minimum margin and is pinned. It uses 35,685 of 41,910 ALMs
(85%), 543 of 553 RAM blocks (98%), 109 of 112 DSP blocks and 5 of 6 PLLs. Seed 61,
the seed of the earlier hardware-validated build, no longer closes setup on this
source; do not use it.

**Reproducibility.** The release bitstream was built from a fresh clone of the GitHub
repository at commit `bb0b6b6e1a6f7687b4f6c5ce2e7d30754d89ab98` with
`tools/build_seeds.sh` for seed 87, with no manual edits. It is byte-identical to the
earlier seed 87 build made before the `Phosphor.qsf` cleanup and the comment edits,
and its timing matches the table. The date stamp is the build date, so a build on
another day differs in those bytes only.

**Hardware.** The release bitstream has been run only partly:
- On 2026-09-20 the owner reported that it plays five gapless FLAC albums: three at
  44.1 kHz (*The Dark Side of the Moon*, *The Wall*, *The Who - Greatest Hits*) and
  two at 48 kHz (*Thriller* and *Purple Rain*), the last two made by the builder's
  high-resolution conversion from 96 kHz / 24-bit sources. Seeking, previous/next, the
  last-to-first wrap and artwork were not reported.
- Not yet tested on this bitstream: TAR playlists (including entries 100 and above),
  MP3, Ogg, WAV, standalone files and the visualizers.
- The earlier build `Phosphor_20260919.rbf` (seed 61) was validated on hardware and has
  the same logic as this release. It is a different fit, fitted before the reset
  exemption reached the timing constraints, so it is not what the repository builds and
  is not the release.

No agent-run hardware playback is claimed. Full records, the earlier build and the
reset-constraint correction are in [QUALIFICATION.md](QUALIFICATION.md).

### Licensing and packaging

Distribute the RBF with the corresponding source under GPL-3.0-or-later, and include
`COPYING`, `COPYING.GPL2`, `COPYING.LESSER` and [ATTRIBUTIONS.md](../ATTRIBUTIONS.md).
Preserve the per-file license headers. Release copies of the bitstream are named
`Phosphor_YYYYMMDD.rbf` and are not stored in the repository.
