import '../models/remote_library.dart';

abstract interface class RemoteLibraryRepository {
  /// Call after selecting an authorized account. No secrets are stored here.
  /// Repeated activation also invalidates work from the previous session.
  Future<RemoteLibraryAccount> activateAccount(RemoteAccountIdentity identity,
      {String? displayName});
  Future<RemoteLibraryAccount?> findAccount(RemoteAccountIdentity identity);
  Future<List<RemoteLibraryAccount>> listAccounts();
  Future<bool> disconnectAccount(RemoteLibraryAccount expected);

  /// Null means the account snapshot is no longer active/current.
  Future<RemoteLibraryCollection?> configureCollection(
      RemoteLibraryAccount account, RemoteCollectionKey key,
      {String? title, required bool isSelected});
  Future<List<RemoteLibraryCollection>> listCollections(
      RemoteAccountIdentity account,
      {bool selectedOnly = false});
  Future<RemoteCollectionContent?> readContent(
      RemoteAccountIdentity account, RemoteCollectionKey key);

  /// Acquire before requesting pages; a new refresh invalidates older ones.
  Future<RemoteCollectionRefresh?> beginRefresh(
      RemoteLibraryAccount account, RemoteLibraryCollection collection);

  /// Partial/inconsistent/stale results return false and preserve old content.
  Future<bool> commitSnapshot(
      RemoteCollectionRefresh refresh, RemoteCollectionSnapshot snapshot);
}
