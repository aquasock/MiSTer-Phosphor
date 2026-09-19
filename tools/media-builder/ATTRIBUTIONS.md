# Media Builder Attributions

This document covers the code shipped in `tools/media-builder`. The application
is self-contained: it loads no JavaScript, fonts, codecs, or other assets from a
CDN or remote service.

## Project code

The application shell, Mixed Playlist TAR builder, Gapless FLAC Album builder,
styles, and metadata/container-writing code were written for MiSTer-Phosphor.
They use only standard browser APIs and contain no separately licensed
JavaScript framework, TAR library, image library, or M3U library.

The browser supplies APIs such as File, Blob, ArrayBuffer, TextEncoder,
TextDecoder, Canvas 2D, `createImageBitmap`, and object URLs. Browser APIs are
platform facilities and are not redistributed with this application.

## libflac.js 5.6.0

- **Bundled file:** `flac/vendor/libflac.js`
- **Purpose:** decoding input FLAC tracks and losslessly encoding the combined
  FLAC album
- **Variant:** self-contained Emscripten/asm.js release build (there is no
  separate `.wasm` file)
- **Upstream:** <https://github.com/mmig/libflac.js>
- **License:** MIT
- **Copyright:** Copyright (c) 2014-2020 DFKI GmbH
- **Exact bundled license:** `flac/vendor/LICENSE-libflacjs.txt`
- **Bundled-file SHA-256:**
  `bebe6285df98e55e606835bdc59b6e2d8586b61c1a020a193c17fe09cf5aabe3`

The complete MIT notice supplied with this copy is retained beside the codec.
That notice also credits the FLAC encoder on which the library is based:

- Copyright (C) 2000-2009 Josh Coalson
- Copyright (C) 2011-2014 Xiph.Org Foundation

## Components included through libflac.js

The following components are not called directly by Media Builder. They are
part of, or used to generate, the bundled `libflac.js` distribution.

### libFLAC

- **Purpose:** reference FLAC encoder and decoder compiled into libflac.js
- **Upstream:** <https://github.com/xiph/flac>
- **Version reported by libflac.js 5.6.0:** 1.3.4
- **License:** Xiph.Org BSD-like license
- **Copyright:** Copyright (C) 2000-2009 Josh Coalson; Copyright (C) 2011-2016
  Xiph.Org Foundation

The libflac.js notice is preserved in `flac/vendor/LICENSE-libflacjs.txt`.
The exact libFLAC 1.3.4 terms are available as
[`COPYING.Xiph`](https://github.com/xiph/flac/blob/1.3.4/COPYING.Xiph).

### libogg

- **Purpose:** Ogg-container support compiled into the upstream libflac.js
  distribution; Media Builder itself produces native FLAC and does not invoke
  Ogg output
- **Upstream:** <https://github.com/xiph/ogg>
- **Version reported by libflac.js 5.6.0:** 1.3.6
- **License:** Xiph.Org BSD-style license
- **Copyright:** Copyright (c) 2002, Xiph.org Foundation

The exact libogg 1.3.6 terms are available in
[`COPYING`](https://github.com/xiph/ogg/blob/v1.3.6/COPYING).

### Emscripten-generated runtime

- **Purpose:** compiles libFLAC/libogg and supplies the JavaScript runtime inside
  the bundled codec
- **Upstream:** <https://github.com/emscripten-core/emscripten>
- **Version reported by libflac.js 5.6.0:** 1.39.19
- **License:** MIT or University of Illinois/NCSA Open Source License
- **Copyright:** Copyright (c) 2010-2014 Emscripten authors

The upstream license text is available in the Emscripten
[`LICENSE`](https://github.com/emscripten-core/emscripten/blob/main/LICENSE).

## What is not bundled

Media Builder does not include or call FFmpeg, LAME, a Vorbis encoder/decoder,
JSZip, a web font, analytics, or an upload service. MP3, Ogg Vorbis, WAV, and
ordinary FLAC members added on the Mixed Playlist TAR tab are copied
byte-for-byte; that tab does not decode or re-encode them.

## Redistribution

When redistributing Media Builder, keep this file and
`flac/vendor/LICENSE-libflacjs.txt` with `flac/vendor/libflac.js`.
