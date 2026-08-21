#!/usr/bin/env python3
"""Write Sponge .schem test fixtures, so the kit importer can be checked
without downloading anything.

The sites builds come from (minecraft-schematics.com and friends)
hand out Sponge .schem files, which pack their blocks as a VARINT stream
in YZX order against a name->index palette — nothing like the plain
{state, pos} list a datapack .nbt uses. This writes a small hut in that
exact format, in both the v2 and v3 layouts (v3 moved the palette and
data inside a "Blocks" compound), which is what
game/tests/import_structures.gd is tested against.

Usage: python3 tools/make_schem.py <out-dir>
"""
import gzip
import os
import struct
import sys

TAG_END, TAG_BYTE, TAG_SHORT, TAG_INT = 0, 1, 2, 3
TAG_BYTE_ARRAY, TAG_STRING, TAG_LIST, TAG_COMPOUND = 7, 8, 9, 10


def _str(text):
    return struct.pack(">H", len(text)) + text.encode()


def tag(tag_id, name, payload):
    return bytes([tag_id]) + _str(name) + payload


def t_short(name, value):
    return tag(TAG_SHORT, name, struct.pack(">h", value))


def t_int(name, value):
    return tag(TAG_INT, name, struct.pack(">i", value))


def t_bytes(name, data):
    return tag(TAG_BYTE_ARRAY, name, struct.pack(">i", len(data)) + data)


def t_compound(name, body):
    return tag(TAG_COMPOUND, name, body + bytes([TAG_END]))


def varint(value):
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        out.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(out)


def build(width=7, height=5, length=7):
    """A hut: plank floor, cobble walls, a glass window, a stair roof."""
    palette = {
        "minecraft:air": 0,
        "minecraft:cobblestone": 1,
        "minecraft:oak_planks": 2,
        "minecraft:glass": 3,
        "minecraft:oak_stairs[facing=north,half=bottom]": 4,
        "minecraft:torch": 5,
    }
    cells = {}
    for y in range(height):
        for z in range(length):
            for x in range(width):
                edge = x in (0, width - 1) or z in (0, length - 1)
                if y == 0:
                    cells[(x, y, z)] = 2
                elif y == height - 1:
                    cells[(x, y, z)] = 4
                elif edge:
                    window = y == 2 and (x == width // 2 or z == length // 2)
                    cells[(x, y, z)] = 3 if window else 1
                elif y == 1 and x == 1 and z == 1:
                    cells[(x, y, z)] = 5
    # YZX order — exactly how Sponge indexes its block array.
    data = bytearray()
    for y in range(height):
        for z in range(length):
            for x in range(width):
                data += varint(cells.get((x, y, z), 0))
    pal_body = b"".join(t_int(k, v) for k, v in palette.items())
    return width, height, length, palette, pal_body, bytes(data)


def sponge_v2(w, h, l, palette, pal_body, data):
    body = (t_int("Version", 2) + t_int("DataVersion", 3465)
            + t_short("Width", w) + t_short("Height", h) + t_short("Length", l)
            + t_int("PaletteMax", len(palette))
            + t_compound("Palette", pal_body)
            + t_bytes("BlockData", data))
    return t_compound("", t_compound("Schematic", body))


def sponge_v3(w, h, l, palette, pal_body, data):
    blocks = t_compound("Palette", pal_body) + t_bytes("Data", data)
    body = (t_int("Version", 3) + t_int("DataVersion", 3465)
            + t_short("Width", w) + t_short("Height", h) + t_short("Length", l)
            + t_compound("Blocks", blocks))
    return t_compound("", t_compound("Schematic", body))


def mcedit(w, h, l):
    """The pre-flattening MCEdit format: flat 1.12 numeric ids plus a
    metadata nibble each, which is what older downloads still are."""
    ids, meta = bytearray(), bytearray()
    for y in range(h):
        for z in range(l):
            for x in range(w):
                edge = x in (0, w - 1) or z in (0, l - 1)
                block, nibble = 0, 0
                if y == 0:
                    block = 5                      # oak planks
                elif y == h - 1:
                    block, nibble = 53, 3          # oak stairs, facing north
                elif edge:
                    window = y == 2 and (x == w // 2 or z == l // 2)
                    block = 20 if window else 4    # glass / cobblestone
                ids.append(block)
                meta.append(nibble)
    body = (t_short("Width", w) + t_short("Height", h) + t_short("Length", l)
            + tag(TAG_STRING, "Materials", _str("Alpha"))
            + t_bytes("Blocks", bytes(ids)) + t_bytes("Data", bytes(meta)))
    return t_compound("", t_compound("Schematic", body))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/schem"
    os.makedirs(out, exist_ok=True)
    w, h, l, palette, pal_body, data = build()
    legacy = os.path.join(out, "hut_legacy.schematic")
    with open(legacy, "wb") as fh:
        fh.write(gzip.compress(mcedit(w, h, l)))
    print("wrote %s (%dx%dx%d)" % (legacy, w, h, l))
    for name, writer in [("hut_v2.schem", sponge_v2), ("hut_v3.schem", sponge_v3)]:
        path = os.path.join(out, name)
        with open(path, "wb") as fh:
            fh.write(gzip.compress(writer(w, h, l, palette, pal_body, data)))
        print("wrote %s (%dx%dx%d)" % (path, w, h, l))


if __name__ == "__main__":
    main()
