#!/usr/bin/env python3
"""Dump an MP3 file as one hex byte per line, for $readmemh in a testbench.

Usage: mp3_to_hex.py input.mp3 output.hex
"""
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    data = open(sys.argv[1], "rb").read()
    with open(sys.argv[2], "w") as f:
        for b in data:
            f.write(f"{b:02x}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
