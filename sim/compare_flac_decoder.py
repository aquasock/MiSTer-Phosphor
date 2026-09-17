#!/usr/bin/env python3
"""Cross-check flac_ddr_decoder.sv (reused verbatim from MiSTer-Phosphor,
never simulated anywhere before this) against ffmpeg's own real FLAC
decoder -- an independent reference decoder, not code sharing any logic
with the RTL under test, matching this project's established validation
discipline for every other stage.

Usage: compare_flac_decoder.py test_vectors/stereo_44100.flac [max_samples]
"""
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def run_reference(flac_path: str):
    pcm_path = "/tmp/_cmp_flac_ref.pcm"
    subprocess.run(
        [
            "ffmpeg", "-hide_banner", "-y", "-loglevel", "error",
            "-i", flac_path, "-f", "s16le", "-acodec", "pcm_s16le", pcm_path,
        ],
        check=True,
    )
    data = open(pcm_path, "rb").read()
    samples = []
    for i in range(0, len(data), 4):
        left = int.from_bytes(data[i:i + 2], "little", signed=True)
        right = int.from_bytes(data[i + 2:i + 4], "little", signed=True)
        samples.append((left, right))
    return samples


def run_sim(flac_path: str) -> str:
    hex_path = "/tmp/_cmp_flac.hex"
    subprocess.run(["python3", str(REPO / "tools/mp3_to_hex.py"), flac_path, hex_path], check=True)
    sim_bin = "/tmp/_cmp_flac_tb.out"
    subprocess.run(
        [
            "iverilog", "-g2012", "-o", sim_bin,
            f"-Pflac_ddr_decoder_tb.HEX_FILE=\"{hex_path}\"",
            str(REPO / "sim/flac_ddr_decoder_tb.sv"),
            str(REPO / "rtl/audio/flac/flac_ddr_decoder.sv"),
            str(REPO / "rtl/audio/flac/flac_stream_decoder.sv"),
            str(REPO / "rtl/audio/flac/flac_frame_store.sv"),
            str(REPO / "rtl/audio/flac/flac_subframe.sv"),
            str(REPO / "rtl/audio/flac/flac_predict_mac.sv"),
            str(REPO / "rtl/audio/flac/flac_stereo.sv"),
        ],
        check=True,
    )
    return subprocess.run(["vvp", sim_bin], capture_output=True, text=True, check=True).stdout


def parse_sim_output(text: str):
    samples = []
    eof_idx = None
    for line in text.splitlines():
        m = re.match(r"PCM idx=(\d+) left=(-?\d+) right=(-?\d+) eof=(\d)", line)
        if m:
            idx, left, right, eof = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
            samples.append((left, right))
            if eof:
                eof_idx = idx
        if "ERROR" in line or "TIMEOUT" in line:
            print(line)
    return samples, eof_idx


def compare(flac_path: str, max_samples: int) -> int:
    ref = run_reference(flac_path)
    if max_samples:
        ref = ref[:max_samples]
    sim_out = run_sim(flac_path)
    sim_samples, eof_idx = parse_sim_output(sim_out)

    # flac_frame_store.sv emits one extra synthetic (0,0) sample tagged
    # pcm_eof=1 after the real audio, purely as an end-of-stream protocol
    # marker for a real consumer (flac_pcm_landing.sv) to recognize and
    # drop -- not a decode bug. Strip it before comparing, the same way a
    # real consumer would.
    if eof_idx is not None and eof_idx == len(sim_samples) - 1 and sim_samples[-1] == (0, 0):
        sim_samples = sim_samples[:-1]

    if max_samples:
        sim_samples = sim_samples[:max_samples]

    mismatches = 0
    n = min(len(ref), len(sim_samples))
    if not max_samples and len(sim_samples) != len(ref):
        print(f"sample count mismatch: ref={len(ref)} sim={len(sim_samples)}")
        mismatches += 1

    for i in range(n):
        rl, rr = ref[i]
        sl, sr = sim_samples[i]
        if rl != sl or rr != sr:
            print(f"sample {i}: ref=({rl},{rr}) sim=({sl},{sr})")
            mismatches += 1
            if mismatches > 20:
                print("... too many mismatches, stopping")
                break

    if mismatches == 0:
        print(f"{flac_path}: {n} samples checked, all match exactly")
        return 0
    print(f"{flac_path}: {mismatches} mismatches")
    return 1


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    max_samples = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    return compare(sys.argv[1], max_samples)


if __name__ == "__main__":
    sys.exit(main())
