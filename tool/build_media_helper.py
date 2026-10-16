"""Build the Windows x64 offline media helper; no global installation.

Requires Python 3.11+, Git Bash and a complete MSVC C11 toolchain (VS 2019
16.8+). FFmpeg/zlib sources are unmodified. GNU Make is a build tool, never distributed
with the player. Exact corresponding sources and recipes travel in the bundle.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import time
import urllib.request


SOURCES = {
    'ffmpeg-7.1.5.tar.xz': ('https://ffmpeg.org/releases/ffmpeg-7.1.5.tar.xz',
                         'de668509caf9e35e3cd162473441fdb29538c6d96ed080292b3cf9e6fc5d558f'),
    'ffmpeg-7.1.5.tar.xz.asc': ('https://ffmpeg.org/releases/ffmpeg-7.1.5.tar.xz.asc',
                             '7ce4b9d56e3ef0cd4c3a9c0b2c8a034ac91e6c4c011c1f10b05a8aa7292fca35'),
    'ffmpeg-devel.asc': ('https://ffmpeg.org/ffmpeg-devel.asc',
                        '397b3becedcd5a98769967ff1ff8501ddc89f8368b8f766e4701377d7dbaabe5'),
    'zlib-1.3.2.tar.xz': ('https://zlib.net/zlib-1.3.2.tar.xz',
                       'd7a0654783a4da529d1bb793b7ad9c3318020af77667bcae35f95d0e42a792f3'),
    'make-4.4.1.tar.gz': ('https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz',
                        'dd16fb1d67bfab79a72f5e8390735c49e3e8e70b4945a15ab1f81ddb78658fb3'),
}
FLAGS = [
    '--toolchain=msvc', '--arch=x86_64', '--target-os=win32',
    '--enable-shared', '--disable-static', '--disable-autodetect',
    '--disable-everything', '--disable-network', '--disable-doc',
    '--disable-debug', '--disable-avdevice', '--disable-postproc',
    '--disable-x86asm', '--enable-w32threads', '--enable-zlib',
    '--enable-ffmpeg', '--enable-ffprobe', '--disable-ffplay',
    '--enable-protocol=file,pipe',
    '--enable-demuxer=mp3,mov,flac,image_png_pipe,image_jpeg_pipe',
    '--enable-muxer=mp3,ipod,flac,null,hash',
    '--enable-decoder=mp3float,aac,flac,png,mjpeg',
    '--enable-encoder=pcm_s16le,pcm_s32le,wrapped_avframe',
    '--enable-parser=mpegaudio,aac,flac,png,mjpeg',
    '--enable-filter=asetpts,anull,aformat,aresample,null,format,scale',
]
BINARIES = ['ffmpeg.exe', 'ffprobe.exe', 'avcodec-61.dll', 'avfilter-10.dll',
            'avformat-61.dll', 'avutil-59.dll', 'swresample-5.dll', 'swscale-8.dll']


def digest(file):
    with file.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def fetch_sources(destination):
    destination.mkdir(parents=True, exist_ok=True)
    for name, (url, expected) in SOURCES.items():
        file = destination / name
        if not file.exists():
            # No partially downloaded file can be mistaken for a pinned source.
            with urllib.request.urlopen(url, timeout=60) as response:
                with file.with_suffix(file.suffix + '.pending').open('xb') as out:
                    shutil.copyfileobj(response, out)
            file.with_suffix(file.suffix + '.pending').rename(file)
        if digest(file) != expected:
            raise RuntimeError('Source SHA-256 mismatch: ' + name)


def extract(source, destination):
    # Python's data filter rejects traversal, special files and escaping links.
    with tarfile.open(source) as archive:
        archive.extractall(destination, filter='data')


def visual_studio_environment(work, vcvars):
    if vcvars is None:
        vswhere = Path(os.environ['ProgramFiles(x86)']) / 'Microsoft Visual Studio/Installer/vswhere.exe'
        installations = json.loads(subprocess.check_output([
            str(vswhere), '-products', '*', '-requires',
            'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-format', 'json', '-utf8']))
        for installation in installations:
            candidate = Path(installation['installationPath']) / 'VC/Auxiliary/Build/vcvarsall.bat'
            if candidate.is_file():
                vcvars = candidate
                break
    if vcvars is None or not vcvars.is_file():
        raise RuntimeError('A complete MSVC C11 installation is required (--vcvars).')
    # Avoid quoting a batch fragment through list2cmdline / cmd /c twice.
    if any(char in str(vcvars) for char in '"%\r\n'):
        raise ValueError('Unsupported compiler setup path.')
    batch = work / 'compiler-environment.cmd'
    batch.write_text('@echo off\ncall "' + str(vcvars) + '" x64 >nul\n'
                     'if errorlevel 1 exit /b 1\nset\n', encoding='utf8')
    output = subprocess.check_output(['cmd', '/d', '/c', str(batch)])
    env = {key.upper(): value for key, value in os.environ.items()}
    for line in output.decode(errors='replace').splitlines():
        if '=' in line and not line.startswith('='):
            key, value = line.split('=', 1)
            env[key.upper()] = value
    return env


def run(name, command, cwd, env, logs):
    started = time.monotonic()
    with (logs / (name + '.log')).open('wb') as log:
        result = subprocess.run(command, cwd=cwd, env=env,
                                stdout=log, stderr=subprocess.STDOUT)
    print(name, 'exit', result.returncode,
          'seconds', round(time.monotonic() - started, 1), flush=True)
    if result.returncode:
        raise RuntimeError('Build failed; see ' + str(logs / (name + '.log')))


def assemble(source_dir, downloads, output, build_info):
    output.mkdir(parents=True)  # Refuse to replace an existing bundle.
    for name in BINARIES:
        matches = list(source_dir.rglob(name))
        if len(matches) != 1:
            raise RuntimeError('Expected exactly one output: ' + name)
        shutil.copy2(matches[0], output / name)
    sources = output / 'sources'
    sources.mkdir()
    for name in SOURCES:
        shutil.copy2(downloads / name, sources / name)
    shutil.copy2(__file__, sources / 'build_media_helper.py')
    (sources / 'build-info.json').write_text(json.dumps(build_info, indent=2) + '\n', encoding='utf8')
    shutil.copy2(source_dir / 'COPYING.LGPLv2.1', output / 'COPYING.LGPLv2.1')
    shutil.copy2(source_dir / 'LICENSE.md', output / 'FFmpeg-LICENSE.md')
    shutil.copy2(Path(__file__).with_name('media_helper_NOTICE.txt'), output / 'NOTICE.txt')
    # zlib's license is in the distributed corresponding source, also convenient
    # as a separate notice. No optional third party audio/video codecs included.
    with tarfile.open(downloads / 'zlib-1.3.2.tar.xz') as archive:
        (output / 'zlib-LICENSE.txt').write_bytes(archive.extractfile('zlib-1.3.2/LICENSE').read())
    shutil.copy2(Path(__file__).with_name('media_helper_NOTICE.txt'), sources / 'media_helper_NOTICE.txt')
    manifest = {'schema': 1, 'profile': 'cmp-audio-1', 'target': 'windows-x64',
                'ffmpegVersion': '7.1.5', 'files': {
                    name: {'bytes': (output / name).stat().st_size,
                           'sha256': digest(output / name)} for name in BINARIES}}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work-dir', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--source-cache', type=Path)
    parser.add_argument('--vcvars', type=Path)
    parser.add_argument('--bash', type=Path,
                        default=Path(os.environ.get('ProgramFiles', 'C:/Program Files')) / 'Git/bin/bash.exe')
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('Only Windows x64 is qualified in this package; macOS build is pending.')
    work, output = args.work_dir.resolve(), args.output.resolve()
    if work.exists() or output.exists():
        parser.error('Use new work and output directories.')
    if not str(work).isascii() or any(char in str(work) for char in ' &%"'):
        parser.error('The native build needs an ASCII work path without shell metacharacters/spaces.')
    work.mkdir(parents=True)
    downloads = (args.source_cache or work / 'downloads').resolve()
    fetch_sources(downloads)
    for name in ['make-4.4.1.tar.gz', 'zlib-1.3.2.tar.xz', 'ffmpeg-7.1.5.tar.xz']:
        extract(downloads / name, work)
    env = visual_studio_environment(work, args.vcvars)
    # GNU Make's documented Windows shell option, only a build-tool config.
    config = work / 'make-4.4.1/src/config.h.W32'
    config.write_text(config.read_text().replace(
        '/*#define HAVE_CYGWIN_SHELL 1 */', '#define HAVE_CYGWIN_SHELL 1'))
    run('make', ['cmd', '/d', '/c', 'build_w32.bat --without-guile'],
        work / 'make-4.4.1', env, work)
    make = work / 'make-4.4.1/WinRel/gnumake.exe'
    if not make.is_file():
        raise RuntimeError('GNU Make did not produce an executable.')
    zlib = work / 'zlib-1.3.2'
    run('zlib', [shutil.which('nmake', path=env['PATH']), '/nologo', '/f',
                 'win32/Makefile.msc', 'zlib.lib', 'CFLAGS=-nologo -MT -O2'], zlib, env, work)
    env['INCLUDE'] = str(zlib) + ';' + env['INCLUDE']
    env['LIB'] = str(zlib) + ';' + env['LIB']
    env['PATH'] = str(args.bash.parent.parent / 'usr/bin') + ';' + env['PATH']
    env['MSYS_NO_PATHCONV'] = '1'
    ffmpeg = work / 'ffmpeg-7.1.5'
    run('configure', [str(args.bash), './configure', *FLAGS], ffmpeg, env, work)
    # One-shot build: native Make/MSYS quoting differs for FFmpeg's awk-based
    # dependency scanner. Skip that scanner (not compilation or source inputs).
    run('ffmpeg', [str(make), '-j4', 'SHELL=' + args.bash.as_posix(),
                   'CCDEP=true', 'CXXDEP=true', 'ASDEP=true',
                   'ffmpeg.exe', 'ffprobe.exe'], ffmpeg, env, work)
    assemble(ffmpeg, downloads, output, {
        'sources': {name: {'url': url, 'sha256': sha} for name, (url, sha) in SOURCES.items()},
        'configure': FLAGS, 'zlib': 'nmake /f win32/Makefile.msc zlib.lib CFLAGS="-nologo -MT -O2"',
        'make': 'gnumake -j4 SHELL=<Git-Bash> CCDEP=true CXXDEP=true ASDEP=true ffmpeg.exe ffprobe.exe',
        'makeConfig': 'Enable HAVE_CYGWIN_SHELL in src/config.h.W32 (build tool only).',
        'compiler': subprocess.run([shutil.which('cl', path=env['PATH'])],
                                   env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT).stdout.decode(errors='replace'),
        'changes': 'No source changes. Generated configuration/build outputs only.',
        'signature': 'Release verified against FCF986EA15E6E293A5644F10B4322F04D67658D8; pinned SHA-256 thereafter.',
    })
    print('Bundle:', output, flush=True)


if __name__ == '__main__':
    main()
