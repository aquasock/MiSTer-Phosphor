# MiSTer FLAC Album Splitter

Open `index.html` in a current desktop Chrome-compatible browser. No web
server, installation, account, or upload is required.

The app reads the standard embedded CUESHEET from a MiSTer_MP3 FLAC album and
losslessly re-encodes each indexed track as an independently playable FLAC.
Every PCM sample and track boundary is recovered exactly; the newly encoded
FLAC container is not byte-identical to the original and does not reproduce
its tags or artwork. Tracks can be downloaded separately or together in one
uncompressed ZIP.

The source must be native FLAC using the MiSTer_MP3 profile: 44.1 kHz, 16-bit,
stereo, with an embedded CUESHEET containing INDEX 01 entries.

The splitter shares the builder's vendored libflac.js codec, distributed under
the MIT license. Keep the `flac_album_builder` and `flac_album_splitter`
directories together when copying these tools.
