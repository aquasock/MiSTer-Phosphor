# MiSTer FLAC Album Builder

Open `index.html` in a current desktop Chrome-compatible browser. No web
server, installation, account, or upload is required.

The app accepts individual native FLAC tracks, preserves every decoded sample
in the selected order, losslessly re-encodes them as one continuous stream,
and injects a standard embedded CD CUESHEET and a frame-aligned SEEKTABLE
containing at most 512 points. It never trims, pads, fades, or otherwise edits
the audio.

The builder also copies the first available album title, album artist, track
titles, and front-cover image into an `MP3A` FLAC APPLICATION metadata block.
Artwork is converted to a letterboxed 92×92 RGB332 thumbnail for the FPGA UI.
This changes only FLAC metadata; the encoded PCM sample sequence is unchanged.
Missing fields use filename or generic fallbacks.
Playlist titles are stored in a 24-character display form and the compact
current-track fields use 15 characters. Longer values end in `...`.

Inputs must use the MiSTer_MP3 profile: 44.1 kHz, 16-bit, stereo. CD CUESHEET
track offsets must be divisible by 588 samples, so the app rejects
non-sector-aligned inputs instead of silently inserting audio gaps.

MiSTer_MP3 repeats indexed albums automatically. Whether the last sample joins
the first musically is therefore determined entirely by the supplied tracks;
the builder does not attempt to alter that boundary.

The companion splitter recovers each track with exactly the same PCM samples
and boundaries. Its FLAC containers are newly encoded, so compression layout,
metadata, tags, artwork, and original filenames are not reproduced.

Desktop Chrome, Chromium, Edge, and ChromeOS are the primary targets. The app
processes one source file at a time, but retains the compressed output until
download. Very large albums can exceed mobile-browser memory limits.

## Validate an exported album

Run `python3 validate_album.py album.flac`. The validator applies the same
profile, table-size, track-order, and seek-offset rules as the FPGA controller.

## Third-party codec

`vendor/libflac.js` is libflac.js 5.6.0 by M. M. G. and contributors,
distributed under the MIT license. See `vendor/LICENSE-libflacjs.txt` and
https://github.com/mmig/libflac.js.
