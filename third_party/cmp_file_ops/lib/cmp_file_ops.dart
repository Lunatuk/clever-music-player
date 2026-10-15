import 'dart:ffi';

// C captures GetLastError/errno BEFORE returning through the Dart VM.
@Native<Int32 Function(Pointer<Void>)>(symbol: 'cmp_mkdir')
external int cmpMkdir(Pointer<Void> path);

@Native<Int32 Function(Pointer<Void>, Int32, Pointer<IntPtr>)>(
  symbol: 'cmp_lock',
)
external int cmpLock(Pointer<Void> path, int seal, Pointer<IntPtr> handle);

@Native<Int32 Function(IntPtr)>(symbol: 'cmp_close')
external int cmpClose(int handle);

@Native<Int32 Function(Pointer<Void>, Pointer<Void>)>(symbol: 'cmp_move')
external int cmpMove(Pointer<Void> source, Pointer<Void> destination);
