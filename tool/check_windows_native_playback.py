"""Exercise the real WinRT AudioPlayer against disposable fixture copies."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, required=True)
    parser.add_argument("--release-directory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    executable = args.executable.resolve(strict=True)
    release = args.release_directory.resolve(strict=True)
    assert (release / "flutter_windows.dll").is_file()
    env = os.environ.copy()
    env["PATH"] = str(release) + os.pathsep + env["PATH"]
    fixtures = Path(__file__).resolve().parent.parent / "test/fixtures/media_helper"
    groups = [
        ("ascii", "ascii", "tone"),
        ("spaces", "space folder", "tone file"),
        ("cyrillic", "Музыка тест", "трек"),
        ("emoji", "Music 🎵", "tone 🎧"),
        ("reserved", "Музыка # 100%", "трек # 100%"),
        ("escape_literal", "%D0%90 %20", "tone %D0%90 %23"),
        ("cjk", "音楽", "曲"),
        ("combining", "cafe\u0301", "tone"),
    ]
    records = []

    def probe(label, file, invalid=False):
        result = subprocess.run(
            [str(executable), "invalid" if invalid else "valid", file.as_uri()],
            capture_output=True, env=env, timeout=15,
        )
        records.append({
            "group": label, "format": file.suffix[1:], "exit": result.returncode,
            "output": result.stdout.decode("utf8", errors="replace").strip(),
        })
        print(label, file.suffix, "exit", result.returncode, flush=True)

    # TemporaryDirectory owns this fresh directory and removes only its contents.
    with tempfile.TemporaryDirectory(prefix="cmp_native_playback_") as directory:
        temporary = Path(directory)
        for label, folder, stem in groups:
            target = temporary / folder
            target.mkdir()
            for extension in ("mp3", "m4a", "flac"):
                file = target / (stem + "." + extension)
                shutil.copyfile(fixtures / ("tone." + extension), file)
                probe(label, file)
        for label, folder in (("invalid_ascii", "bad"),
                              ("invalid_cyrillic", "Неправильный")):
            file = temporary / folder / "broken.mp3"
            file.parent.mkdir()
            file.write_bytes(b"not an audio file")
            probe(label, file, invalid=True)

    args.output.write_text(json.dumps(records, indent=2), encoding="utf8")
    if any(item["exit"] != 0 for item in records):
        raise SystemExit("Native playback matrix failed; see numeric results.")
    print("PASS actual WinRT playback matrix:", len(records), flush=True)


if __name__ == "__main__":
    main()
