import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:cmp_file_ops/cmp_file_ops.dart';
import 'package:path/path.dart' as p;

enum PublicationFileFailure {
  busy,
  collision,
  accessDenied,
  noSpace,
  unsupported,
  io
}

final class PublicationFileException implements Exception {
  const PublicationFileException(this.reason, {this.osCode});
  final PublicationFileFailure reason;
  final int? osCode;
  @override
  String toString() => 'PublicationFileException(${reason.name}, $osCode)';
}

/// OS handles stay alive across awaited Dart/worker operations in this process.
final class PublicationFileLock {
  PublicationFileLock._(this._handle);
  final int _handle;
  Future<void>? _closing;
  Future<void> close() {
    final handle = _handle;
    return _closing ??= Isolate.run(() => _close(handle));
  }
}

/// Short OS calls on workers. No overwrite/cross-volume-copy fallback.
abstract interface class PublicationFiles {
  Future<bool> createDirectory(String path);
  Future<PublicationFileLock> lock(String path, {bool seal = false});
  Future<void> moveNoReplace(String source, String target);
}

final class NativePublicationFiles implements PublicationFiles {
  const NativePublicationFiles();
  @override
  Future<bool> createDirectory(String path) => Isolate.run(() => _mkdir(path));
  @override
  Future<PublicationFileLock> lock(String path, {bool seal = false}) async {
    final handle = await Isolate.run(() => _lock(path, seal));
    return PublicationFileLock._(handle);
  }

  @override
  Future<void> moveNoReplace(String source, String target) =>
      Isolate.run(() => _move(source, target));
}

Never _fail(int code, {bool locking = false}) {
  final reason = Platform.isWindows
      ? switch (code) {
          80 || 183 => PublicationFileFailure.collision,
          32 ||
          33 =>
            locking ? PublicationFileFailure.busy : PublicationFileFailure.io,
          5 => PublicationFileFailure.accessDenied,
          39 || 112 => PublicationFileFailure.noSpace,
          17 || 50 => PublicationFileFailure.unsupported,
          _ => PublicationFileFailure.io,
        }
      : switch (code) {
          17 => PublicationFileFailure.collision,
          11 ||
          35 =>
            locking ? PublicationFileFailure.busy : PublicationFileFailure.io,
          1 || 13 => PublicationFileFailure.accessDenied,
          28 || 122 || 69 => PublicationFileFailure.noSpace,
          18 || 45 || 95 => PublicationFileFailure.unsupported,
          38 when Platform.isAndroid => PublicationFileFailure.unsupported,
          _ => PublicationFileFailure.io,
        };
  throw PublicationFileException(reason, osCode: code);
}

void _supported() {
  // Android support is for app-private ordinary paths. SAF content URIs need
  // their own provider adapter and must never be passed to these POSIX calls.
  if (!Platform.isWindows &&
      !Platform.isMacOS &&
      !Platform.isLinux &&
      !Platform.isAndroid) {
    throw const PublicationFileException(PublicationFileFailure.unsupported);
  }
}

String _winPath(String path) {
  final value = p.normalize(p.absolute(path)).replaceAll('/', r'\');
  if (value.startsWith(r'\\?\')) return value;
  return value.startsWith(r'\\')
      ? r'\\?\UNC\' + value.substring(2)
      : r'\\?\' + value;
}

Pointer<Void> _path(String path) => Platform.isWindows
    ? _winPath(path).toNativeUtf16().cast<Void>()
    : path.toNativeUtf8().cast<Void>();

bool _mkdir(String path) {
  _supported();
  final name = _path(path);
  try {
    final code = cmpMkdir(name);
    if (code < 0) _fail(-code);
    return code == 0;
  } finally {
    calloc.free(name);
  }
}

int _lock(String path, bool seal) {
  _supported();
  final name = _path(path), output = calloc<IntPtr>();
  try {
    final code = cmpLock(name, seal ? 1 : 0, output);
    if (code < 0) _fail(-code, locking: true);
    return output.value;
  } finally {
    calloc.free(name);
    calloc.free(output);
  }
}

void _close(int handle) {
  final code = cmpClose(handle);
  if (code < 0) _fail(-code);
}

void _move(String source, String target) {
  _supported();
  final from = _path(source), to = _path(target);
  try {
    final code = cmpMove(from, to);
    if (code < 0) _fail(-code);
  } finally {
    calloc.free(from);
    calloc.free(to);
  }
}
