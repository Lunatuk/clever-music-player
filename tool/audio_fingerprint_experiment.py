"""Measure Chromaprint bit agreement on two local recordings, without a match verdict."""

import argparse
from dataclasses import asdict, dataclass
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
import time


ALGORITHM = 1  # FFmpeg's zero-based value for Chromaprint TEST2.
MIN_SECONDS = 18
MAX_SECONDS = 30 * 60
WINDOW_SECONDS = 24
MAX_BYTES = 128 * 1024 * 1024
MAX_DURATION_GAP = 1.5
MIN_FRAMES = 96
MAX_LAG_FRAMES = 12
MIN_DISTINCT_WORDS = 12
WINDOW_STEP_SECONDS = 20
INPUT_LIMITS = (
    '-protocol_whitelist', 'file,pipe', '-format_whitelist', 'mp3,mov,flac',
    '-max_alloc', '67108864', '-max_streams', '2',
    '-probesize', '2097152', '-analyzeduration', '5000000',
)


@dataclass(frozen=True)
class FingerprintScore:
    right_lag_frames: int
    compared_frames: int
    mean_bit_agreement: float
    weakest_window_agreement: float
    window_agreement: tuple[float, ...]


def sample_windows(duration: float, *, full: bool = False) -> list[tuple[float, float]]:
    if duration <= 30:
        return [(0.0, duration)]
    last_start = duration - WINDOW_SECONDS
    if full:
        starts = [*range(0, math.ceil(last_start), WINDOW_STEP_SECONDS), last_start]
        return [(start, WINDOW_SECONDS) for start in starts]
    starts = (0.0, last_start) if duration <= 48 else (
        0.0, last_start / 2, last_start)
    return [(start, WINDOW_SECONDS) for start in starts]


def fingerprint_words(raw: bytes) -> tuple[int, ...]:
    # FFmpeg writes raw uint32_t items in the executable's native byte order.
    if len(raw) > 4096 or len(raw) % 4:
        raise ValueError('Invalid raw Chromaprint output')
    return tuple(word for (word,) in struct.iter_unpack('=I', raw))


def score_windows(left: list[tuple[int, ...]], right: list[tuple[int, ...]]
                  ) -> FingerprintScore | None:
    if len(left) != len(right) or not left:
        raise ValueError('Both recordings must have the same analysis windows')
    if any(len(words) < MIN_FRAMES or len(set(words)) < MIN_DISTINCT_WORDS
           for words in (*left, *right)):
        return None

    best = None
    for lag in range(-MAX_LAG_FRAMES, MAX_LAG_FRAMES + 1):
        scores, total_bits, total_errors = [], 0, 0
        left_start, right_start = max(0, -lag), max(0, lag)
        for left_words, right_words in zip(left, right, strict=True):
            count = min(len(left_words) - left_start, len(right_words) - right_start)
            if count < MIN_FRAMES or count * 10 < 9 * max(len(left_words), len(right_words)):
                break
            errors = sum((left_words[left_start + i] ^ right_words[right_start + i]).bit_count()
                         for i in range(count))
            bits = count * 32
            scores.append(1 - errors / bits)
            total_bits += bits
            total_errors += errors
        if len(scores) == len(left):
            current = FingerprintScore(lag, total_bits // 32, 1 - total_errors / total_bits,
                                       min(scores), tuple(scores))
            if best is None or _rank(current) > _rank(best):
                best = current
    return best


def _rank(score: FingerprintScore) -> tuple[float, float, int, int]:
    return (score.mean_bit_agreement, score.weakest_window_agreement,
            score.compared_frames, -abs(score.right_lag_frames))


def _run(executable: Path, arguments: list[str], deadline: float) -> bytes:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise ValueError('Comparison time budget exceeded')
    completed = subprocess.run([str(executable), *arguments], stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               timeout=min(15, remaining))
    if completed.returncode != 0:
        raise ValueError(f'{executable.name} could not read the file or lacks Chromaprint support')
    return completed.stdout


def _duration(probe: Path, file: Path, deadline: float) -> float:
    result = _run(probe, [
        '-v', 'error', *INPUT_LIMITS, '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1', '-i', str(file),
    ], deadline)
    duration = float(result)
    if not math.isfinite(duration) or duration <= 0 or duration > MAX_SECONDS:
        raise ValueError('Unsupported recording duration')
    return duration


def _fingerprint(ffmpeg: Path, file: Path, start: float, span: float,
                 deadline: float) -> tuple[int, ...]:
    raw = _run(ffmpeg, [
        '-hide_banner', '-nostdin', '-v', 'error', '-xerror', '-threads', '1',
        '-filter_threads', '1', *INPUT_LIMITS, '-ss', f'{start:.3f}', '-i', str(file),
        '-t', f'{span:.3f}', '-map', '0:a:0', '-vn', '-sn', '-dn',
        '-ac', '1', '-ar', '11025', '-c:a', 'pcm_s16le', '-f', 'chromaprint',
        '-algorithm', str(ALGORITHM), '-fp_format', 'raw', 'pipe:1',
    ], deadline)
    return fingerprint_words(raw)


def _file_stamp(file: Path) -> tuple[int, int, int, int, int]:
    stat = file.stat()
    if not file.is_file() or not 0 < stat.st_size <= MAX_BYTES:
        raise ValueError('Expected a regular local audio file of at most 128 MiB')
    return stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns


def compare_files(ffmpeg: Path, first: Path, second: Path, *, full: bool = False) -> dict:
    ffmpeg, first, second = (path.resolve(strict=True) for path in (ffmpeg, first, second))
    probe = ffmpeg.with_name('ffprobe' + ffmpeg.suffix)
    files = (first, second)
    before = tuple(_file_stamp(file) for file in files)
    deadline = time.monotonic() + (60 if full else 30)
    durations = tuple(_duration(probe, file, deadline) for file in files)
    result = {'algorithm': ALGORITHM, 'durations_seconds': durations,
              'analysis': 'overlapping_windows' if full else 'sampled'}
    if abs(durations[0] - durations[1]) > MAX_DURATION_GAP:
        return dict(result, status='inconclusive', reason='duration_gap')
    if min(durations) < MIN_SECONDS:
        return dict(result, status='inconclusive', reason='too_short')
    windows = sample_windows(min(durations), full=full)
    left, right = ([_fingerprint(ffmpeg, file, start, span, deadline) for start, span in windows]
                   for file in files)
    if tuple(_file_stamp(file) for file in files) != before:
        raise ValueError('A recording changed during analysis')
    score = score_windows(left, right)
    result['windows_seconds'] = windows
    if score is None:
        return dict(result, status='inconclusive', reason='insufficient_comparable_audio')
    return dict(result, status='scored', **asdict(score))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', required=True, type=Path,
                        help='Local FFmpeg with the chromaprint muxer, alongside FFprobe')
    parser.add_argument('--full', action='store_true',
                        help='Compare overlapping windows throughout the recording')
    parser.add_argument('first', type=Path)
    parser.add_argument('second', type=Path)
    args = parser.parse_args()
    try:
        result = compare_files(args.ffmpeg, args.first, args.second, full=args.full)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f'Cannot compare: {error}', file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
