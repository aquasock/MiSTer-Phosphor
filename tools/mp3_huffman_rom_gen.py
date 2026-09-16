#!/usr/bin/env python3
"""Generates $readmemh ROM content for the RTL Huffman decoder from the
verified canonical tables in mp3_huffman_tables.py.

Binary-trie representation, not range-based addressing: an earlier version
of this generator assumed codes of the same length, sorted by code value,
form a contiguous range -- true for a "complete" canonical code but NOT
guaranteed here (ff_vlc_init_from_lengths's order-sensitive construction
can leave gaps in a length's code range, since intervening entries of
other lengths consume part of the code space between them). A binary trie
is correct for any prefix code regardless of gaps: each internal node
holds {left_child_addr, right_child_addr}; each leaf holds {x, y}. Walking
one bit at a time from a table's root, following left (bit=0) or right
(bit=1), always terminates at the correct leaf -- this is just the
definition of a prefix code, not an assumption about code layout.

Outputs (under rtl/):
  mp3_huffman_nodes.hex    -- one global node ROM, all 15 tables' tries
                               concatenated; mp3_huffman_roots.hex gives
                               each table's root node address into it.
                               Word format (25 bits): bit24=is_leaf;
                               leaf: bits[7:4]=x, bits[3:0]=y, rest 0;
                               internal: bits[23:12]=left_addr, bits[11:0]=right_addr.
  mp3_huffman_roots.hex    -- root node address per physical table (1..15).
  mp3_band_index_long.hex  -- band_index_long[sample_rate_index][23], two
                               rows (44100, 48000), 23 entries each.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mp3_huffman_tables import ALL_TABLES
from mp3_huffman_source_data import BAND_SIZE_LONG, QUAD_CODES, QUAD_BITS

OUT_DIR = Path(__file__).resolve().parent.parent / "rtl"

# Physical tables 1..15 (big_values pairs) followed by the two quadruples
# (count1) tables, all sharing one trie-walk ROM format and RTL walker.
# Root addresses 16 and 17 (quad A, quad B) let the same hardware handle
# count1 decode with no separate logic -- a quad leaf packs its 4-bit
# symbol (v<<3|w<<2|x<<1|y) into the format's y nibble with x forced 0,
# since a quad symbol is a single 0-15 index, not an (x,y) pair.
PHYSICAL_TABLE_ORDER = [1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15, 16, 24]
QUAD_TABLE_ORDER = ["A", "B"]
ADDR_BITS = 12  # up to 4096 nodes total -- comfortably covers ~1400 entries worth of tries


class Node:
    __slots__ = ("left", "right", "leaf_val")

    def __init__(self):
        self.left = None
        self.right = None
        self.leaf_val = None  # (x, y) once this becomes a leaf


def insert(root, code, length, x, y):
    node = root
    for i in range(length - 1, -1, -1):
        bit = (code >> i) & 1
        if i == 0:
            child = Node()
            child.leaf_val = (x, y)
            if bit:
                assert node.right is None, "duplicate code"
                node.right = child
            else:
                assert node.left is None, "duplicate code"
                node.left = child
            return
        if bit:
            if node.right is None:
                node.right = Node()
            assert node.right.leaf_val is None, "prefix collision: shorter code already a leaf here"
            node = node.right
        else:
            if node.left is None:
                node.left = Node()
            assert node.left.leaf_val is None, "prefix collision: shorter code already a leaf here"
            node = node.left


def flatten(root, nodes):
    """Post-order-ish flatten: assigns each node a global index, returns that index."""
    if root.leaf_val is not None:
        x, y = root.leaf_val
        word = (1 << 24) | (x << 4) | y
        nodes.append(word)
        return len(nodes) - 1
    left_addr = flatten(root.left, nodes) if root.left else 0
    right_addr = flatten(root.right, nodes) if root.right else 0
    word = (0 << 24) | (left_addr << 12) | right_addr
    nodes.append(word)
    return len(nodes) - 1


def gen_huffman_roms():
    nodes = []
    roots = []
    for name in PHYSICAL_TABLE_ORDER:
        root = Node()
        for code, length, x, y in ALL_TABLES[name]:
            insert(root, code, length, x, y)
        root_addr = flatten(root, nodes)
        assert root_addr < (1 << ADDR_BITS), "node address overflow, widen ADDR_BITS"
        roots.append(root_addr)

    for letter in QUAD_TABLE_ORDER:
        root = Node()
        codes, bits = QUAD_CODES[letter], QUAD_BITS[letter]
        for sym in range(16):
            insert(root, codes[sym], bits[sym], 0, sym)
        root_addr = flatten(root, nodes)
        assert root_addr < (1 << ADDR_BITS), "node address overflow, widen ADDR_BITS"
        roots.append(root_addr)

    with open(OUT_DIR / "mp3_huffman_nodes.hex", "w") as f:
        for word in nodes:
            f.write(f"{word:07x}\n")
    with open(OUT_DIR / "mp3_huffman_roots.hex", "w") as f:
        for addr in roots:
            f.write(f"{addr:03x}\n")

    print(f"huffman trie: {len(nodes)} total nodes across "
          f"{len(PHYSICAL_TABLE_ORDER)} big_values tables + {len(QUAD_TABLE_ORDER)} quad tables")
    print(f"roots: {roots}")


def gen_band_index_rom():
    lines = []
    for sr in (44100, 48000):
        sizes = BAND_SIZE_LONG[sr]
        idx = [0]
        k = 0
        for size in sizes:
            k += size >> 1
            idx.append(k)
        assert len(idx) == 23
        for v in idx:
            lines.append(f"{v:03x}")
    with open(OUT_DIR / "mp3_band_index_long.hex", "w") as f:
        for line in lines:
            f.write(line + "\n")
    print(f"band index: {len(lines)} entries (2 sample rates x 23)")


if __name__ == "__main__":
    OUT_DIR.mkdir(exist_ok=True)
    gen_huffman_roms()
    gen_band_index_rom()
