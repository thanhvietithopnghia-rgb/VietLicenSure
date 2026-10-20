"""Build-only raw Deflate encoder. Python 3 + stdlib; not shipped in the EXE."""
import hashlib
import json
import pathlib
import sys
import zlib

source, destination = map(pathlib.Path, sys.argv[1:])
data = source.read_bytes()
if not 0 < len(data) <= 32 * 1024 * 1024:
    raise ValueError("Payload bundle outside the existing decoded size limit")
encoder = zlib.compressobj(9, zlib.DEFLATED, -15, 9)
encoded = encoder.compress(data) + encoder.flush()
decoder = zlib.decompressobj(-15)
decoded = decoder.decompress(encoded, len(data) + 1)
if decoded != data or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
    raise ValueError("Payload compression round-trip mismatch")
with destination.open("xb") as stream:
    stream.write(encoded)
print(json.dumps({
    "encoder": "Python stdlib zlib raw Deflate level9 memLevel9",
    "python": sys.version.split()[0],
    "zlib": zlib.ZLIB_RUNTIME_VERSION,
    "decodedBytes": len(data),
    "encodedBytes": len(encoded),
    "decodedSha256": hashlib.sha256(data).hexdigest(),
    "roundtrip": True,
}))
