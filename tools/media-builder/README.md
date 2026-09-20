# MiSTer-Phosphor Media Builder

Open `index.html` in a current Chromium-based browser. The complete application
is contained in this directory and does not require installation, a web server,
or an internet connection.

The two tabs provide:

- **Mixed Playlist TAR** — packages as many as 255 original MP3, Ogg Vorbis,
  WAV, and FLAC files into an uncompressed USTAR archive with a standard M3U,
  album and artist metadata, track titles, and optional 92×92 artwork. Existing
  builder-created TAR playlists can be reopened, reordered, edited, and saved.
  Every source audio member is retained byte-for-byte.
- **Gapless FLAC Album** — losslessly combines as many as 99 compatible FLAC
  tracks into one continuous FLAC with an embedded CUESHEET, SEEKTABLE, display
  metadata, and artwork. Decoded source samples are retained in their original
  order without trimming, padding, fading, or lossy conversion. An optional,
  off-by-default setting instead downsamples stereo tracks above 44.1 kHz, or
  24-bit, to 44.1 or 48 kHz / 16-bit; only the tracks that need it are converted.

All processing happens locally in the browser. Files are never uploaded.

## Directory contents

Keep the entire directory together:

```text
media-builder/
├── index.html
├── app.js
├── style.css
├── tar/
└── flac/
    └── vendor/
```

The `flac/vendor` directory contains the bundled libflac.js codec and its
license. Moving only the top-level `index.html` will not work; its scripts,
styles, embedded tab applications, and codec dependency must remain beside it.

Third-party components and their license provenance are documented in
[`ATTRIBUTIONS.md`](ATTRIBUTIONS.md).
