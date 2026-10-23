"""Offline integrity/source correspondence check for the Android media bundle."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import zipfile

from build_media_helper import SOURCES

SOURCE_FILES = ['tool/build_android_media.py', 'tool/build_media_helper.py',
                'third_party/cmp_android_media/CMakeLists.txt',
                'third_party/cmp_android_media/src/cmp_media.c',
                'third_party/cmp_android_media/src/cmp_media.h',
                'third_party/cmp_android_media/src/cmp_media_jni.c']


def verify(root):
    bundle = root / 'third_party/cmp_android_media/vendor'
    manifest = json.loads((bundle / 'manifest.json').read_text(encoding='utf8'))
    assert (manifest['schema'], manifest['profile'], manifest['version'], manifest['target'],
            manifest['api'], manifest['pageBytes'], manifest['ndk']) == (
        1, 'cmp-android-audio-1', '7.1.5', 'android-arm64', 24, 16384, '28.2.13676358')
    files = manifest['files']
    assert 5 <= len(files) <= 200
    for name, info in files.items():
        relative = PurePosixPath(name)
        assert not relative.is_absolute() and '..' not in relative.parts and '\\' not in name and ':' not in name
        file = bundle / name
        assert file.is_file() and not file.is_symlink() and file.resolve().is_relative_to(bundle.resolve())
        assert file.stat().st_size == info['bytes'] <= 16*1024*1024
        assert hashlib.sha256(file.read_bytes()).hexdigest() == info['sha256'], name
    expected_libraries = {'libavformat.so', 'libavcodec.so', 'libavutil.so', 'libswresample.so'}
    assert {p.name for p in (bundle / 'arm64-v8a').iterdir()} == expected_libraries
    with zipfile.ZipFile(bundle / 'source-kit.zip') as archive:
        assert archive.testzip() is None
        assert len(archive.infolist()) < 32 and sum(i.file_size for i in archive.infolist()) < 32*1024*1024
        for name, (_, expected) in SOURCES.items():
            if name.startswith('ffmpeg'):
                assert hashlib.sha256(archive.read(name)).hexdigest() == expected, name
        for name in SOURCE_FILES:
            # Git may translate source line endings on Windows; pinned vendor
            # bytes themselves are exempt from translation in .gitattributes.
            actual = (root / name).read_text(encoding='utf-8-sig')
            saved = archive.read(name).decode('utf-8-sig').replace('\r\n', '\n')
            assert saved == actual, 'Source kit is stale: ' + name
        generated = archive.read('generated/config.h').decode()
        for flag in ['CONFIG_GPL', 'CONFIG_VERSION3', 'CONFIG_NONFREE', 'CONFIG_NETWORK']:
            assert '#define ' + flag + ' 0' in generated
        components = archive.read('generated/config_components.h').decode()
        assert '#define CONFIG_FILE_PROTOCOL 0' in components
        assert '#define CONFIG_HTTP_PROTOCOL 0' in components
        assert '#define CONFIG_HTTPS_PROTOCOL 0' in components
        for flag in ['MP3_DEMUXER', 'MOV_DEMUXER', 'FLAC_DEMUXER', 'MP3_MUXER', 'IPOD_MUXER', 'FLAC_MUXER', 'MP3FLOAT_DECODER', 'AAC_DECODER', 'FLAC_DECODER', 'PNG_DECODER', 'MJPEG_DECODER']:
            assert '#define CONFIG_' + flag + ' 1' in components, flag
    return {'bundleFiles': len(files), 'runtimeBytes': sum((bundle / 'arm64-v8a' / name).stat().st_size for name in expected_libraries),
            'sourceKitBytes': (bundle / 'source-kit.zip').stat().st_size, 'exactSources': True}


if __name__ == '__main__':
    print(json.dumps(verify(Path(__file__).resolve().parent.parent), indent=2))
