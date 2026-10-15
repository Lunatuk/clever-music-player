import 'external_track_ref.dart';

/// An opaque provider account ID, never an access token or a login credential.
final class RemoteAccountIdentity {
  factory RemoteAccountIdentity(
      {required String provider, required String accountId}) {
    if (_providerPattern.stringMatch(provider) != provider) {
      throw const FormatException('Некорректный провайдер.');
    }
    _validateText(accountId);
    return RemoteAccountIdentity._(provider, accountId);
  }
  const RemoteAccountIdentity._(this.provider, this.accountId);
  final String provider, accountId;
  @override
  bool operator ==(Object other) =>
      other is RemoteAccountIdentity &&
      provider == other.provider &&
      accountId == other.accountId;
  @override
  int get hashCode => Object.hash(provider, accountId);
}

/// Active means selected for synchronization; it does not prove authorization.
/// Every activation/disconnection changes the revision and invalidates old work.
final class RemoteLibraryAccount {
  const RemoteLibraryAccount(
      {required this.id,
      required this.identity,
      required this.displayName,
      required this.isActive,
      required this.revision});
  final int id, revision;
  final RemoteAccountIdentity identity;
  final String? displayName;
  final bool isActive;
  @override
  bool operator ==(Object other) =>
      other is RemoteLibraryAccount &&
      id == other.id &&
      identity == other.identity &&
      displayName == other.displayName &&
      isActive == other.isActive &&
      revision == other.revision;
  @override
  int get hashCode =>
      Object.hash(id, identity, displayName, isActive, revision);
}

enum RemoteCollectionKind { liked, playlist }

/// Owner/context distinguishes playlist IDs which are only unique per owner.
final class RemoteCollectionKey {
  factory RemoteCollectionKey(
      {required RemoteCollectionKind kind,
      String externalId = '',
      String ownerId = ''}) {
    if (kind == RemoteCollectionKind.liked) {
      if (externalId.isNotEmpty || ownerId.isNotEmpty) {
        throw const FormatException('Избранное принадлежит самому аккаунту.');
      }
    } else {
      _validateText(externalId);
      if (ownerId.isNotEmpty) _validateText(ownerId);
    }
    return RemoteCollectionKey._(kind, externalId, ownerId);
  }
  const RemoteCollectionKey._(this.kind, this.externalId, this.ownerId);
  final RemoteCollectionKind kind;
  final String externalId, ownerId;
  @override
  bool operator ==(Object other) =>
      other is RemoteCollectionKey &&
      kind == other.kind &&
      externalId == other.externalId &&
      ownerId == other.ownerId;
  @override
  int get hashCode => Object.hash(kind, externalId, ownerId);
}

/// Configuration plus the last successful remote snapshot, not a local playlist.
final class RemoteLibraryCollection {
  const RemoteLibraryCollection(
      {required this.id,
      required this.account,
      required this.key,
      required this.title,
      required this.isSelected,
      required this.revision,
      required this.itemCount,
      required this.remoteRevision,
      required this.completedAt});
  final int id, revision, itemCount;
  final RemoteAccountIdentity account;
  final RemoteCollectionKey key;
  final String? title, remoteRevision;
  final bool isSelected;
  final DateTime? completedAt;
  @override
  bool operator ==(Object other) =>
      other is RemoteLibraryCollection &&
      id == other.id &&
      account == other.account &&
      key == other.key &&
      title == other.title &&
      isSelected == other.isSelected &&
      revision == other.revision &&
      itemCount == other.itemCount &&
      remoteRevision == other.remoteRevision &&
      completedAt == other.completedAt;
  @override
  int get hashCode => Object.hash(id, account, key, title, isSelected, revision,
      itemCount, remoteRevision, completedAt);
}

/// A persisted revision must be acquired before reading the first remote page.
final class RemoteCollectionRefresh {
  const RemoteCollectionRefresh(
      {required this.account, required this.collection});
  final RemoteLibraryAccount account;
  final RemoteLibraryCollection collection;
}

/// The adapter must affirm that every page was fetched successfully.
/// Count/revision checks provide additional guards when the provider has them.
/// Repeated tracks and their original order are intentionally preserved.
final class RemoteCollectionSnapshot {
  factory RemoteCollectionSnapshot(
      {required Iterable<ExternalTrackIdentity> items,
      required bool isComplete,
      required DateTime completedAt,
      int? expectedItemCount,
      String? revisionAtStart,
      String? revisionAtEnd}) {
    if (expectedItemCount != null && expectedItemCount < 0) {
      throw ArgumentError('Некорректный размер коллекции.');
    }
    for (final revision in [revisionAtStart, revisionAtEnd]) {
      if (revision != null) _validateText(revision);
    }
    final copy = <ExternalTrackIdentity>[];
    for (final item in items) {
      if (copy.length == maxItems) {
        throw ArgumentError('Коллекция слишком велика для одного снимка.');
      }
      copy.add(item);
    }
    return RemoteCollectionSnapshot._(List.unmodifiable(copy), isComplete,
        completedAt.toUtc(), expectedItemCount, revisionAtStart, revisionAtEnd);
  }
  const RemoteCollectionSnapshot._(
      this.items,
      this.isComplete,
      this.completedAt,
      this.expectedItemCount,
      this.revisionAtStart,
      this.revisionAtEnd);
  static const maxItems = 100000;
  final List<ExternalTrackIdentity> items;
  final bool isComplete;
  final DateTime completedAt;
  final int? expectedItemCount;
  final String? revisionAtStart, revisionAtEnd;
  bool get canCommit =>
      isComplete &&
      (expectedItemCount == null || expectedItemCount == items.length) &&
      revisionAtStart == revisionAtEnd;
}

final class RemoteCollectionContent {
  RemoteCollectionContent(
      {required this.collection,
      required Iterable<ExternalTrackIdentity> items})
      : items = List.unmodifiable(items);
  final RemoteLibraryCollection collection;
  final List<ExternalTrackIdentity> items;
}

void validateRemoteDisplayName(String? value) {
  if (value != null) _validateText(value);
}

final _providerPattern = RegExp(r'^[a-z][a-z0-9._-]{0,63}$');
void _validateText(String value) {
  if (value.trim().isEmpty ||
      value.length > 512 ||
      value.runes.any((rune) => rune < 32 || rune == 127)) {
    throw const FormatException('Некорректное внешнее обозначение.');
  }
}
