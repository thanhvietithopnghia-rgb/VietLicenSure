"""Build-only raw Deflate encoder. Python 3 + stdlib; not shipped in the EXE."""
import hashlib
import json
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
import zipfile

source, destination = map(pathlib.Path, sys.argv[1:])
data = source.read_bytes()
if not 0 < len(data) <= 32 * 1024 * 1024:
    raise ValueError("Payload bundle outside the existing decoded size limit")
seven_zip = shutil.which("7z.exe") or shutil.which("7z")
encoder_name = "Python stdlib zlib raw Deflate level9 memLevel9"
if seven_zip:
    with tempfile.TemporaryDirectory(prefix="vls-deflate-") as temporary:
        archive = pathlib.Path(temporary) / "payload.zip"
        subprocess.run([
            seven_zip, "a", "-tzip", str(archive), str(source),
            "-mx=9", "-mm=Deflate", "-mfb=258", "-mpass=15",
        ], check=True, stdout=subprocess.DEVNULL)
        archive_bytes = archive.read_bytes()
        with zipfile.ZipFile(archive) as package:
            entries = package.infolist()
            if len(entries) != 1 or entries[0].compress_type != zipfile.ZIP_DEFLATED:
                raise ValueError("7-Zip did not produce one Deflate entry")
            entry = entries[0]
        name_length, extra_length = struct.unpack_from("<HH", archive_bytes, entry.header_offset + 26)
        start = entry.header_offset + 30 + name_length + extra_length
        encoded = archive_bytes[start:start + entry.compress_size]
    encoder_name = "7-Zip raw Deflate max/15-pass"
else:
    encoder = zlib.compressobj(9, zlib.DEFLATED, -15, 9)
    encoded = encoder.compress(data) + encoder.flush()
decoder = zlib.decompressobj(-15)
decoded = decoder.decompress(encoded, len(data) + 1)
if decoded != data or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:
    raise ValueError("Payload compression round-trip mismatch")
with destination.open("xb") as stream:
    stream.write(encoded)
print(json.dumps({
    "encoder": encoder_name,
    "python": sys.version.split()[0],
    "zlib": zlib.ZLIB_RUNTIME_VERSION,
    "decodedBytes": len(data),
    "encodedBytes": len(encoded),
    "decodedSha256": hashlib.sha256(data).hexdigest(),
    "roundtrip": True,
}))
