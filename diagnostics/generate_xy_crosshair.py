#!/usr/bin/env python3
"""Generate seamless 44.1 kHz stereo PCM for the XY circle/crosshair test."""

import math
import struct
import sys


SAMPLE_RATE = 44_100
CYCLE_SAMPLES = 245  # 180 complete drawings/s: exactly three per 60 Hz frame.
AMPLITUDE = 32_767


def line(start, end, count):
    """Include start and leave end for the following connected segment."""
    x0, y0 = start
    x1, y1 = end
    return [
        (
            round(x0 + (x1 - x0) * index / count),
            round(y0 + (y1 - y0) * index / count),
        )
        for index in range(count)
    ]


def main():
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} OUTPUT.pcm")

    # Route: center -> right edge -> full circle -> full horizontal diameter
    # -> center -> full vertical diameter -> center. Every connector is part
    # of the requested crosshair, and the final-to-first transition is the
    # same small step as every other 180 Hz repetition.
    lengths = [1.0, 2.0 * math.pi, 2.0, 1.0, 1.0, 2.0, 1.0]
    raw_counts = [CYCLE_SAMPLES * value / sum(lengths) for value in lengths]
    counts = [math.floor(value) for value in raw_counts]
    for index in sorted(
        range(len(counts)), key=lambda item: raw_counts[item] - counts[item], reverse=True
    )[: CYCLE_SAMPLES - sum(counts)]:
        counts[index] += 1

    center = (0, 0)
    right = (AMPLITUDE, 0)
    left = (-AMPLITUDE, 0)
    top = (0, AMPLITUDE)
    bottom = (0, -AMPLITUDE)

    cycle = []
    cycle.extend(line(center, right, counts[0]))
    cycle.extend(
        (
            round(AMPLITUDE * math.cos(2.0 * math.pi * index / counts[1])),
            round(AMPLITUDE * math.sin(2.0 * math.pi * index / counts[1])),
        )
        for index in range(counts[1])
    )
    cycle.extend(line(right, left, counts[2]))
    cycle.extend(line(left, center, counts[3]))
    cycle.extend(line(center, top, counts[4]))
    cycle.extend(line(top, bottom, counts[5]))
    cycle.extend(line(bottom, center, counts[6]))
    assert len(cycle) == CYCLE_SAMPLES

    with open(sys.argv[1], "wb") as output:
        for _ in range(720):  # Exactly four seconds.
            for x, y in cycle:
                output.write(struct.pack("<hh", x, y))


if __name__ == "__main__":
    main()
