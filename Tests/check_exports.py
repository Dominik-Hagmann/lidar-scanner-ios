#!/usr/bin/env python3
"""Independent parser: checks the actual C++ writer output, not a reimplementation."""
import pathlib
import struct
import sys

root = pathlib.Path(sys.argv[1])
raw = (root / "test.ply").read_bytes()
header, body = raw.split(b"end_header\n", 1)
assert b"format binary_little_endian 1.0" in header
assert b"element vertex 8\n" in header
assert b"property uchar confidence" in header
assert len(body) == 8 * 16, (len(body), "Unexpected padding/record size")
records = list(struct.iter_unpack("<fffBBBB", body))
assert records[0] == (-1.0, 2.0, 0.5, 128, 128, 128, 2)
assert records[7] == (2.0, 2.0, -0.5, 128, 128, 128, 2)
text = (root / "test-ascii.ply").read_text().split("end_header\n")[1].splitlines()
assert len(text) == 8
for binary, line in zip(records, text):
    assert tuple(map(float, line.split())) == binary
xyz = (root / "test.xyz").read_text().splitlines()
assert len(xyz) == 8
for record, line in zip(records, xyz):
    assert len(line.split()) == 3
    assert tuple(map(float, line.split())) == record[:3]
assert not list(root.glob("*.partial"))
print("PASS: independent binary PLY, ASCII PLY and XYZ parsing; Z-up, RGB, confidence, point count, endian and record sizes")

# Inspect the actual large exports without loading their bodies into RAM.
for filename, count, last in [
    ("large-auto.ply", 2_097_152, (1.984375, -1.9375, -0.984375)),
    ("large-capped.ply", 2_000_009, (0.125, -1.8125, 0.9375)),
]:
    path = root / filename
    with path.open("rb") as file:
        lines = []
        while True:
            line = file.readline()
            assert line, "Incomplete PLY header"
            lines.append(line)
            if line == b"end_header\n":
                break
        assert f"element vertex {count}\n".encode() in lines
        offset = file.tell()
        assert path.stat().st_size == offset + count * 16
        assert struct.unpack("<fffBBBB", file.read(16)) == (-2, 2, 1, 128, 128, 128, 2)
        file.seek(offset + (count - 1) * 16)
        assert struct.unpack("<fffBBBB", file.read(16)) == (*last, 128, 128, 128, 2)
print("PASS: large exports, including exact full record count and first/last points")
