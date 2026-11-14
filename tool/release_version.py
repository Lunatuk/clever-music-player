"""Read/bump the pubspec version and verify native release metadata (stdlib only)."""

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
VERSION_LINE = re.compile(r"^version:[ \t]*([^\s#]+)", re.MULTILINE)
NUMBER = r"(0|[1-9][0-9]*)"
VERSION = re.compile(rf"{NUMBER}\.{NUMBER}\.{NUMBER}(?:\+{NUMBER})?")


@dataclass(frozen=True)
class AppVersion:
    major: int
    minor: int
    patch: int
    build: int

    @classmethod
    def parse(cls, value, *, legacy=False):
        match = VERSION.fullmatch(value)
        if not match or (match[4] is None and not legacy):
            raise ValueError("Ожидается версия MAJOR.MINOR.PATCH+BUILD")
        parts = [int(match[i] or 0) for i in range(1, 5)]
        if any(part > 65535 for part in parts) or (not legacy and parts[3] < 1):
            raise ValueError("Компоненты версии должны помещаться в 16 бит; BUILD > 0")
        return cls(*parts)

    @property
    def name(self):
        return f"{self.major}.{self.minor}.{self.patch}"

    @property
    def parts(self):
        return self.major, self.minor, self.patch, self.build

    def __str__(self):
        return f"{self.name}+{self.build}"

    def bump(self, part):
        major, minor, patch, build = self.parts
        if part == "major":
            major, minor, patch = major + 1, 0, 0
        elif part == "minor":
            minor, patch = minor + 1, 0
        elif part == "patch":
            patch += 1
        else:
            raise ValueError(f"Неизвестный компонент: {part}")
        return AppVersion.parse(f"{major}.{minor}.{patch}+{build + 1}")

    def require_newer_than(self, previous):
        if self.parts[:3] <= previous.parts[:3] or self.build <= previous.build:
            raise ValueError("Для выпуска должны вырасти и версия, и BUILD")


def read_version(text, *, legacy=False):
    matches = list(VERSION_LINE.finditer(text))
    if len(matches) != 1:
        raise ValueError("В pubspec должна быть ровно одна строка version")
    return AppVersion.parse(matches[0][1], legacy=legacy)


def bump_file(path, part):
    with path.open(encoding="utf-8", newline="") as source:
        text = source.read()
    version = read_version(text).bump(part)
    match = VERSION_LINE.search(text)
    updated = text[:match.start(1)] + str(version) + text[match.end(1):]
    with path.open("w", encoding="utf-8", newline="") as target:
        target.write(updated)
    return version


def output(command, **kwargs):
    return subprocess.check_output(command, encoding="utf-8", **kwargs)


def verify_windows(version, executable):
    env = dict(os.environ, CMP_VERSION_EXECUTABLE=str(executable.resolve()))
    script = (
        "$ErrorActionPreference='Stop'; "
        "$v=(Get-Item -LiteralPath $env:CMP_VERSION_EXECUTABLE).VersionInfo; "
        "@{file=@($v.FileMajorPart,$v.FileMinorPart,$v.FileBuildPart,$v.FilePrivatePart);"
        "product=@($v.ProductMajorPart,$v.ProductMinorPart,$v.ProductBuildPart,$v.ProductPrivatePart);"
        "fileString=$v.FileVersion;productString=$v.ProductVersion} | ConvertTo-Json -Compress"
    )
    data = json.loads(output(["powershell.exe", "-NoProfile", "-NonInteractive",
                              "-Command", script], env=env))
    if (tuple(data["file"]) != version.parts
            or tuple(data["product"]) != version.parts
            or data["fileString"] != str(version)
            or data["productString"] != str(version)):
        raise ValueError(f"Версия EXE расходится с pubspec: {data}")
    return data


def find_aapt():
    executable = "aapt.exe" if os.name == "nt" else "aapt"
    found = shutil.which(executable)
    if found:
        return found
    for key in ("ANDROID_SDK_ROOT", "ANDROID_HOME"):
        sdk = os.environ.get(key)
        if not sdk:
            continue
        candidates = list((Path(sdk) / "build-tools").glob(f"*/{executable}"))
        candidates.sort(key=lambda p: tuple(int(n) for n in re.findall(r"\d+", p.parent.name)), reverse=True)
        if candidates:
            return str(candidates[0])
    raise ValueError("Не найден aapt: задай --aapt или ANDROID_SDK_ROOT")


def verify_android(version, apk, aapt=None):
    badging = output([aapt or find_aapt(), "dump", "badging", str(apk)])
    package = re.search(r"^package: (.*)$", badging, re.MULTILINE)
    if package is None:
        raise ValueError("aapt не вернул метаданные пакета")
    fields = dict(re.findall(r"(\w+)='([^']*)'", package[1]))
    if (fields.get("versionName") != version.name
            or fields.get("versionCode") != str(version.build)):
        raise ValueError(f"Версия APK расходится с pubspec: {fields}")
    return fields


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pubspec", type=Path, default=ROOT / "pubspec.yaml")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("show")
    check = commands.add_parser("check")
    check.add_argument("--base-ref", help="Git ref предыдущего выпуска")
    bump = commands.add_parser("bump")
    bump.add_argument("part", choices=("major", "minor", "patch"))
    windows = commands.add_parser("verify-windows")
    windows.add_argument("executable", type=Path)
    android = commands.add_parser("verify-android")
    android.add_argument("apk", type=Path)
    android.add_argument("--aapt")
    args = parser.parse_args()
    try:
        version = read_version(args.pubspec.read_text(encoding="utf-8"))
        if args.command == "bump":
            version = bump_file(args.pubspec, args.part)
        elif args.command == "check" and args.base_ref:
            old = output(["git", "show", f"{args.base_ref}:pubspec.yaml"], cwd=ROOT)
            version.require_newer_than(read_version(old, legacy=True))
        elif args.command == "verify-windows":
            print(json.dumps(verify_windows(version, args.executable)))
        elif args.command == "verify-android":
            print(json.dumps(verify_android(version, args.apk, args.aapt)))
        print(version)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Ошибка проверки версии: {error}\n")


if __name__ == "__main__":
    main()
