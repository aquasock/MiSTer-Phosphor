# MiSTer FLAC Album Builder

Open `index.html` in a current desktop Chrome-compatible browser. No web
server, installation, account, or upload is required.

The app accepts individual native FLAC tracks, preserves every decoded sample
in the selected order, and losslessly re-encodes them as one continuous FLAC.
It injects a standard embedded CUESHEET, a frame-aligned SEEKTABLE with at most
512 points, and MiSTer_MP3's compact MP3A display metadata and artwork. It never
trims, pads, fades, or otherwise edits the audio.

The MP3A block carries the album title, album artist, each track title, and
converted cover artwork. The **Album title**, **Album artist**, and **Album
artwork** fields match those of the mixed playlist builder. They are prefilled
from the first source track that has an album tag, an album-artist (or artist)
tag, and an embedded picture, and stay in sync as tracks are added, removed, or
reordered until you edit them. Typing a value or choosing an image file
overrides the tags; emptying a text field returns it to the tags, and Clear
resets all three. Missing fields use filenames or generic fallbacks. The FPGA
truncates display text with an ellipsis where necessary.

By default inputs must use the MiSTer_MP3 profile: 44.1 kHz, 16-bit, stereo. CD
CUESHEET track offsets must be divisible by 588 samples, so the app rejects
non-sector-aligned inputs instead of silently inserting audio gaps.

## Converting high-resolution FLACs

The core plays 44.1 and 48 kHz, 16-bit stereo FLAC albums. The optional
**Convert high-resolution FLACs** setting (off by default) accepts stereo 16- or
24-bit tracks above 44.1 kHz and downsamples them to one common album format,
either 44.1 or 48 kHz at 16 bits. Off, the audio is never altered; on, only the
tracks that need it are converted, and tracks already in the target format are
copied bit for bit.

- **Target rate.** The app picks whichever of 44.1 and 48 kHz needs the simplest
  conversions: exact integer ratios first (88.2, 176.4 and 352.8 kHz to 44.1;
  96, 192 and 384 kHz to 48), then the fewer conversions. A target that would
  upsample any track is never chosen, so an album mixing 44.1 kHz and 96 kHz
  tracks becomes 44.1 kHz. Sources below 44.1 kHz, mono, or bit depths other than
  16 and 24 are rejected. The chosen target and each conversion appear in the
  track list.
- **Resampler.** A polyphase Kaiser-windowed sinc filter (about 96 dB stopband, no
  delay) handles any rational ratio, such as 96 to 44.1 kHz (147/320). It is flat
  to 20 kHz (21.6 kHz at a 48 kHz target) and nothing above the new Nyquist
  frequency folds back into that band; the transition band is centred on Nyquist,
  so content between 20 kHz and Nyquist rolls off. Consecutive tracks at one source rate are resampled as a
  single continuous stream, so gapless recordings stay gapless.
- **16-bit output.** Converted audio is requantized with TPDF dither (a fixed
  seed, so rebuilding gives an identical file). Samples that would exceed full
  scale are clamped and the total is reported after the build; a large count
  means the source is mastered too hot to convert without attenuation.
- **CUESHEET.** Converted albums keep 588-sample CD-sector offsets by moving each
  track marker back to the previous sector (at most 588 samples, 12 ms at 48 kHz),
  so no track start is ever cut off. The audio itself is not moved, and no gap is
  inserted between tracks. Under one sector of silence is added after the last
  track so the lead-out is sector aligned; this matters only where a repeating
  album loops.
- **Verification.** The finished file is re-read and its rate, bit depth, channel
  count and length are checked, and every decoded track must contain exactly the
  number of samples its header declares.

Conversion is lossy by nature: the result is a very high quality 16-bit
rendition, not the original samples. Keep the source files.

MiSTer_MP3 repeats indexed albums automatically. Whether the last sample joins
the first musically is therefore determined entirely by the supplied tracks;
the builder does not attempt to alter that boundary.

The companion splitter recovers each track with exactly the same PCM samples
and boundaries. Its FLAC containers are newly encoded, so compression layout,
metadata, tags, artwork, and original filenames are not reproduced.

Desktop Chrome, Chromium, Edge, and ChromeOS are the primary targets. The app
processes one source file at a time, decoding and converting in short
steps so the page stays responsive, but retains the compressed output until
download. Very large albums can exceed mobile-browser memory limits.

The downloaded `.flac` is opened directly by MiSTer_MP3; no TAR is involved.

## Third-party codec

`vendor/libflac.js` is libflac.js 5.6.0 by M. M. G. and contributors,
distributed under the MIT license. See `vendor/LICENSE-libflacjs.txt` and
https://github.com/mmig/libflac.js.
