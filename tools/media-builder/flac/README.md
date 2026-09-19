# MiSTer FLAC Album Builder

Open `index.html` in a current desktop Chrome-compatible browser. No web
server, installation, account, or upload is required.

The app accepts individual native FLAC tracks, preserves every decoded sample
in the selected order, and losslessly re-encodes them as one continuous FLAC.
It injects a standard embedded CUESHEET, a frame-aligned SEEKTABLE with at most
512 points, and MiSTer_MP3's compact MP3A display metadata and artwork. It never
trims, pads, fades, or otherwise edits the audio.

The MP3A block carries the first available album title and album artist, each
track title, and converted cover artwork. Missing fields use filenames or
generic fallbacks. The FPGA truncates display text with an ellipsis where
necessary.

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

The downloaded `.flac` is opened directly by MiSTer_MP3; no TAR is involved.

## Third-party codec

`vendor/libflac.js` is libflac.js 5.6.0 by M. M. G. and contributors,
distributed under the MIT license. See `vendor/LICENSE-libflacjs.txt` and
https://github.com/mmig/libflac.js.
