import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../library/library_scan_control.dart';
import 'ffmpeg_audio_metadata_backend.dart';
import 'media_process_runner.dart';

enum MediaHelperFailure {
  unsupportedPlatform,
  missing,
  invalidBundle,
  incompatible,
  unavailable,
  timedOut,
}

final class MediaHelperException implements Exception {
  const MediaHelperException(this.failure);
  final MediaHelperFailure failure;
}

/// Valid for an unchanged installed bundle. The download owner must qualify
/// again after an application/helper update, rather than persisting this proof.
final class QualifiedMediaHelper {
  const QualifiedMediaHelper._(this.ffmpegPath, this.ffprobePath);
  final String ffmpegPath, ffprobePath;
  String get version => BundledMediaHelper.version;

  FfmpegAudioMetadataBackend createMetadataBackend() =>
      FfmpegAudioMetadataBackend(
          ffmpegPath: ffmpegPath, ffprobePath: ffprobePath);
}

/// Explicit, offline and lazy: no work at player startup. SHA-256 detects
/// incomplete/corrupted packages; an editable local manifest is not a signature
/// or a sandbox against someone able to replace the application itself.
final class BundledMediaHelper {
  BundledMediaHelper(
      {required Directory directory,
      this.target = 'windows-x64',
      MediaProcessRunner? runner,
      this.timeout = const Duration(seconds: 30)})
      : directory = directory.absolute,
        _runner = runner ?? BoundedMediaProcessRunner() {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 2)) {
      throw ArgumentError('Некорректный срок проверки помощника.');
    }
  }

  factory BundledMediaHelper.forCurrentProcess() {
    if (Abi.current() != Abi.windowsX64) {
      throw const MediaHelperException(MediaHelperFailure.unsupportedPlatform);
    }
    return BundledMediaHelper(
        directory: Directory(p.join(
            p.dirname(Platform.resolvedExecutable), 'tools', 'media-helper')));
  }

  static const version = '7.1.5';
  static const binaries = [
    'ffmpeg.exe',
    'ffprobe.exe',
    'avcodec-61.dll',
    'avfilter-10.dll',
    'avformat-61.dll',
    'avutil-59.dll',
    'swresample-5.dll',
    'swscale-8.dll',
  ];
  final Directory directory;
  final String target;
  final Duration timeout;
  final MediaProcessRunner _runner;
  bool _closed = false;
  Completer<void>? _active;
  LibraryScanControl? _control;
  Future<void>? _closing;

  Future<QualifiedMediaHelper> qualify({LibraryScanControl? control}) async {
    if (_closed) throw StateError('Проверка помощника закрыта.');
    if (_active != null) throw StateError('Проверка уже выполняется.');
    if (target != 'windows-x64') {
      throw const MediaHelperException(MediaHelperFailure.unsupportedPlatform);
    }
    control?.throwIfCancelled();
    final active = Completer<void>();
    _active = active;
    final current = LibraryScanControl();
    _control = current;
    control?.addCancellationListener(current.cancel);
    var timedOut = false;
    final timer = Timer(timeout, () {
      timedOut = true;
      current.cancel();
    });
    try {
      final manifest = await _manifest(current);
      await _verifyFiles(manifest, current);
      final ffmpeg = p.join(directory.path, 'ffmpeg.exe');
      final ffprobe = p.join(directory.path, 'ffprobe.exe');
      for (final entry in [(ffmpeg, 'ffmpeg'), (ffprobe, 'ffprobe')]) {
        final output = await _run(entry.$1, ['-version'], current);
        if (!output.startsWith('${entry.$2} version $version ') ||
            !output.contains('--disable-network') ||
            !output.contains('--enable-shared') ||
            !output.contains('--disable-autodetect') ||
            output.contains('--enable-gpl') ||
            output.contains('--enable-version3') ||
            output.contains('--enable-nonfree')) {
          throw const MediaHelperException(MediaHelperFailure.incompatible);
        }
      }
      for (final entry in const {
        '-decoders': {'mp3float', 'aac', 'flac', 'png', 'mjpeg'},
        '-encoders': {'pcm_s16le', 'pcm_s32le', 'wrapped_avframe'},
        '-demuxers': {'mp3', 'mov', 'flac', 'png_pipe', 'jpeg_pipe'},
        '-muxers': {'mp3', 'ipod', 'flac', 'null', 'hash'},
        '-filters': {'asetpts', 'aformat', 'aresample', 'null'},
      }.entries) {
        final output = await _run(ffmpeg, ['-hide_banner', entry.key], current);
        // FFmpeg tables have a fixed flag column, then a comma-separated name
        // column. Do not accept a name appearing only in the description.
        final names = <String>{};
        for (final line in const LineSplitter().convert(output)) {
          final match = RegExp(r'^\s*[A-Z.]{1,6}\s+(\S+)\s+').firstMatch(line);
          if (match != null) names.addAll(match[1]!.split(','));
        }
        if (!names.containsAll(entry.value)) {
          throw const MediaHelperException(MediaHelperFailure.incompatible);
        }
      }
      final protocols =
          await _run(ffmpeg, ['-hide_banner', '-protocols'], current);
      final names = const LineSplitter()
          .convert(protocols)
          .map((line) => line.trim())
          .where((line) => RegExp(r'^[a-z][a-z0-9_]+$').hasMatch(line))
          .toSet();
      if (names.length != 2 || !names.containsAll({'file', 'pipe'})) {
        throw const MediaHelperException(MediaHelperFailure.incompatible);
      }
      // Detect accidental replacement during probing too. Future processing
      // still assumes a stable application installation, not a hostile folder.
      await _verifyFiles(manifest, current);
      current.throwIfCancelled();
      return QualifiedMediaHelper._(ffmpeg, ffprobe);
    } on LibraryScanCancelled {
      if (timedOut) {
        throw const MediaHelperException(MediaHelperFailure.timedOut);
      }
      rethrow;
    } on FileSystemException {
      throw const MediaHelperException(MediaHelperFailure.invalidBundle);
    } on FormatException {
      throw const MediaHelperException(MediaHelperFailure.invalidBundle);
    } finally {
      timer.cancel();
      control?.removeCancellationListener(current.cancel);
      _control = null;
      _active = null;
      active.complete();
    }
  }

  Future<Map<String, dynamic>> _manifest(LibraryScanControl control) async {
    final kind =
        await FileSystemEntity.type(directory.path, followLinks: false);
    if (kind == FileSystemEntityType.notFound) {
      throw const MediaHelperException(MediaHelperFailure.missing);
    }
    if (kind != FileSystemEntityType.directory) {
      throw const MediaHelperException(MediaHelperFailure.invalidBundle);
    }
    final file = File(p.join(directory.path, 'manifest.json'));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const MediaHelperException(MediaHelperFailure.invalidBundle);
    }
    final bytes = <int>[];
    await for (final chunk in file.openRead()) {
      control.throwIfCancelled();
      if (bytes.length + chunk.length > 8192) {
        throw const MediaHelperException(MediaHelperFailure.invalidBundle);
      }
      bytes.addAll(chunk);
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic> ||
        value.length != 5 ||
        value['schema'] != 1 ||
        value['profile'] != 'cmp-audio-1' ||
        value['target'] != target ||
        value['ffmpegVersion'] != version ||
        value['files'] is! Map<String, dynamic>) {
      throw const MediaHelperException(MediaHelperFailure.invalidBundle);
    }
    final files = value['files'] as Map<String, dynamic>;
    if (files.length != binaries.length ||
        !files.keys.toSet().containsAll(binaries)) {
      throw const MediaHelperException(MediaHelperFailure.invalidBundle);
    }
    for (final entry in files.values) {
      if (entry is! Map ||
          entry.length != 2 ||
          entry['bytes'] is! int ||
          entry['bytes'] < 1 ||
          entry['bytes'] > 64 * 1024 * 1024 ||
          entry['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry['sha256'])) {
        throw const MediaHelperException(MediaHelperFailure.invalidBundle);
      }
    }
    return files;
  }

  Future<void> _verifyFiles(
      Map<String, dynamic> manifest, LibraryScanControl control) async {
    for (final entry in manifest.entries) {
      control.throwIfCancelled();
      final file = File(p.join(directory.path, entry.key));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() != entry.value['bytes']) {
        throw const MediaHelperException(MediaHelperFailure.invalidBundle);
      }
      var count = 0;
      final hash = await sha256
          .bind(file.openRead().map((chunk) {
            control.throwIfCancelled();
            count += chunk.length;
            if (count > entry.value['bytes']) {
              throw const MediaHelperException(
                  MediaHelperFailure.invalidBundle);
            }
            return chunk;
          }))
          .first;
      if (count != entry.value['bytes'] ||
          hash.toString() != entry.value['sha256']) {
        throw const MediaHelperException(MediaHelperFailure.invalidBundle);
      }
    }
  }

  Future<String> _run(
      String path, List<String> args, LibraryScanControl control) async {
    try {
      final output = await _runner.run(path, args, control);
      control.throwIfCancelled();
      if (output.exitCode != 0 || output.hadStderr) {
        throw const MediaHelperException(MediaHelperFailure.incompatible);
      }
      return output.stdout;
    } on MediaProcessFailure {
      control.throwIfCancelled();
      throw const MediaHelperException(MediaHelperFailure.unavailable);
    }
  }

  Future<void> close() {
    _closed = true;
    _control?.cancel();
    return _closing ??= _close(_active?.future);
  }

  Future<void> _close(Future<void>? active) async {
    await active;
    await _runner.close();
  }
}
