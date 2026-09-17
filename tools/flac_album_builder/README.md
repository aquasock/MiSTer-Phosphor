# MiSTer FLAC Album Builder

Open `index.html` in a current desktop Chrome-compatible browser. No web
server, installation, account, or upload is required.

The app accepts individual native FLAC tracks, preserves their selected order,
decodes and losslessly re-encodes them as one continuous stream, and injects a
standard embedded CD CUESHEET and a frame-aligned SEEKTABLE containing at most
512 points.

Inputs must use the MiSTer_MP3 profile: 44.1 kHz, 16-bit, stereo. CD CUESHEET
track offsets must be divisible by 588 samples, so the app rejects
non-sector-aligned inputs instead of silently inserting audio gaps.

Optional **Circular album** mode examines the decoded PCM at only the start of
track 1 and the end of the final track. It removes whole 588-sample CD sectors
that contain exact digital zeroes. Partial sectors, low-level fades, and all
nonzero audio remain untouched, and the completion message reports the exact
duration removed. This is destructive by design and is disabled by default.

The advanced **Tight loop** choice removes consecutive outer CD sectors whose
stereo RMS is below -50 dBFS. It can make deliberately faded circular masters
sound more immediate, but it removes real low-level audio. The result reports
the separate start and end trims so the edit is auditable.

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
