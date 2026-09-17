# Format support summary

One core, one OSD file entry (`S0,MP3WAVFL*,Load Audio;`), content-sniffed
by magic bytes at load time (`RIFF`→WAV, `fLaC`→FLAC, else MP3) — no
per-format menu. All three decoders are always present in the same
bitstream. Fixed-profile philosophy throughout: nothing outside the
accepted profile is validated or rejected; out-of-profile input is
undefined behavior, not a graceful error.

## What each format supports

| | MP3 | WAV | FLAC |
|---|---|---|---|
| Container/codec | MPEG-1 Layer III | RIFF/WAVE PCM | FLAC (native RTL decode) |
| Sample rate | 44.1 / 48 / 32 kHz | 44.1 kHz only | 44.1 kHz only |
| Bit depth | n/a (lossy) | 16-bit only | 16-bit only |
| Channels | mono or stereo | stereo only | stereo only |
| Bitrate modes | CBR/VBR/ABR, all 14 standard bitrates | n/a (uncompressed) | n/a (lossless, arbitrary block sizes) |
| Stream validation | Structural sync/bitrate/sample-rate check for frame resync only (tolerates ID3v2 tags with embedded cover art); no CRC check | None — `fmt`/`data` chunks parsed structurally, fields never validated | Requires literal `fLaC` magic at byte 0; no resync/decoy tolerance |
| Album/track navigation | n/a | n/a | Embedded-CUESHEET albums; N/P selects next/previous track using SEEKTABLE-assisted resume |
| Audio output path | Multi-rate FIFO path (`mp3_pcm_pack`→`audio_pcm_fifo`→`audio_pcm_output_adapter`), no backpressure | Fixed-44.1kHz native-audio rail (`PLAYER_PCM_*`), real backpressure | Same native-audio rail as WAV, via `flac_pcm_landing` |
| External DDR use | None | None | Yes — `flac_frame_store` double-buffers decoded frames in DDR (only DDR client in this core) |

**Explicitly out of scope / not supported by any format**: MPEG-2/2.5 LSF
(8–24 kHz MP3), dual-channel MP3 mode, free-format MP3 bitstreams, any
sample rate other than the table above, any bit depth other than 16-bit,
mono/multichannel WAV or FLAC, compressed WAV (ADPCM etc.), general seek,
pause, or playlist support beyond FLAC album next/previous-track navigation.

## Resource usage (Cyclone V 5CSEBA6U23I7, full board-level design)

| Stage | ALMs | % | Registers | M10K blocks | DSP blocks | PLLs |
|---|---|---|---|---|---|---|
| MP3 only (pre-unification) | 11,271 | 27% | ~15,038 | — | — | 3 |
| + WAV (Stage 1) | 11,577 | 28% | — | — | — | 3 |
| + FLAC (Stage 2) | 13,512 | 32% | 16,686 | 191/553 (35%) | 67/112 (60%) | 4/6 (67%) |
| + FLAC albums (current) | 14,354 | 34% | 18,074 | 196/553 (35%) | 67/112 (60%) | 4/6 (67%) |
| + three visualizers, HDMI + analog (current) | 15,952 | 38% | 21,549 | 226/553 (41%) | 77/112 (69%) | 4/6 (67%) |

FLAC's LPC/prediction engine, Rice/CRC processing, and DDR interface
account for the largest single jump (+1,947 ALMs); CUESHEET parsing,
track/seek tables, and navigation add another 842 ALMs. The waveform, FFT,
and XY visualizers add 1,554 ALMs, 30 M10Ks, and 10 DSPs. Comfortably within
budget on this device at every stage; DSP usage (69%) is the tightest
resource, driven mostly by the standard MiSTer video-scaler framework
(`ascal`), not the audio decoders themselves.

## Timing

**Fully closed — zero violations of any kind** (setup, hold, recovery,
removal, minimum pulse width) across every clock domain, confirmed via
real Quartus `quartus_map`/`fit`/`sta`/`asm` (0 errors).

| Check | Worst-case slack |
|---|---|
| Setup | 0.771 ns |
| Hold | 0.246 ns |
| Recovery | 3.510 ns |
| Removal | 0.660 ns |

The only nontrivial timing work was closing async-reset-into-CDC-
synchronizer paths feeding `media_native_audio` (the WAV/FLAC audio rail)
from this core's own reset/new-file/format-dispatch logic — resolved via
`set_false_path` exceptions in `MiSTer_MP3.sdc`, not RTL changes. Full
history in `docs/MP3.md`.
