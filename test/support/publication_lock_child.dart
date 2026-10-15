import 'dart:async';
import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

Future<void> main(List<String> args) async {
  final library = DynamicLibrary.open(args[2]);
  final acquire = library.lookupFunction<
      Int32 Function(Pointer<Void>, Int32, Pointer<IntPtr>),
      int Function(Pointer<Void>, int, Pointer<IntPtr>)>('cmp_lock');
  final path = Platform.isWindows
      ? args[0].toNativeUtf16().cast<Void>()
      : args[0].toNativeUtf8().cast<Void>();
  final output = calloc<IntPtr>();
  final int code;
  try {
    code = acquire(path, 0, output);
  } finally {
    calloc.free(path);
    calloc.free(output);
  }
  if (code < 0) {
    if (![-32, -33, -11, -35].contains(code)) {
      throw StateError('Native child lock failed: $code');
    }
    await File(args[1]).writeAsString('busy', flush: true);
    return;
  }
  await File(args[1]).writeAsString('held', flush: true);
  Timer.periodic(const Duration(seconds: 1), (_) {});
}
