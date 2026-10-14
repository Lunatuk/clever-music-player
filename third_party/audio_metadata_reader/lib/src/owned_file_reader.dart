import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Entry points own the opened file. Container parsers may close it themselves;
/// final cleanup must close failed probes/parses without double-closing success.
class OwnedFileReader implements RandomAccessFile {
  OwnedFileReader(this._file);
  final RandomAccessFile _file;
  bool _closed = false;
  @override
  String get path => _file.path;
  @override
  void closeSync() {
    if (_closed) return;
    _file.closeSync();
    _closed = true;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await _file.close();
    _closed = true;
  }

  @override
  int readByteSync() => _file.readByteSync();
  @override
  Future<int> readByte() => _file.readByte();
  @override
  Uint8List readSync(int count) => _file.readSync(count);
  @override
  Future<Uint8List> read(int count) => _file.read(count);
  @override
  int readIntoSync(List<int> buffer, [int start = 0, int? end]) =>
      _file.readIntoSync(buffer, start, end);
  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) =>
      _file.readInto(buffer, start, end);
  @override
  int positionSync() => _file.positionSync();
  @override
  Future<int> position() => _file.position();
  @override
  void setPositionSync(int position) => _file.setPositionSync(position);
  @override
  Future<RandomAccessFile> setPosition(int position) async {
    await _file.setPosition(position);
    return this;
  }

  @override
  int lengthSync() => _file.lengthSync();
  @override
  Future<int> length() => _file.length();
  @override
  void truncateSync(int length) => _file.truncateSync(length);
  @override
  Future<RandomAccessFile> truncate(int length) async {
    await _file.truncate(length);
    return this;
  }

  @override
  int writeByteSync(int value) => _file.writeByteSync(value);
  @override
  Future<RandomAccessFile> writeByte(int value) async {
    await _file.writeByte(value);
    return this;
  }

  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) =>
      _file.writeFromSync(buffer, start, end);
  @override
  Future<RandomAccessFile> writeFrom(List<int> buffer,
      [int start = 0, int? end]) async {
    await _file.writeFrom(buffer, start, end);
    return this;
  }

  @override
  void writeStringSync(String string, {Encoding encoding = utf8}) =>
      _file.writeStringSync(string, encoding: encoding);
  @override
  Future<RandomAccessFile> writeString(String string,
      {Encoding encoding = utf8}) async {
    await _file.writeString(string, encoding: encoding);
    return this;
  }

  @override
  void flushSync() => _file.flushSync();
  @override
  Future<RandomAccessFile> flush() async {
    await _file.flush();
    return this;
  }

  @override
  void lockSync(
          [FileLock mode = FileLock.exclusive, int start = 0, int end = -1]) =>
      _file.lockSync(mode, start, end);
  @override
  Future<RandomAccessFile> lock(
      [FileLock mode = FileLock.exclusive, int start = 0, int end = -1]) async {
    await _file.lock(mode, start, end);
    return this;
  }

  @override
  void unlockSync([int start = 0, int end = -1]) =>
      _file.unlockSync(start, end);
  @override
  Future<RandomAccessFile> unlock([int start = 0, int end = -1]) async {
    await _file.unlock(start, end);
    return this;
  }
}
