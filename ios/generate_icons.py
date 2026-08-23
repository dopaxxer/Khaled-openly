#!/usr/bin/env python3
import os
import struct
import zlib

SIZES = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]
OUT = os.path.join(os.path.dirname(__file__), "Openly", "Assets.xcassets", "AppIcon.appiconset")


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def icon(size):
    blue = (22, 39, 122)
    white = (255, 255, 255)
    cx = cy = (size - 1) / 2
    outer = size * 0.33
    inner = size * 0.22
    rows = []
    for y in range(size):
        row = bytearray([0])
        for x in range(size):
            distance = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            row.extend(white if inner <= distance <= outer else blue)
        rows.append(bytes(row))
    raw = b"".join(rows)
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


os.makedirs(OUT, exist_ok=True)
for value in SIZES:
    with open(os.path.join(OUT, f"icon-{value}.png"), "wb") as handle:
        handle.write(icon(value))

print(f"Generated {len(SIZES)} Openly app icons")

