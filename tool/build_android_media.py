"""Build pinned, minimal LGPL FFmpeg shared libraries for Android ARM64/API24.

Requires NDK r28c, Python 3.11+, GNU Make and a POSIX shell. Windows additionally
uses Git Bash and a complete MSVC SDK for host build tools, not Android code.
No library/source is downloaded at application runtime. Existing outputs are
never replaced. The source kit includes exact upstream source and build inputs.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import urllib.request
import zipfile

from build_media_helper import SOURCES, visual_studio_environment

LIBRARIES = ['avformat', 'avcodec', 'avutil', 'swresample']
FLAGS = [
    '--target-os=android', '--arch=aarch64', '--cpu=armv8-a',
    '--enable-cross-compile', '--cc=clang', '--cxx=clang++', '--ar=llvm-ar',
    '--ranlib=llvm-ranlib', '--nm=llvm-nm', '--strip=llvm-strip',
    '--extra-cflags=--target=aarch64-linux-android24',
    '--extra-ldflags=--target=aarch64-linux-android24 -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384',
    '--enable-shared', '--disable-static', '--disable-autodetect',
    '--disable-everything', '--disable-network', '--disable-doc',
    '--disable-debug', '--disable-avdevice', '--disable-postproc',
    '--disable-avfilter', '--disable-swscale', '--disable-asm',
    '--enable-small', '--enable-pthreads', '--enable-zlib', '--disable-programs',
    '--enable-demuxer=mp3,mov,flac', '--enable-muxer=mp3,ipod,flac',
    '--enable-decoder=mp3float,aac,flac,png,mjpeg',
    '--enable-parser=mpegaudio,aac,flac,png,mjpeg',
]
NOTICE = """Clever Music Player Android media backend, profile cmp-android-audio-1.
FFmpeg 7.1.5: LGPL version 2.1 or later. Copyright the FFmpeg developers.
No GPL, version3 or nonfree options. Dynamically linked, not a playback engine.
Android's system zlib is used; it is not redistributed in this bundle.
Exact corresponding source, release signature/key, generated configuration,
recipes and wrapper source are in source-kit.zip, also included inside the APK.
The app can export this kit from its licenses page. No network is required.
Libraries can be rebuilt, replaced in the APK, aligned and signed with your own
key (the original signing key is not needed). See README in the source kit.
Upstream: https://ffmpeg.org/   License: https://ffmpeg.org/legal.html
Player source: https://github.com/Lunatuk/clever-music-player
"""


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def source_files(cache):
    cache.mkdir(parents=True, exist_ok=True)
    selected = {name: spec for name, spec in SOURCES.items()
                if name.startswith('ffmpeg')}
    for name, (url, expected) in selected.items():
        file = cache / name
        if not file.exists():
            temporary = file.with_suffix(file.suffix + '.pending')
            with urllib.request.urlopen(url, timeout=60) as inp, temporary.open('xb') as out:
                shutil.copyfileobj(inp, out)
            temporary.rename(file)
        if sha(file) != expected:
            raise RuntimeError('Source hash mismatch: ' + name)
    return selected


def run(name, command, directory, environment, logs):
    with (logs / (name + '.log')).open('wb') as log:
        result = subprocess.run(command, cwd=directory, env=environment,
                                stdout=log, stderr=subprocess.STDOUT)
    print(name, 'exit', result.returncode, flush=True)
    if result.returncode:
        raise RuntimeError('Build failed: ' + str(logs / (name + '.log')))


def assemble(ffmpeg, cache, output, tools, flags, root):
    """Collect a completed build; keep paths out of distributed build records."""
    source_files(cache)
    config = (ffmpeg / 'config.h').read_text()
    for name in ['CONFIG_GPL', 'CONFIG_VERSION3', 'CONFIG_NONFREE', 'CONFIG_NETWORK']:
        if '#define ' + name + ' 0' not in config:
            raise RuntimeError('Unexpected FFmpeg profile: ' + name)
    output.mkdir(parents=True, exist_ok=False)
    libs = output / 'arm64-v8a'
    libs.mkdir()
    for name in LIBRARIES:
        candidates = [p for p in (ffmpeg / ('lib' + name)).glob('lib' + name + '.so.*') if p.is_file()]
        # Android's SONAME is lib<name>.so; build products retain a major suffix.
        candidates.sort(key=lambda p: len(p.name))
        if not candidates:
            raise RuntimeError('Missing shared library: ' + name)
        target = libs / ('lib' + name + '.so')
        shutil.copyfile(candidates[0], target)
        subprocess.run([str(tools / ('llvm-strip.exe' if os.name == 'nt' else 'llvm-strip')),
                        '--strip-unneeded', str(target)], check=True)
        readelf = tools / ('llvm-readelf.exe' if os.name == 'nt' else 'llvm-readelf')
        info = subprocess.check_output([str(readelf), '-d', '-lW', str(target)]).decode()
        if 'Library soname: [lib' + name + '.so]' not in info:
            raise RuntimeError('Unexpected SONAME: ' + name)
        for line in info.splitlines():
            if line.strip().startswith('LOAD') and int(line.split()[-1], 16) < 16384:
                raise RuntimeError('Library is not aligned for 16 KiB pages')
    # Only public headers listed by FFmpeg's Makefiles (not private config.h).
    import re
    for name in LIBRARIES:
        directory = ffmpeg / ('lib' + name)
        make = (directory / 'Makefile').read_text()
        match = re.search(r'^HEADERS\s*[:+]?=\s*(.*?)(?=\n\s*\n|\n[A-Z_]+\s*[:+]?=)', make, re.M | re.S)
        if not match:
            raise RuntimeError('Cannot determine public headers: ' + name)
        headers = re.findall(r'[a-zA-Z0-9_]+\.h', match.group(1))
        if name == 'avutil':
            headers += ['avconfig.h', 'ffversion.h']
        for header in sorted(set(headers)):
            destination = output / 'include' / directory.name / header
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(directory / header, destination)
    for source, destination in [('COPYING.LGPLv2.1', 'COPYING.LGPLv2.1'), ('LICENSE.md', 'FFmpeg-LICENSE.md')]:
        shutil.copyfile(ffmpeg / source, output / destination)
    (output / 'NOTICE.txt').write_text(NOTICE, encoding='utf8')
    files = {p.relative_to(output).as_posix(): {'bytes': p.stat().st_size, 'sha256': sha(p)}
             for p in output.rglob('*') if p.is_file()}
    manifest = {'schema': 1, 'profile': 'cmp-android-audio-1', 'version': '7.1.5',
                'target': 'android-arm64', 'api': 24, 'pageBytes': 16384,
                'ndk': '28.2.13676358', 'configure': flags, 'files': files}
    kit = output / 'source-kit.zip'
    with zipfile.ZipFile(kit, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
        for name in source_files(cache):
            archive.write(cache / name, name)
        for name in ['config.h', 'config_components.h', 'libavutil/avconfig.h', 'libavutil/ffversion.h']:
            archive.write(ffmpeg / name, 'generated/' + name)
        archive.writestr('BUILD_INFO.json', json.dumps(manifest, indent=2))
        archive.writestr('NOTICE.txt', NOTICE)
        archive.write(output / 'COPYING.LGPLv2.1', 'COPYING.LGPLv2.1')
        archive.writestr('README.txt', 'Rebuild with NDK r28c and Python 3.11+:\n'
                          'python tool/build_android_media.py --ndk <NDK> --work-dir <new-ASCII-directory> '
                          '--output third_party/cmp_android_media/vendor --source-cache .\n'
                          'Windows: provide --make <GNU-Make> and --bash <Git-Bash>; a full MSVC SDK is needed.\n'
                          'Build tool changes are generated configuration only; upstream FFmpeg source is unchanged.\n'
                          'Replace the APK lib/arm64-v8a/libav*.so and libswresample.so with rebuilt libraries,\n'
                          'zipalign -P 16, then apksigner sign with your own key.\n'
                          'To rebuild the JNI wrapper, use the included CMake project with Android NDK.\n')
        for name in ['tool/build_android_media.py', 'tool/build_media_helper.py',
                     'third_party/cmp_android_media/CMakeLists.txt',
                     'third_party/cmp_android_media/src/cmp_media.c',
                     'third_party/cmp_android_media/src/cmp_media.h',
                     'third_party/cmp_android_media/src/cmp_media_jni.c']:
            archive.write(root / name, name)
    manifest['files']['source-kit.zip'] = {'bytes': kit.stat().st_size, 'sha256': sha(kit)}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf8')
    print('Assembled', len(files), 'files, source kit', kit.stat().st_size, 'bytes', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ndk', required=True, type=Path)
    parser.add_argument('--work-dir', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--source-cache', required=True, type=Path)
    parser.add_argument('--make', type=Path)
    parser.add_argument('--bash', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    work = args.work_dir.resolve()
    if work.exists() or args.output.exists() or not str(work).isascii() or any(c in str(work) for c in ' &%"'):
        parser.error('Use new output and ASCII build directories without shell metacharacters/spaces.')
    revision = dict(tuple(item.strip() for item in line.split('=', 1)) for line in (args.ndk / 'source.properties').read_text().splitlines() if '=' in line)
    if revision.get('Pkg.Revision') != '28.2.13676358':
        parser.error('The qualified NDK is 28.2.13676358.')
    system = 'windows-x86_64' if os.name == 'nt' else 'darwin-x86_64' if platform.system() == 'Darwin' else 'linux-x86_64'
    tools = args.ndk.resolve() / 'toolchains/llvm/prebuilt' / system / 'bin'
    source_files(args.source_cache)
    work.mkdir(parents=True)
    with tarfile.open(args.source_cache / 'ffmpeg-7.1.5.tar.xz') as archive:
        archive.extractall(work, filter='data')
    ffmpeg = work / 'ffmpeg-7.1.5'
    flags = FLAGS.copy()
    make = args.make or shutil.which('make')
    if make is None:
        parser.error('GNU Make is required (--make).')
    env = os.environ.copy()
    shell = str(args.bash) if args.bash else 'sh'
    if os.name == 'nt':
        env = visual_studio_environment(work, None)
        env.pop('CPATH', None)
        env.pop('LIBRARY_PATH', None)
        env.pop('MSYS_NO_PATHCONV', None)
        shell = str(args.bash or Path(os.environ['ProgramFiles']) / 'Git/bin/bash.exe')
        git_usr = Path(shell).parent.parent / 'usr/bin'
        env['PATH'] += os.pathsep + str(git_usr)
        flags = [s + '.exe' if s.startswith(('--cc=', '--cxx=', '--ar=', '--ranlib=', '--nm=', '--strip=')) else s for s in flags]
        flags += ['--host-cc=./cmp-host-cc']
        (ffmpeg / 'cmp-host-cc').write_text('#!/bin/sh\nexport CPATH="$INCLUDE"\nexec clang.exe --target=x86_64-pc-windows-msvc "$@"\n', encoding='utf8')
    env['PATH'] = str(tools) + os.pathsep + env['PATH']
    (work / 'tmp').mkdir()
    env['TMPDIR'] = (work / 'tmp').as_posix()
    run('configure', [shell, './configure', *flags], ffmpeg, env, work)
    run('make', [str(make), '-j4', 'SHELL=' + shell.replace('\\', '/'),
                 'CCDEP=true', 'CXXDEP=true', 'ASDEP=true'], ffmpeg, env, work)
    assemble(ffmpeg, args.source_cache, args.output, tools, flags, root)


if __name__ == '__main__':
    main()
