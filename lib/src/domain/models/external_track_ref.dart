/// Provider identity is independent from titles, file paths and local IDs.
/// The adapter defines [variantKey] (for example an album/version ID); an empty
/// value means no such context. IDs are opaque and retain case/leading zeros.
final class ExternalTrackIdentity {
  factory ExternalTrackIdentity({
    required String provider,
    required String externalId,
    String variantKey = '',
  }) {
    if (_providerPattern.stringMatch(provider) != provider) {
      throw const FormatException('Некорректное имя музыкального провайдера.');
    }
    _validateId(externalId, allowEmpty: false);
    _validateId(variantKey, allowEmpty: true);
    return ExternalTrackIdentity._(provider, externalId, variantKey);
  }

  const ExternalTrackIdentity._(
      this.provider, this.externalId, this.variantKey);
  final String provider, externalId, variantKey;

  @override
  bool operator ==(Object other) =>
      other is ExternalTrackIdentity &&
      provider == other.provider &&
      externalId == other.externalId &&
      variantKey == other.variantKey;
  @override
  int get hashCode => Object.hash(provider, externalId, variantKey);
}

enum ExternalTrackRefOrigin {
  embeddedTag,
  providerResponse,
  manual;

  String get storageKey => name;
  int get priority => switch (this) {
        embeddedTag => 1,
        providerResponse => 2,
        manual => 3,
      };
  static ExternalTrackRefOrigin fromStorageKey(String key) =>
      values.firstWhere((value) => value.storageKey == key,
          orElse: () =>
              throw const FormatException('Неизвестное происхождение ID.'));
}

/// A confirmed association, not proof that audio was downloaded or verified.
/// Several independent local copies may refer to the same external identity.
final class ExternalTrackRef {
  factory ExternalTrackRef({
    required int trackId,
    required ExternalTrackIdentity identity,
    required ExternalTrackRefOrigin origin,
    required DateTime linkedAt,
  }) {
    if (trackId <= 0) throw ArgumentError('Требуется сохранённый ID трека.');
    return ExternalTrackRef._(trackId, identity, origin, linkedAt.toUtc());
  }
  const ExternalTrackRef._(
      this.trackId, this.identity, this.origin, this.linkedAt);
  final int trackId;
  final ExternalTrackIdentity identity;
  final ExternalTrackRefOrigin origin;
  final DateTime linkedAt;

  @override
  bool operator ==(Object other) =>
      other is ExternalTrackRef &&
      trackId == other.trackId &&
      identity == other.identity &&
      origin == other.origin &&
      linkedAt == other.linkedAt;
  @override
  int get hashCode => Object.hash(trackId, identity, origin, linkedAt);
}

final _providerPattern = RegExp(r'^[a-z][a-z0-9._-]{0,63}$');
void _validateId(String value, {required bool allowEmpty}) {
  if (allowEmpty && value.isEmpty) return;
  if (value.trim().isEmpty ||
      value.length > 512 ||
      value.runes.any((rune) => rune < 32 || rune == 127)) {
    throw const FormatException('Некорректный внешний ID трека.');
  }
}
