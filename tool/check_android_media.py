"""Exercise the Android media C core on a Windows host with real FFmpeg 7.1.5.

Host tests do not qualify JNI, ContentResolver or phone hardware. They compile
the same C core, verify all six format/cover combinations and fault paths.
Only a new, owned work directory and the shipped/generated fixtures are used.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import threading
import time

from build_media_helper import visual_studio_environment


def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg-build', type=Path, required=True)
    parser.add_argument('--runtime', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    args = parser.parse_args()
    if os.name != 'nt' or args.work_dir.exists():
        parser.error('Use Windows and a new work directory.')
    root = Path(__file__).resolve().parent.parent
    work = args.work_dir.resolve()
    work.mkdir(parents=True)
    environment = visual_studio_environment(work, None)
    ffmpeg = args.ffmpeg_build.resolve()
    command = [shutil.which('cl', path=environment['PATH']), '/nologo', '/std:c11', '/MT', '/O2', '/W4', '/LD',
               '/I' + str(ffmpeg), str(root / 'third_party/cmp_android_media/src/cmp_media.c'),
               '/Fe:' + str(work / 'cmp_media.dll'), '/link']
    for name in ['avformat', 'avcodec', 'avutil', 'swresample']:
        command += ['/LIBPATH:' + str(ffmpeg / ('lib' + name)), name + '.lib']
    result = subprocess.run(command, cwd=work, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    (work / 'compile.log').write_bytes(result.stdout)
    if result.returncode:
        raise RuntimeError('Native host compilation failed; see compile.log')
    search = os.add_dll_directory(str(args.runtime.resolve()))
    library = ctypes.CDLL(str(work / 'cmp_media.dll'))
    library.cmp_media_run.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_char_p,
        ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_int64, ctypes.POINTER(ctypes.c_char_p)]
    library.cmp_media_run.restype = ctypes.c_char_p
    keys = ['title', 'artist', 'album', 'album_artist', 'genre', 'track', 'disc', 'date']
    expected = dict(zip(keys, ['Проверка 😀', 'Исполнитель трека', 'Альбом', 'Исполнитель альбома', 'Electronic', '2', '1', '2026']))
    def call(op, source=None, output=None, cover=None, cover_format=0, mode=0, limit=1000000, tags=expected, accepted=False):
        values = (ctypes.c_char_p * 8)(*[tags[k].encode() if k in tags else None for k in keys])
        paths = [str(p.resolve()).encode() if p is not None else None for p in (source, output, cover)]
        if not accepted:
            assert library.cmp_media_begin() == 1
        try:
            response = json.loads(library.cmp_media_run(op, *paths, cover_format, mode, limit, values).decode('utf8'))
            assert isinstance(response, dict) and isinstance(response.get('status'), str)
            return response
        finally:
            library.cmp_media_end()
    def ok(*args, **kwargs):
        response = call(*args, **kwargs)
        assert response['status'] == 'ok', response
        return response
    cases = []
    def passed(name):
        cases.append(name)
        print('PASS', name, flush=True)
    assert ok(0) == {'status': 'ok', 'profile': 'cmp-android-audio-1', 'version': '7.1.5', 'license': 'LGPL version 2.1 or later'}
    passed('pinned capabilities')
    fixtures = root / 'assets/media_check'
    for ext in ['mp3', 'm4a', 'flac']:
        source = fixtures / ('tone.' + ext)
        original = digest(source)
        source_info = ok(1, source)['inspection']
        assert source_info['container'] == ext
        assert source_info['channels'] == 2 and source_info['sampleRate'] == 48000
        if ext == 'flac':
            assert source_info['bitDepth'] == 24
        assert ok(2, source)['durationUs'] > 0
        for name, kind in [('cover.png', 1), ('cover.jpg', 2)]:
            target = work / (ext + '-' + name + '.part')
            target.touch(exist_ok=False)
            ok(5, source, target, fixtures / name, kind)
            prepared = ok(1, target)['inspection']
            assert prepared['tags'] == expected and prepared['coverStreamIndex'] is not None
            for mode in [0, 1]:
                assert ok(4, source, mode=mode)['digest'] == ok(4, target, mode=mode)['digest']
            assert ok(4, target, mode=2)['digest'] == digest(fixtures / name)
            ok(3, target)
            # A second pass clears old tags, keeps the existing artwork and audio.
            retained = work / (ext + '-' + name + '-retained.part')
            retained.touch(exist_ok=False)
            ok(5, target, retained, tags={'title': 'Only this title'})
            assert ok(1, retained)['inspection']['tags'] == {'title': 'Only this title'}
            assert ok(4, retained, mode=2)['digest'] == digest(fixtures / name)
            for mode in [0, 1]:
                assert ok(4, source, mode=mode)['digest'] == ok(4, retained, mode=mode)['digest']
            assert digest(source) == original
            passed(ext + ' / ' + name + ' / clear tags / preserve artwork / exact audio')
        assert call(3, source)['status'] == 'coverMissing'
    source = fixtures / 'tone.mp3'
    original = digest(source)
    nonempty = work / 'unowned-nonempty.part'
    nonempty.write_bytes(b'keep this file')
    assert call(5, source, nonempty)['status'] != 'ok' and nonempty.read_bytes() == b'keep this file'
    assert call(5, source, source)['status'] != 'ok' and digest(source) == original
    passed('no overwrite of source or nonempty output')
    quota = work / 'quota.part'
    quota.touch(exist_ok=False)
    assert call(5, source, quota, limit=100)['status'] == 'quotaExceeded'
    assert quota.stat().st_size <= 100 and digest(source) == original
    passed('write quota does not exceed reservation')
    invalid = work / 'invalid.part'
    invalid.write_bytes(b'<html>not audio</html>')
    assert call(1, invalid)['status'] == 'invalidAudio'
    empty = work / 'empty.part'
    empty.touch(exist_ok=False)
    assert call(1, empty)['status'] != 'ok'
    assert call(1, work / 'missing.part')['status'] != 'ok'
    passed('malformed, empty and missing source')
    bad_cover = work / 'bad-cover.part'
    bad_cover.write_bytes(b'\x89PNG\r\n\x1a\nnot-a-picture')
    output = work / 'bad-cover-output.part'
    output.touch(exist_ok=False)
    assert call(5, source, output, bad_cover, 1)['status'] != 'ok' and output.stat().st_size == 0
    passed('invalid picture cannot produce ready output')
    assert library.cmp_media_begin() == 1
    assert library.cmp_media_begin() == 0
    library.cmp_media_cancel()
    assert call(1, source, accepted=True)['status'] == 'cancelled'
    passed('global admission and pre-cancellation')
    # Stream-copy an existing fixture into a bounded long stress input. No music
    # or network; the external helper is only a host test-fixture generator.
    long_source = work / 'long.mp3'
    subprocess.run([str(args.runtime / 'ffmpeg.exe'), '-nostdin', '-v', 'error',
                    '-stream_loop', '2000', '-i', str(source), '-c:a', 'copy',
                    str(long_source)], check=True)
    assert library.cmp_media_begin() == 1
    started = threading.Event()
    answer = []
    def decode():
        started.set()
        answer.append(call(2, long_source, accepted=True))
    thread = threading.Thread(target=decode)
    thread.start()
    assert started.wait(5)
    time.sleep(0.005)
    library.cmp_media_cancel()
    thread.join(5)
    assert not thread.is_alive() and answer == [{'status': 'cancelled'}], answer
    long_source.unlink()  # Windows proves the source descriptor has closed.
    passed('cancellation drains full decoder and closes descriptors')
    search.close()
    report = {'nativeChecks': len(cases), 'cases': cases, 'phoneQualified': False,
              'coreSha256': digest(root / 'third_party/cmp_android_media/src/cmp_media.c')}
    (work / 'checks.json').write_text(json.dumps(report, indent=2), encoding='utf8')
    print(json.dumps(report, indent=2), flush=True)


if __name__ == '__main__':
    main()
