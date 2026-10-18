import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Interrupted test writer: the production C lock and exact journals serialized
/// by DownloadWorkspace. The direct SDK VM needs no native build hooks.
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
  if (code < 0) throw StateError('Cannot acquire test process lock: $code');
  final entries = jsonDecode(await File(args[3]).readAsString()) as List;
  for (final entry in entries.cast<Map<String, dynamic>>()) {
    final directory = await Directory(entry['directory'] as String).create();
    await File('${directory.path}/reservation.json')
        .writeAsString(entry['record'] as String, flush: true);
    await File('${directory.path}/audio.part').writeAsString('x', flush: true);
    if (entry['cover'] == true) {
      await File('${directory.path}/cover.part')
          .writeAsString('c', flush: true);
    }
  }
  await File(args[1]).writeAsString('held', flush: true);
  await stdin.first;
  // Bypass all cleanup: the OS must release this handle when the process exits.
  exit(73);
}
