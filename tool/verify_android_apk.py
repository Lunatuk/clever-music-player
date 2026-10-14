"""Check arm64 APK CRC, uncompressed library ZIP alignment and ELF segments.

Usage: python tool/verify_android_apk.py path/to/app-arm64-v8a-release.apk
This is a build check, not a substitute for running on a 16 KB device.
"""
import json
from pathlib import Path
import struct
import sys
import zipfile


def verify(apk):
    libraries = []
    with zipfile.ZipFile(apk) as archive, open(apk, "rb") as raw:
        assert archive.testzip() is None, "APK CRC failure"
        for entry in archive.infolist():
            if not entry.filename.endswith(".so"):
                continue
            assert entry.filename.startswith("lib/arm64-v8a/"), entry.filename
            raw.seek(entry.header_offset)
            header = raw.read(30)
            assert header[:4] == b"PK\x03\x04", "Invalid ZIP header"
            name_size, extra_size = struct.unpack_from("<HH", header, 26)
            data_offset = entry.header_offset + 30 + name_size + extra_size
            if entry.compress_type == zipfile.ZIP_STORED:
                assert data_offset % 16384 == 0, f"ZIP alignment: {entry.filename}"
            elf = archive.read(entry)
            assert elf[:6] == b"\x7fELF\x02\x01", "Expected little-endian ELF64"
            assert struct.unpack_from("<H", elf, 18)[0] == 183, "Expected AArch64"
            phoff = struct.unpack_from("<Q", elf, 32)[0]
            phentsize, phnum = struct.unpack_from("<HH", elf, 54)
            loads = []
            load_ranges = []
            relro = []
            for index in range(phnum):
                kind, flags, offset, virtual, physical, file_size, memory_size, alignment = struct.unpack_from(
                    "<IIQQQQQQ", elf, phoff + index * phentsize)
                if kind == 1:  # PT_LOAD
                    assert alignment >= 16384, f"ELF alignment: {entry.filename}"
                    assert (virtual - offset) % 16384 == 0, "ELF load offset"
                    loads.append(alignment)
                    load_ranges.append((virtual, virtual + memory_size, flags))
                if kind == 0x6474E552:  # PT_GNU_RELRO
                    relro.append(virtual + memory_size)
            assert loads, f"No load segments: {entry.filename}"
            for end in relro:
                # Bionic also accepts RELRO covering the entire LOAD (or suffix).
                # Its end need not be page aligned if rounding cannot protect
                # any following writable data. See phdr_table_get_relro_min_align:
                # android.googlesource.com/platform/bionic/+/android16-qpr2-release/
                # linker/linker_phdr_16kib_compat.cpp
                if end % 16384:
                    assert any(stop == end for _, stop, _ in load_ranges), f"RELRO: {entry.filename}"
                    rounded_end = (end + 16383) & ~16383
                    assert not any(flags & 2 and stop > end and start < rounded_end
                                   for start, stop, flags in load_ranges), f"RELRO overlap: {entry.filename}"
            libraries.append({"name": entry.filename, "zip_offset": data_offset,
                              "load_alignments": loads, "relro_ends": relro})
    assert any(item["name"].endswith("/libflutter.so") for item in libraries), "Missing engine"
    assert any(item["name"].endswith("/libapp.so") for item in libraries), "Missing AOT app"
    return {"apk": Path(apk).name, "libraries": libraries, "result": "passed"}


if __name__ == "__main__":
    print(json.dumps(verify(sys.argv[1]), indent=2))
