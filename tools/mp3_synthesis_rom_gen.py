#!/usr/bin/env python3
"""Generates the two coefficient ROMs for rtl/mp3_synthesis.sv: the 64x32
matrixing table (Q16 fixed-point cosines) and the 512-entry window table
(the ISO-standard polyphase prototype filter, used at its natural
~WFRAC_BITS=16 integer scale, no rescaling -- see
tools/mp3_synthesis_reference.py's module docstring for why this stage,
uniquely among this project's stages, reuses FFmpeg's own real
fixed-point convention rather than choosing an independent one: it's the
final stage, and its output must BE correctly-scaled 16-bit PCM.

Unlike mp3_imdct_rom_gen.py, these two tables can NOT be folded together
into one combined coefficient: the window multiply's 16-term sum reuses
each matrixing output (V[i]) across MULTIPLE different final output
samples as it ages through the 1024-entry persistent history (via the
U-extraction index remapping), pairing it with a DIFFERENT window
coefficient each time -- there is no single fixed (output, input) pair to
pre-multiply the way IMDCT's window and cosine shared the same index.
"""
import math
from pathlib import Path

OUT_DIR = Path(__file__).resolve().parent.parent / "rtl"

FRAC_BITS = 16

# See tools/mp3_synthesis_reference.py for ENWINDOW's provenance and the
# window-construction rule.
ENWINDOW = [
    0, -1, -1, -1, -1, -1, -1, -2,
    -2, -2, -2, -3, -3, -4, -4, -5,
    -5, -6, -7, -7, -8, -9, -10, -11,
    -13, -14, -16, -17, -19, -21, -24, -26,
    -29, -31, -35, -38, -41, -45, -49, -53,
    -58, -63, -68, -73, -79, -85, -91, -97,
    -104, -111, -117, -125, -132, -139, -147, -154,
    -161, -169, -176, -183, -190, -196, -202, -208,
    213, 218, 222, 225, 227, 228, 228, 227,
    224, 221, 215, 208, 200, 189, 177, 163,
    146, 127, 106, 83, 57, 29, -2, -36,
    -72, -111, -153, -197, -244, -294, -347, -401,
    -459, -519, -581, -645, -711, -779, -848, -919,
    -991, -1064, -1137, -1210, -1283, -1356, -1428, -1498,
    -1567, -1634, -1698, -1759, -1817, -1870, -1919, -1962,
    -2001, -2032, -2057, -2075, -2085, -2087, -2080, -2063,
    2037, 2000, 1952, 1893, 1822, 1739, 1644, 1535,
    1414, 1280, 1131, 970, 794, 605, 402, 185,
    -45, -288, -545, -814, -1095, -1388, -1692, -2006,
    -2330, -2663, -3004, -3351, -3705, -4063, -4425, -4788,
    -5153, -5517, -5879, -6237, -6589, -6935, -7271, -7597,
    -7910, -8209, -8491, -8755, -8998, -9219, -9416, -9585,
    -9727, -9838, -9916, -9959, -9966, -9935, -9863, -9750,
    -9592, -9389, -9139, -8840, -8492, -8092, -7640, -7134,
    6574, 5959, 5288, 4561, 3776, 2935, 2037, 1082,
    70, -998, -2122, -3300, -4533, -5818, -7154, -8540,
    -9975, -11455, -12980, -14548, -16155, -17799, -19478, -21189,
    -22929, -24694, -26482, -28289, -30112, -31947, -33791, -35640,
    -37489, -39336, -41176, -43006, -44821, -46617, -48390, -50137,
    -51853, -53534, -55178, -56778, -58333, -59838, -61289, -62684,
    -64019, -65290, -66494, -67629, -68692, -69679, -70590, -71420,
    -72169, -72835, -73415, -73908, -74313, -74630, -74856, -74992,
    75038,
]


def _build_window():
    window = [0] * 513
    for i in range(257):
        v = ENWINDOW[i]
        window[i] = v
        if (i & 63) != 0:
            v = -v
        if i != 0:
            window[512 - i] = v
    return window[:512]


def gen():
    window = _build_window()
    max_win = max(abs(x) for x in window)
    assert max_win < (1 << 17), f"window coefficient {max_win} overflows 18 bits"
    with open(OUT_DIR / "mp3_synthesis_window.hex", "w") as f:
        for v in window:
            f.write(f"{v & 0x3FFFF:05x}\n")
    print(f"synthesis window ROM: 512 entries, max magnitude {max_win}")

    max_mat = 0
    lines = []
    for i in range(64):
        for k in range(32):
            v = round(math.cos((16 + i) * (2 * k + 1) * math.pi / 64) * (1 << FRAC_BITS))
            max_mat = max(max_mat, abs(v))
            assert -(1 << 17) <= v < (1 << 17), f"matrix coeff i={i} k={k} v={v} overflows 18 bits"
            lines.append(f"{v & 0x3FFFF:05x}")
    with open(OUT_DIR / "mp3_synthesis_matrix.hex", "w") as f:
        for line in lines:
            f.write(line + "\n")
    print(f"synthesis matrix ROM: {len(lines)} entries (64x32), max magnitude {max_mat}")


if __name__ == "__main__":
    OUT_DIR.mkdir(exist_ok=True)
    gen()
