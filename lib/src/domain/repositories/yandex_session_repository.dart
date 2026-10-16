import '../models/remote_library.dart';

/// No secret enters SQLite. Only the small OS credential operation runs inside
/// the writer fence; all authentication/network work must finish beforehand.
abstract interface class YandexSessionRepository {
  Future<List<RemoteLibraryAccount>> capture();
  Future<RemoteLibraryAccount?> connect(
      List<RemoteLibraryAccount> expected, RemoteAccountIdentity identity,
      {String? displayName,
      required Future<void> Function(RemoteLibraryAccount account) persist});
  Future<bool> disconnect(List<RemoteLibraryAccount> expected,
      {required Future<void> Function() forget});
}
