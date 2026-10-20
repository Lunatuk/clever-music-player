"""Reject a Windows audio DLL built from different plugin sources."""
import argparse
import hashlib
from pathlib import Path
import struct


INPUTS = (
    "CMakeLists.txt",
    "include/just_audio_windows/just_audio_windows_plugin.h",
    "just_audio_windows_plugin.cpp",
    "player.hpp",
    "player_data.hpp",
    "uri_utils.hpp",
)
PREFIX = b"CMP_WINDOWS_AUDIO_SOURCE_SHA256:"


def source_digest(source_root):
    plugin = Path(source_root) / "third_party/just_audio_windows/windows"
    manifest = "".join(
        name + ":" + hashlib.sha256((plugin / name).read_bytes()).hexdigest() + "\n"
        for name in INPUTS
    )
    return hashlib.sha256(manifest.encode("ascii")).hexdigest()


def verify(plugin_path, source_root):
    binary = Path(plugin_path).read_bytes()
    if binary[:2] != b"MZ" or len(binary) < 64:
        raise ValueError("The Windows audio plugin is not a PE binary.")
    offset = struct.unpack_from("<I", binary, 0x3C)[0]
    if (offset + 6 > len(binary) or binary[offset:offset + 4] != b"PE\0\0"
            or struct.unpack_from("<H", binary, offset + 4)[0] != 0x8664):
        raise ValueError("The Windows audio plugin must be x64.")
    digest = source_digest(source_root)
    stamp = PREFIX + digest.encode("ascii") + b"\0"
    if binary.count(PREFIX) != 1 or stamp not in binary:
        raise ValueError("Stale Windows audio DLL: source fingerprint does not match.")
    if b"CmpWindowsAudioBuildStamp\0" not in binary:
        raise ValueError("The Windows audio DLL has no build verification export.")
    return digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin", type=Path)
    parser.add_argument("--source-root", type=Path,
                        default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    try:
        digest = verify(args.plugin, args.source_root)
    except (OSError, ValueError, struct.error) as error:
        raise SystemExit(str(error)) from None
    print("Windows audio DLL matches source SHA-256:", digest)


if __name__ == "__main__":
    main()
