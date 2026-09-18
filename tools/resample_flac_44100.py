#!/usr/bin/env python3
"""Resample audio to 44.1 kHz stereo FLAC and trim to a CD-sector boundary."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


SECTOR_SAMPLES = 588
CHANNELS = 2
BYTES_PER_SAMPLE = 2
BYTES_PER_FRAME = CHANNELS * BYTES_PER_SAMPLE


def run(command: list[str]) -> None:
    try:
        subprocess.run(command, check=True)
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"FFmpeg failed with exit code {exc.returncode}") from exc


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Resample audio to 44.1 kHz, 16-bit stereo FLAC and remove the "
            "final partial 588-sample CD sector."
        )
    )
    parser.add_argument("input", type=Path, help="source audio file")
    parser.add_argument("output", type=Path, help="destination .flac file")
    parser.add_argument(
        "--compression",
        type=int,
        choices=range(0, 13),
        default=8,
        metavar="0-12",
        help="FFmpeg FLAC compression level (default: 8)",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="replace an existing output file",
    )
    args = parser.parse_args()

    if shutil.which("ffmpeg") is None:
        parser.error("ffmpeg was not found in PATH")
    if not args.input.is_file():
        parser.error(f"input file does not exist: {args.input}")
    if args.output.suffix.lower() != ".flac":
        parser.error("output filename must end in .flac")
    if args.output.exists() and not args.overwrite:
        parser.error(f"output already exists: {args.output} (use --overwrite)")

    args.output.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="mister_mp3_resample_") as temp_dir:
        raw_path = Path(temp_dir) / "resampled.s16le"
        trimmed_path = Path(temp_dir) / "trimmed.s16le"

        # Decode, mix/duplicate to stereo, resample with libsoxr, and quantize
        # once to the MiSTer core's supported signed 16-bit PCM profile.
        run(
            [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-i",
                str(args.input),
                "-map_metadata",
                "-1",
                "-vn",
                "-ac",
                "2",
                "-af",
                "aresample=44100:resampler=soxr:precision=28:dither_method=triangular",
                "-ar",
                "44100",
                "-f",
                "s16le",
                str(raw_path),
            ]
        )

        byte_count = raw_path.stat().st_size
        if byte_count % BYTES_PER_FRAME:
            raise SystemExit("resampled PCM has an incomplete stereo sample frame")

        sample_frames = byte_count // BYTES_PER_FRAME
        trim_frames = sample_frames % SECTOR_SAMPLES
        kept_frames = sample_frames - trim_frames
        if kept_frames == 0:
            raise SystemExit("input is shorter than one 588-sample sector")

        keep_bytes = kept_frames * BYTES_PER_FRAME
        with raw_path.open("rb") as source, trimmed_path.open("wb") as destination:
            remaining = keep_bytes
            while remaining:
                block = source.read(min(1024 * 1024, remaining))
                if not block:
                    raise SystemExit("unexpected end of temporary PCM data")
                destination.write(block)
                remaining -= len(block)

        output_flag = "-y" if args.overwrite else "-n"
        run(
            [
                "ffmpeg",
                "-hide_banner",
                "-loglevel",
                "error",
                output_flag,
                "-f",
                "s16le",
                "-ar",
                "44100",
                "-ac",
                "2",
                "-i",
                str(trimmed_path),
                "-c:a",
                "flac",
                "-compression_level",
                str(args.compression),
                str(args.output),
            ]
        )

    duration = kept_frames / 44100
    print(f"Created: {args.output}")
    print(f"Kept: {kept_frames:,} stereo sample frames ({duration:.6f} seconds)")
    print(f"Trimmed from end: {trim_frames} sample frames ({trim_frames / 44100:.6f} seconds)")
    print(f"CD sectors: {kept_frames // SECTOR_SAMPLES:,} (remainder 0)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
