import array
import json
import math
import os
from pathlib import Path
import random
import struct
import subprocess
import tempfile
import time
import unittest
import wave

from audio_fingerprint_experiment import (
    compare_files,
    fingerprint_words,
    sample_windows,
    score_windows,
)


class FingerprintScoringTest(unittest.TestCase):
    def test_global_alignment_applies_to_all_windows(self):
        rng = random.Random(42)
        left = [tuple(rng.getrandbits(32) for _ in range(180)) for _ in range(3)]
        right = [(0, 1, 2, 3, 4) + words for words in left]
        score = score_windows(left, right)
        self.assertEqual(score.right_lag_frames, 5)
        self.assertEqual(score.compared_frames, 540)
        self.assertEqual(score.mean_bit_agreement, 1)
        inverse = score_windows(right, left)
        self.assertEqual(inverse.right_lag_frames, -5)

    def test_weakest_window_surfaces_a_different_ending(self):
        rng = random.Random(21)
        first, last = [tuple(rng.getrandbits(32) for _ in range(180)) for _ in range(2)]
        changed = tuple(word ^ 0x0f0f0f0f for word in last)
        score = score_windows([first, last], [first, changed])
        self.assertEqual(score.right_lag_frames, 0)
        self.assertEqual(score.mean_bit_agreement, 0.75)
        self.assertEqual(score.weakest_window_agreement, 0.5)

    def test_short_repetitive_and_low_overlap_inputs_are_inconclusive(self):
        rng = random.Random(13)
        usable = tuple(rng.getrandbits(32) for _ in range(150))
        for unsuitable in (usable[:70], (0,) * 150, usable[:100]):
            with self.subTest(length=len(unsuitable)):
                self.assertIsNone(score_windows([usable], [unsuitable]))

    def test_windows_reach_the_end_and_raw_words_are_strict(self):
        self.assertEqual(sample_windows(25.0), [(0, 25)])
        self.assertEqual(sample_windows(40.0), [(0, 24), (16, 24)])
        self.assertEqual(sample_windows(90.0), [(0, 24), (33, 24), (66, 24)])
        self.assertEqual(sample_windows(90.0, full=True),
                         [(0, 24), (20, 24), (40, 24), (60, 24), (66, 24)])
        self.assertEqual(fingerprint_words(struct.pack('=II', 5, 0xffffffff)), (5, 0xffffffff))
        for invalid in (b'abc', b'\0' * 4100):
            with self.assertRaises(ValueError):
                fingerprint_words(invalid)


RATE = 22050
SECONDS = 90
_FFMPEG = os.environ.get('CMP_TEST_CHROMAPRINT_FFMPEG')


def _recording(seed):
    """Deterministic polyphonic fixture with changing chords, melody and accents."""
    rng = random.Random(seed)
    palette = (0, 2, 3, 5, 7, 9, 10, 12)
    samples = array.array('h')
    for note in range(SECONDS * 2):
        root = rng.choice(palette) + (3 if seed % 2 else 0)
        lead = root + rng.choice((12, 15, 19, 24, 27))
        lead_step, root_step, third_step = (
            math.tau * 110 * 2 ** (pitch / 12) / RATE
            for pitch in (lead, root, root + rng.choice((3, 4, 7)))
        )
        length = RATE // 2
        for i in range(length):
            envelope = min(1, i / 300, (length - i) / 900)
            bass = math.sin(root_step * i) + 0.35 * math.sin(root_step * i * 2)
            melody = math.sin(lead_step * i) + 0.24 * math.sin(lead_step * i * 3)
            chord = math.sin(third_step * i)
            drum = math.sin(i * 0.022) * max(0, 1 - i / 1200)
            samples.append(round(envelope * (4600 * bass + 3000 * melody + 2100 * chord + 1400 * drum)))
    if struct.pack('=H', 1) != b'\x01\x00':
        samples.byteswap()
    return samples.tobytes()


def _wav(path, data):
    with wave.open(str(path), 'wb') as stream:
        stream.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        stream.writeframes(data)


@unittest.skipUnless(_FFMPEG, 'Set CMP_TEST_CHROMAPRINT_FFMPEG to run the local file experiment')
class FingerprintFileExperiment(unittest.TestCase):
    def test_real_encodings_and_counterexamples(self):
        ffmpeg = Path(_FFMPEG).resolve(strict=True)
        first, other = _recording(17), _recording(42)
        with tempfile.TemporaryDirectory(prefix='cmp_chromaprint_') as temporary:
            root = Path(temporary)
            first_wave, second_wave = root / 'first.wav', root / 'second.wav'
            _wav(first_wave, first)
            _wav(second_wave, other)
            frames = RATE * 2
            gap = slice(27 * frames, 30 * frames)
            delayed_samples = int(0.6 * RATE) * 2
            tail = (RATE // 4) * 2
            for filename, data in [
                ('shared_intro', first[:60 * frames] + other[60 * frames:]),
                ('gap_edit', first[:gap.start] + other[gap] + first[gap.stop:]),
                ('tail_edit', first[:-tail] + other[-tail:]),
                ('delayed', bytes(delayed_samples) + first[:-delayed_samples]),
                ('short', first[:8 * frames]),
                ('trimmed', first[:86 * frames]),
                ('silence', bytes(len(first))),
            ]:
                _wav(root / f'{filename}.wav', data)

            def encode(stem, output, *options):
                subprocess.run([str(ffmpeg), '-hide_banner', '-v', 'error', '-nostdin', '-n',
                                '-i', str(root / f'{stem}.wav'), *options, str(root / output)],
                               check=True, timeout=20)
                return root / output

            baseline = encode('first', 'baseline.flac', '-c:a', 'flac')
            mp3 = encode('first', 'changed tags.mp3', '-c:a', 'libmp3lame',
                         '-b:a', '64k', '-metadata', 'title=Changed title')
            aac = encode('first', 'gain.m4a', '-c:a', 'aac', '-b:a', '96k',
                         '-af', 'volume=0.55')
            unrelated = encode('second', 'unrelated.flac', '-c:a', 'flac')
            shared = encode('shared_intro', 'reused intro.flac', '-c:a', 'flac')
            edit = encode('gap_edit', 'edit in gap.flac', '-c:a', 'flac')
            tail_edit = encode('tail_edit', 'edit in last quarter-second.flac', '-c:a', 'flac')
            delayed = encode('delayed', 'delayed.flac', '-c:a', 'flac')
            short = encode('short', 'short.flac', '-c:a', 'flac')
            trimmed = encode('trimmed', 'different duration.flac', '-c:a', 'flac')
            silence = encode('silence', 'silence.flac', '-c:a', 'flac')

            def compare(label, left, right, *, full=False):
                started = time.perf_counter()
                report = compare_files(ffmpeg, left, right, full=full)
                print(json.dumps({'case': label, 'elapsed_seconds': round(time.perf_counter() - started, 3),
                                  **report}), flush=True)
                return report

            self.assertGreater(compare('FLAC -> MP3', baseline, mp3)['weakest_window_agreement'], 0.85)
            self.assertGreater(compare('FLAC -> AAC with gain change', baseline, aac)['weakest_window_agreement'], 0.85)
            self.assertGreater(compare('MP3 vs AAC', mp3, aac)['weakest_window_agreement'], 0.85)
            report = compare('same recording shifted by 0.6 seconds', baseline, delayed)
            self.assertGreater(report['weakest_window_agreement'], 0.85)
            self.assertNotEqual(report['right_lag_frames'], 0)
            different = compare('different recordings', baseline, unrelated)
            shared_result = compare('same intro, different ending', baseline, shared)
            self.assertLess(different['mean_bit_agreement'], 0.85)
            self.assertLess(shared_result['weakest_window_agreement'],
                            shared_result['mean_bit_agreement'])
            # This negative control deliberately changes only an unsampled gap.
            self.assertEqual(compare('edit between windows', baseline, edit)['mean_bit_agreement'], 1)
            detailed = compare('edit between windows, full analysis', baseline, edit, full=True)
            self.assertLess(detailed['weakest_window_agreement'], 1)
            transcode = compare('FLAC -> MP3, full analysis', baseline, mp3, full=True)
            self.assertGreater(transcode['weakest_window_agreement'],
                               detailed['weakest_window_agreement'])
            # The FFT and classifier context can miss edits at the stream boundary.
            self.assertEqual(compare('edit at the end, full analysis', baseline, tail_edit,
                                     full=True)['mean_bit_agreement'], 1)
            self.assertEqual(compare('short inputs', short, short)['reason'], 'too_short')
            self.assertEqual(compare('substantially different durations', baseline, trimmed)['reason'], 'duration_gap')
            self.assertEqual(compare('uninformative windows', silence, silence)['reason'],
                             'insufficient_comparable_audio')


if __name__ == '__main__':
    unittest.main()
