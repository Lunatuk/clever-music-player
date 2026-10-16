import '../models/publication_cleanup.dart';

abstract interface class PublicationRetentionRepository {
  /// Writer reservation before reading current terminal job/folder/asset.
  /// action must be short and bounded, with the OS resource lock already held.
  /// null preserves the journal (including any result still needing recovery).
  Future<T?> withCleanupAuthority<T extends Object>(
      PublicationCleanupRequest request,
      {required DateTime notUpdatedAfter,
      required DateTime Function() clock,
      required Future<T> Function(String destinationPath) action});
}
