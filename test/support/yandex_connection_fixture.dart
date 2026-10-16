import 'package:clever_music_player/src/library_sync/yandex_credential_store.dart';

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
