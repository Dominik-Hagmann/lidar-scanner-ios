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

csv_lines = (root / "test.csv").read_text().splitlines()
assert csv_lines[0] == "x,y,z,red,green,blue,confidence"
assert len(csv_lines) == 9
for record, line in zip(records, csv_lines[1:]):
    parts = line.split(",")
    assert len(parts) == 7
    assert tuple(map(float, parts)) == record

las = (root / "test.las").read_bytes()
assert las[:4] == b"LASF"
assert las[24:26] == bytes([1, 2])
assert struct.unpack_from("<H", las, 94)[0] == 227
assert struct.unpack_from("<I", las, 96)[0] == 227
assert las[104] == 2 and struct.unpack_from("<H", las, 105)[0] == 26
assert struct.unpack_from("<I", las, 107)[0] == 8
assert len(las) == 227 + 8 * 26
scales = struct.unpack_from("<3d", las, 131)
offsets = struct.unpack_from("<3d", las, 155)
for idx, record in enumerate(records):
    px, py, pz, inten, flags, cls, ang, udata, psid, r16, g16, b16 = struct.unpack_from("<iiiHBBbBH3H", las, 227 + idx * 26)
    x = px * scales[0] + offsets[0]
    y = py * scales[1] + offsets[1]
    z = pz * scales[2] + offsets[2]
    assert abs(x - record[0]) < 1e-3 and abs(y - record[1]) < 1e-3 and abs(z - record[2]) < 1e-3
    assert (r16 // 257, g16 // 257, b16 // 257, udata) == record[3:]

laz = (root / "test.laz").read_bytes()
assert laz[:4] == b"LASF"
assert struct.unpack_from("<I", laz, 96)[0] == 327
assert laz[104] == (2 | 0x80)
assert laz[227 + 2 : 227 + 16] == b"laszip encoded"
ct_off = struct.unpack_from("<q", laz, 327)[0]
assert 327 + 8 < ct_off < len(laz)

e57 = (root / "test.e57").read_bytes()
assert e57[:8] == b"ASTM-E57"
file_len, xml_off, xml_len, page_size = struct.unpack_from("<QQQQ", e57, 16)
assert page_size == 1024 and len(e57) == file_len and len(e57) % 1024 == 0
assert 48 < xml_off < file_len and xml_len > 100

assert not list(root.glob("*.partial"))
print("PASS: independent binary/ASCII PLY, XYZ, CSV, LAS, LAZ and ASTM E57 parsing")

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
