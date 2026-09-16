#!/usr/bin/env python3
"""Generates the combined IMDCT+window coefficient ROM for rtl/mp3_imdct.sv.

Rather than a separate 36-point IMDCT pass followed by a separate 36-tap
window multiply, this folds window[block_type][i] * cos(...) into ONE
precomputed table: since output[i] = window[i] * sum_k(x[k]*cos[i][k]) =
sum_k(x[k] * (window[i]*cos[i][k])), the window multiply can be pushed
inside the same accumulation loop that computes the IMDCT sum, with no
separate temporary array needed for the unwindowed IMDCT result. Four
variants (long=0, start=1, stop=3, short=4th/bt_sel-3 -- see below) x 36
output positions x 18 input positions = 2592 entries.

The short-block variant (bt_sel index 3) reuses this exact same 36x18
shape and the exact same RTL MAC loop (rtl/mp3_imdct.sv's
S_MAC_ISSUE/S_MAC_ACC, k=0..17) with NO datapath changes, even though the
real short-block transform is three independent 12-point IMDCTs (one per
short window) rather than one 36-tap sum: at most 2 of the 3 short
windows ever contribute to any single output position out_i (see
tools/mp3_imdct_reference.py's imdct_short_block_fixed() for the full
derivation, hand-traced from FFmpeg's fused imdct12()+overlap-add
implementation and confirmed against real FFmpeg output), so each row of
this table has only 6 or 12 of its 18 entries nonzero -- the inactive
window's taps are simply zero, and the shared 18-tap MAC loop naturally
adds nothing for them.

See tools/mp3_imdct_reference.py for the IMDCT formula derivation and
docs/MP3.md for the validation methodology.
"""
import math
import sys
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "rtl"

N = 36
K = 18
FRAC_BITS = 16
SHORT_N = 12
SHORT_K = 6


def _window(block_type_idx):
    w = [0.0] * N
    for i in range(N):
        d = math.sin(math.pi * (i + 0.5) / 36.0)
        if block_type_idx == 1:  # start
            if i >= 30:
                d = 0.0
            elif i >= 24:
                d = math.sin(math.pi * (i - 18 + 0.5) / 12.0)
            elif i >= 18:
                d = 1.0
        elif block_type_idx == 3:  # stop
            if i < 6:
                d = 0.0
            elif i < 12:
                d = math.sin(math.pi * (i - 6 + 0.5) / 12.0)
            elif i < 18:
                d = 1.0
        w[i] = d
    return w


WINDOWS = {0: _window(0), 1: _window(1), 3: _window(3)}
# RTL index 0/1/2 -> block_type 0(long)/1(start)/3(stop); index 3 -> short.
BT_ORDER = [0, 1, 3]

SHORT_WINDOW = [math.sin(math.pi * (i + 0.5) / 12.0) for i in range(SHORT_N)]


def _short_row(out_i):
    """Row of 18 combined coefficients (k = 3*f + w) for one short-block
    output position -- zero for any (f, w) not among the at-most-2 windows
    active at this out_i. See tools/mp3_imdct_reference.py's
    imdct_short_block_fixed() for the derivation this mirrors exactly."""
    row = [0] * K

    def add_window(w, i_local):
        for f in range(SHORT_K):
            c = math.cos(math.pi / (2 * SHORT_N) * (2 * i_local + 1 + SHORT_N // 2) * (2 * f + 1))
            row[3 * f + w] += SHORT_WINDOW[i_local] * c

    if out_i < 6 or out_i >= 30:
        pass
    elif out_i < 12:
        add_window(0, out_i - 6)
    elif out_i < 18:
        add_window(1, out_i - 12)
        add_window(0, out_i - 6)
    elif out_i < 24:
        add_window(2, out_i - 18)
        add_window(1, out_i - 12)
    else:
        add_window(2, out_i - 18)
    return row


def gen_combined_rom():
    lines = []
    max_val = 0

    def emit_row(tag, i, row):
        nonlocal max_val
        for k, val in enumerate(row):
            v = round(val * (1 << FRAC_BITS))
            max_val = max(max_val, abs(v))
            assert -(1 << 17) <= v < (1 << 17), f"combined coeff {tag} i={i} k={k} v={v} overflows 18 bits"
            lines.append(f"{v & 0x3FFFF:05x}")

    for bt in BT_ORDER:
        win = WINDOWS[bt]
        for i in range(N):
            c_row = [win[i] * math.cos(math.pi / (2 * N) * (2 * i + 1 + N // 2) * (2 * k + 1)) for k in range(K)]
            emit_row(f"bt={bt}", i, c_row)

    for out_i in range(N):
        emit_row("short", out_i, _short_row(out_i))

    with open(OUT_DIR / "mp3_imdct_coeff.hex", "w") as f:
        for line in lines:
            f.write(line + "\n")
    print(f"combined IMDCT+window ROM: {len(lines)} entries (3 long block types + 1 short x 36 x 18), max magnitude {max_val}")


if __name__ == "__main__":
    OUT_DIR.mkdir(exist_ok=True)
    gen_combined_rom()
