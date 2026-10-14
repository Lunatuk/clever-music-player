import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

enum Sha256Backend { dart, windowsCng }

abstract interface class Sha256Digest {
  Sha256Backend get backend;
  void add(List<int> bytes);
  String finish();
  void dispose();
}

Sha256Digest createSha256Digest({bool preferNative = true}) {
  if (preferNative && Platform.isWindows) {
    try {
      return _WindowsSha256Digest.create();
    } on Object {
      // Unsupported/failed provider initialization keeps the portable path.
      // Errors after accepting data propagate; no partial digest is published.
    }
  }
  return _DartSha256Digest();
}

String sha256Hex(List<int> bytes, {bool preferNative = true}) {
  final digest = createSha256Digest(preferNative: preferNative);
  try {
    digest.add(bytes);
    return digest.finish();
  } finally {
    digest.dispose();
  }
}

final class _DartSha256Digest implements Sha256Digest {
  _DartSha256Digest() {
    _conversion = sha256.startChunkedConversion(_output);
  }
  final _output = _DigestOutput();
  late final Sink<List<int>> _conversion;
  bool _closed = false;
  @override
  Sha256Backend get backend => Sha256Backend.dart;
  @override
  void add(List<int> bytes) {
    if (_closed) throw StateError('SHA-256 is closed.');
    _conversion.add(bytes);
  }

  @override
  String finish() {
    if (_closed) throw StateError('SHA-256 is closed.');
    _conversion.close();
    _closed = true;
    return _output.digest!.toString();
  }

  @override
  void dispose() {
    if (!_closed) {
      _conversion.close();
      _closed = true;
    }
  }
}

final class _DigestOutput implements Sink<Digest> {
  Digest? digest;
  @override
  void add(Digest data) => digest = data;
  @override
  void close() {}
}

final class _WindowsSha256Digest implements Sha256Digest {
  _WindowsSha256Digest._(this._api);
  static _CngApi? _cachedApi;
  static _WindowsSha256Digest create() {
    final digest = _WindowsSha256Digest._(_cachedApi ??= _CngApi());
    try {
      digest._initialize();
      return digest;
    } on Object {
      digest.dispose();
      rethrow;
    }
  }

  final _CngApi _api;
  Pointer<Void> _algorithm = nullptr;
  Pointer<Void> _hash = nullptr;
  Pointer<Uint8> _object = nullptr;
  Pointer<Uint8> _buffer = nullptr;
  late final Uint8List _bufferView;
  bool _closed = false;
  bool _finished = false;
  static const _bufferSize = 64 * 1024;

  @override
  Sha256Backend get backend => Sha256Backend.windowsCng;

  void _initialize() {
    final output = calloc<Pointer<Void>>();
    final name = 'SHA256'.toNativeUtf16();
    try {
      _check(_api.open(output, name, nullptr, 0));
      _algorithm = output.value;
    } finally {
      calloc.free(name);
      calloc.free(output);
    }
    final objectSize = _property('ObjectLength');
    if (_property('HashDigestLength') != 32 || objectSize <= 0) {
      throw StateError('Unexpected SHA-256 provider properties.');
    }
    _object = calloc<Uint8>(objectSize);
    final hashOutput = calloc<Pointer<Void>>();
    try {
      _check(_api.create(
          _algorithm, hashOutput, _object, objectSize, nullptr, 0, 0));
      _hash = hashOutput.value;
    } finally {
      calloc.free(hashOutput);
    }
    _buffer = calloc<Uint8>(_bufferSize);
    _bufferView = _buffer.asTypedList(_bufferSize);
  }

  int _property(String name) {
    final property = name.toNativeUtf16();
    final value = calloc<Uint32>();
    final length = calloc<Uint32>();
    try {
      _check(
          _api.getProperty(_algorithm, property, value.cast(), 4, length, 0));
      if (length.value != 4) throw StateError('Invalid CNG property length.');
      return value.value;
    } finally {
      calloc.free(property);
      calloc.free(value);
      calloc.free(length);
    }
  }

  @override
  void add(List<int> bytes) {
    if (_closed || _finished) throw StateError('SHA-256 is closed.');
    for (var offset = 0; offset < bytes.length; offset += _bufferSize) {
      final length = (bytes.length - offset).clamp(0, _bufferSize);
      _bufferView.setRange(0, length, bytes, offset);
      _check(_api.hashData(_hash, _buffer, length, 0));
    }
  }

  @override
  String finish() {
    if (_closed || _finished) throw StateError('SHA-256 is closed.');
    final output = calloc<Uint8>(32);
    try {
      _check(_api.finish(_hash, output, 32, 0));
      _finished = true;
      return output
          .asTypedList(32)
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
    } finally {
      calloc.free(output);
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    if (_hash != nullptr) _api.destroy(_hash);
    if (_algorithm != nullptr) _api.close(_algorithm, 0);
    if (_buffer != nullptr) calloc.free(_buffer);
    if (_object != nullptr) calloc.free(_object);
  }
}

void _check(int status) {
  if (status < 0) throw StateError('CNG SHA-256 failed: $status');
}

final class _CngApi {
  _CngApi() : _library = DynamicLibrary.open('bcrypt.dll');
  final DynamicLibrary _library;
  late final open = _library.lookupFunction<
      Int32 Function(
          Pointer<Pointer<Void>>, Pointer<Utf16>, Pointer<Utf16>, Uint32),
      int Function(Pointer<Pointer<Void>>, Pointer<Utf16>, Pointer<Utf16>,
          int)>('BCryptOpenAlgorithmProvider');
  late final getProperty = _library.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Utf16>, Pointer<Uint8>, Uint32,
          Pointer<Uint32>, Uint32),
      int Function(Pointer<Void>, Pointer<Utf16>, Pointer<Uint8>, int,
          Pointer<Uint32>, int)>('BCryptGetProperty');
  late final create = _library.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Uint8>,
          Uint32, Pointer<Uint8>, Uint32, Uint32),
      int Function(Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Uint8>, int,
          Pointer<Uint8>, int, int)>('BCryptCreateHash');
  late final hashData = _library.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Uint32),
      int Function(Pointer<Void>, Pointer<Uint8>, int, int)>('BCryptHashData');
  late final finish = _library.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint32, Uint32),
      int Function(
          Pointer<Void>, Pointer<Uint8>, int, int)>('BCryptFinishHash');
  late final destroy = _library.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('BCryptDestroyHash');
  late final close = _library.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int)>('BCryptCloseAlgorithmProvider');
}
