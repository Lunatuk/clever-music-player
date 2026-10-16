import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Test-only handle: permits reads but denies replacement/deletion of our fixture.
void Function() lockAgainstReplacement(File file) {
  final kernel = DynamicLibrary.open('kernel32.dll');
  final open = kernel.lookupFunction<
      Pointer<Void> Function(Pointer<Utf16>, Uint32, Uint32, Pointer<Void>,
          Uint32, Uint32, Pointer<Void>),
      Pointer<Void> Function(Pointer<Utf16>, int, int, Pointer<Void>, int, int,
          Pointer<Void>)>('CreateFileW');
  final close = kernel.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('CloseHandle');
  final name = ('\\\\?\\${file.absolute.path}').toNativeUtf16();
  final handle = open(name, 0x80000000, 1, nullptr, 3, 0x80, nullptr);
  calloc.free(name);
  if (handle.address == -1 || handle.address == 0xffffffffffffffff) {
    throw StateError('Fixture lock unavailable');
  }
  return () {
    if (close(handle) == 0) throw StateError('Fixture unlock failed');
  };
}
