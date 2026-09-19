# MiSTer Mixed Playlist Builder

Open `index.html` in Chrome or another current Chromium-based browser. Add up
to 255 MP3, Ogg Vorbis, FLAC, or WAV files, arrange them, and download a
standard uncompressed POSIX USTAR archive.

Use **Open playlist TAR** (or drop a single `.tar` onto the page) to reopen a
playlist previously made by this builder. Its audio entries are
restored in M3U order and can be reordered, removed, or combined with new
files before rebuilding. Imported audio payloads remain byte-for-byte intact.

The archive contains a standard `playlist.m3u`, the selected audio files, and
optionally `cover.art`, a builder-generated 92×92 RGB332 image used directly
by the FPGA. `#PLAYLIST:` and `#ARTIST:` lines supply the album and artist text;
`#EXTINF` supplies each displayed track title.
Their physical order in the TAR does not matter: M3U filename order controls
playback. Both plain and extended M3U are accepted. The FPGA walks only the
512-byte TAR headers, seeking over audio payloads while it builds its in-memory
directory, then resolves the M3U against that directory. Source audio files are
inserted byte-for-byte without decoding, transcoding, or metadata changes.
Duplicate filenames are disambiguated inside builder-created archives.

You can also build a playlist manually with PeaZip: put one `.m3u` plus the
referenced MP3, Ogg, FLAC, and WAV files into an uncompressed TAR archive.
Members may be added in any order. Keep the names and relative paths in the M3U
identical to those shown inside the TAR; ASCII case and slash direction are
ignored. Use ordinary TAR, not TAR.GZ, TAR.BZ2, TAR.XZ, ZIP, or 7z.
Artwork is optional; manually created archives may omit `cover.art`.

Track-to-track playback is not gapless; each entry uses the core's existing
standalone-file decoder path.
