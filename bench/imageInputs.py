import hashlib
from pathlib import Path
import struct
import sys
import zlib


def chunk(kind, data):
    return (struct.pack(">I", len(data)) + kind + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff))


output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
for size in (64, 512, 2048, 4096):
    row = bytes((i * 13 + (i // 4) * 7) & 255 for i in range(size * 4))
    raw = (b"\0" + row) * size
    data = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 1))
            + chunk(b"IEND", b""))
    path = output / f"{size}.png"
    path.write_bytes(data)
    print("image-input", size, len(data), hashlib.sha256(data).hexdigest(), path)
