#!/usr/bin/env python3
"""Independent parser: checks the actual C++ writer output, not a reimplementation."""
import pathlib
import plistlib
import struct
import sys

root = pathlib.Path(sys.argv[1])
repository = pathlib.Path(__file__).resolve().parents[1]
info = plistlib.loads((repository / "LiDARScanner" / "Info.plist").read_bytes())
app_build = info["CFBundleVersion"]
raw = (root / "test.ply").read_bytes()
header, body = raw.split(b"end_header\n", 1)
assert b"format binary_little_endian 1.0" in header
assert f"comment LiDAR-Scanner Build {app_build}; units metres; local right-handed Z-up".encode() in header
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

# Check ASPRS LAS 1.2 binary export
las_bytes = (root / "test.las").read_bytes()
assert las_bytes[:4] == b"LASF", "Invalid LAS signature"
assert las_bytes[24:26] == bytes([1, 2]), "Expected LAS version 1.2"
header_size, offset_to_points = struct.unpack_from("<HI", las_bytes, 94)
assert header_size == 227
assert offset_to_points == 227
format_id, record_len, num_points = struct.unpack_from("<BHI", las_bytes, 104)
assert format_id == 2
assert record_len == 26
assert num_points == 8
assert len(las_bytes) == 227 + 8 * 26, "Unexpected LAS file size"
scale_x, scale_y, scale_z, off_x, off_y, off_z = struct.unpack_from("<dddddd", las_bytes, 131)
assert scale_x == 0.001 and scale_y == 0.001 and scale_z == 0.001
first_pt = las_bytes[227:253]
p_x, p_y, p_z, intensity, ret_byte, cls, scan_angle, user_data, pt_source, r16, g16, b16 = struct.unpack("<iiiHBBbBH HHH", first_pt)
assert round(p_x * scale_x + off_x, 3) == records[0][0]
assert round(p_y * scale_y + off_y, 3) == records[0][1]
assert round(p_z * scale_z + off_z, 3) == records[0][2]
assert r16 == records[0][3] * 257
assert g16 == records[0][4] * 257
assert b16 == records[0][5] * 257
assert user_data == records[0][6]

assert not list(root.glob("*.partial"))
print("PASS: independent binary PLY, ASCII PLY, XYZ and ASPRS LAS 1.2 parsing; Z-up, RGB, confidence, point count, endian and record sizes")

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
