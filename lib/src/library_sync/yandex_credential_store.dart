import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/models/remote_library.dart';
import 'yandex_library_protocol.dart';

final class YandexCredentialException implements Exception {
  const YandexCredentialException();
  @override
  String toString() => 'YandexCredentialException(storage)';
}

/// Only the protected store receives encode(); never Settings, DB or diagnostics.
final class YandexSavedCredential {
  const YandexSavedCredential({required this.account, required this.token});
  final RemoteLibraryAccount account;
  final YandexAccessToken token;
  String encode() {
    if (!account.isActive ||
        account.id <= 0 ||
        account.revision <= 0 ||
        account.identity.provider != 'yandex_music') {
      throw const YandexCredentialException();
    }
    yandexNumericId(account.identity.accountId);
    String? raw;
    token.authorize((header) => raw = header.substring(6));
    return jsonEncode({
      'version': 1,
      'id': account.id,
      'uid': account.identity.accountId,
      'revision': account.revision,
      'token': raw
    });
  }

  static YandexSavedCredential decode(String value) {
    try {
      if (utf8.encode(value).length > 16384) throw const FormatException();
      final map = jsonDecode(value) as Map<String, dynamic>;
      final id = map['id'] as int, revision = map['revision'] as int;
      if (id <= 0 || revision <= 0) throw const FormatException();
      final record = YandexSavedCredential(
          account: RemoteLibraryAccount(
              id: id,
              identity: RemoteAccountIdentity(
                  provider: 'yandex_music',
                  accountId: yandexNumericId(map['uid'])),
              displayName: null,
              isActive: true,
              revision: revision),
          token: YandexAccessToken(map['token'] as String));
      if (record.encode() != value) throw const FormatException();
      return record;
    } on Object {
      throw const YandexCredentialException();
    }
  }

  bool matches(RemoteLibraryAccount current) =>
      current.isActive &&
      current.id == account.id &&
      current.identity == account.identity &&
      current.revision == account.revision;
  @override
  String toString() => 'YandexSavedCredential(<redacted>)';
}

abstract interface class YandexCredentialStore {
  Future<YandexSavedCredential?> read();
  Future<void> write(YandexSavedCredential credential);
  Future<void> delete();
}

/// One namespaced key. Never readAll/deleteAll, plaintext fallback or migration
/// from YaDown config. Creation does not touch the OS store.
final class SecureYandexCredentialStore implements YandexCredentialStore {
  const SecureYandexCredentialStore(
      {FlutterSecureStorage storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(
              resetOnError: false,
              storageNamespace: 'clever_music_player_yandex_v1'),
          mOptions: MacOsOptions(
              accountName: 'CleverMusicPlayer.Yandex',
              synchronizable: false,
              usesDataProtectionKeychain: false),
          wOptions: WindowsOptions(useBackwardCompatibility: false))})
      : _storage = storage;
  static const key = 'clever_music_player.yandex.session.v1';
  final FlutterSecureStorage _storage;
  @override
  Future<YandexSavedCredential?> read() async {
    try {
      final value = await _storage.read(key: key);
      return value == null ? null : YandexSavedCredential.decode(value);
    } on Object {
      throw const YandexCredentialException();
    }
  }

  @override
  Future<void> write(YandexSavedCredential credential) async {
    try {
      final value = credential.encode();
      await _storage.write(key: key, value: value);
      if (await _storage.read(key: key) != value) {
        throw const YandexCredentialException();
      }
    } on Object {
      throw const YandexCredentialException();
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: key);
      if (await _storage.read(key: key) != null) {
        throw const YandexCredentialException();
      }
    } on Object {
      throw const YandexCredentialException();
    }
  }
}

/// Accept an existing token or the documented browser redirect, never arbitrary
/// URLs/query strings. The URL itself is not persisted or displayed again.
YandexAccessToken parseYandexTokenInput(String input) {
  try {
    return _parseToken(input);
  } on Object {
    throw ArgumentError('Некорректный токен или адрес.');
  }
}

YandexAccessToken _parseToken(String input) {
  final value = input.trim();
  if (value.length > 16384) throw ArgumentError('Некорректный токен.');
  if (value.startsWith('https://')) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host != 'music.yandex.ru' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.port != 443 ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw ArgumentError('Некорректный адрес токена.');
    }
    final params = Uri(query: uri.fragment).queryParametersAll;
    final token = params['access_token'];
    if (token == null || token.length != 1) {
      throw ArgumentError('Токен не найден.');
    }
    return YandexAccessToken(token.single);
  }
  if (value.contains('://')) throw ArgumentError('Некорректный адрес.');
  return YandexAccessToken(value);
}
