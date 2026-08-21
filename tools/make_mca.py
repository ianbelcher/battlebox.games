#!/usr/bin/env python3
"""Writes a minimal-but-valid Anvil region file (r.0.0.mca) exercising the
modern chunk format: 1.18+ layout (sections list at root, block_states with
palette + packed long data, no spanning across longs), zlib compression.

World content (per chunk, all 4x4 chunks the same):
  mc y = 60..63 : stone
  mc y = 64    : grass_block
  mc y = 65    : one oak_log at local (3, 5); one poppy at (5, 7); rest air
  plus a single-entry-palette section of all air above.
"""
import struct
import zlib
import os
import sys

out_dir = sys.argv[1]
os.makedirs(out_dir, exist_ok=True)


def tag_byte(name, v):
    return b"\x01" + _name(name) + struct.pack(">b", v)

def tag_int(name, v):
    return b"\x03" + _name(name) + struct.pack(">i", v)

def tag_long_array(name, longs):
    return b"\x0c" + _name(name) + struct.pack(">i", len(longs)) + b"".join(
        struct.pack(">q", v) for v in longs)

def tag_string(name, v):
    body = v.encode()
    return b"\x08" + _name(name) + struct.pack(">H", len(body)) + body

def _name(name):
    body = name.encode()
    return struct.pack(">H", len(body)) + body

def compound(name, children):
    return b"\x0a" + _name(name) + b"".join(children) + b"\x00"

def anon_compound(children):
    # compound payload only (for list entries)
    return b"".join(children) + b"\x00"

def list_of_compounds(name, entries):
    return b"\x09" + _name(name) + b"\x0a" + struct.pack(">i", len(entries)) + b"".join(entries)


def pack_indices(indices, bits):
    per_long = 64 // bits
    longs = []
    for i in range(0, len(indices), per_long):
        v = 0
        for j, idx in enumerate(indices[i:i + per_long]):
            v |= (idx & ((1 << bits) - 1)) << (j * bits)
        if v >= 1 << 63:
            v -= 1 << 64
        longs.append(v)
    return longs


def palette_entry(mc_name):
    return anon_compound([tag_string("Name", mc_name)])


def section(y_index, palette_names, indices=None):
    children = [tag_byte("Y", y_index)]
    palette = list_of_compounds("palette", [palette_entry(n) for n in palette_names])
    states = [palette]
    if indices is not None:
        bits = max(4, (len(palette_names) - 1).bit_length())
        states.append(tag_long_array("data", pack_indices(indices, bits)))
    block_states = compound("block_states", states)
    children.append(block_states)
    return anon_compound(children)


def chunk_nbt(cx, cz):
    # Section y=3 covers mc y 48..63; y=4 covers 64..79.
    # Section 3: bottom 12 layers stone-free (air), top 4 layers (60..63) stone.
    palette3 = ["minecraft:air", "minecraft:stone"]
    idx3 = []
    for y in range(16):
        idx3.extend([1] * 256)  # solid stone; still exercises packed data
    # Section 4: layer 0 (mc 64) grass; layer 1 (mc 65): log at (3,5), poppy at
    # (5,7); air above.
    palette4 = ["minecraft:air", "minecraft:grass_block", "minecraft:oak_log", "minecraft:poppy"]
    idx4 = []
    for y in range(16):
        for z in range(16):
            for x in range(16):
                if y == 0:
                    idx4.append(1)
                elif y == 1 and x == 3 and z == 5:
                    idx4.append(2)
                elif y == 1 and x == 5 and z == 7:
                    idx4.append(3)
                else:
                    idx4.append(0)
    sections = [
        section(0, ["minecraft:stone"]),   # solid underside, like a real world
        section(1, ["minecraft:stone"]),
        section(2, ["minecraft:stone"]),
        section(3, palette3, idx3),
        section(4, palette4, idx4),
        section(5, ["minecraft:air"]),  # single-palette section, no data tag
    ]
    root = compound("", [
        tag_int("xPos", cx),
        tag_int("zPos", cz),
        tag_string("Status", "minecraft:full"),
        list_of_compounds("sections", sections),
    ])
    return root


locations = bytearray(4096)
timestamps = bytearray(4096)
payloads = b""
sector = 2
for cz in range(4):
    for cx in range(4):
        raw = chunk_nbt(cx, cz)
        comp = zlib.compress(raw)
        body = struct.pack(">i", len(comp) + 1) + b"\x02" + comp
        padded = body + b"\x00" * ((4096 - len(body) % 4096) % 4096)
        count = len(padded) // 4096
        head = 4 * (cx + cz * 32)
        locations[head:head + 4] = struct.pack(">i", (sector << 8) | count)
        payloads += padded
        sector += count

with open(os.path.join(out_dir, "r.0.0.mca"), "wb") as f:
    f.write(bytes(locations) + bytes(timestamps) + payloads)
print("wrote", os.path.join(out_dir, "r.0.0.mca"), len(locations) + len(timestamps) + len(payloads), "bytes")
