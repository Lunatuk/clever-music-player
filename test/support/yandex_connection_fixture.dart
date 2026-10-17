import 'package:clever_music_player/src/library_sync/yandex_credential_store.dart';
import 'package:clever_music_player/src/library/library_scan_control.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';

final class FakeYandexProbe implements YandexConnectionProbe {
  int calls = 0;
  bool closed = false;
  Future<void> Function(LibraryScanControl)? onProbe;
  @override
  Future<void> probe(LibraryScanControl control) async {
    calls++;
    control.throwIfCancelled();
    await onProbe?.call(control);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

final class MemoryYandexCredentials implements YandexCredentialStore {
  YandexSavedCredential? value;
  bool failRead = false,
      failWrite = false,
      failDelete = false,
      writeThenFail = false;
  int reads = 0, writes = 0, deletes = 0;
  Future<void> Function()? onWrite;
  @override
  Future<YandexSavedCredential?> read() async {
    reads++;
    if (failRead) throw const YandexCredentialException();
    return value;
  }

  @override
  Future<void> write(YandexSavedCredential credential) async {
    writes++;
    await onWrite?.call();
    if (failWrite) throw const YandexCredentialException();
    value = YandexSavedCredential.decode(credential.encode());
    if (writeThenFail) throw const YandexCredentialException();
  }

  @override
  Future<void> delete() async {
    deletes++;
    if (failDelete) throw const YandexCredentialException();
    value = null;
  }
}
