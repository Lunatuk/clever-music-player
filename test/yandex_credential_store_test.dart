import 'dart:convert';
import 'dart:io';

import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/library_sync/yandex_credential_store.dart';
import 'package:clever_music_player/src/library_sync/yandex_library_protocol.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage_windows/flutter_secure_storage_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/windows_read_lock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secret = 'synthetic-native-secret-38-abcdefghijklmnopqrstuvwxyz';
  final account = RemoteLibraryAccount(
      id: 42,
      identity:
          RemoteAccountIdentity(provider: 'yandex_music', accountId: '101'),
      displayName: 'Music',
      isActive: true,
      revision: 3);
  final record =
      YandexSavedCredential(account: account, token: YandexAccessToken(secret));
  test(
      'protected envelope roundtrip retains binding, public debug text is redacted',
      () {
    final decoded = YandexSavedCredential.decode(record.encode());
    expect(decoded.matches(account), isTrue);
    expect(decoded.encode(), record.encode());
    expect(record.toString(), isNot(contains(secret)));
    expect(record.token.toString(), isNot(contains(secret)));
  });
  for (final input in [
    '{}',
    '[]',
    '{broken',
    record.encode().replaceFirst('"revision":3', '"revision":0'),
    record.encode().replaceFirst('"version":1', '"version":2'),
    '${record.encode()} '
  ]) {
    test('invalid credential record sanitized: ${input.length}', () {
      try {
        YandexSavedCredential.decode(input);
        fail('Must reject');
      } on YandexCredentialException catch (error) {
        expect(error.toString(), 'YandexCredentialException(storage)');
      }
    });
  }
  test('raw token and documented callback URL normalize to the same token', () {
    final values = [
      '  $secret  ',
      'https://music.yandex.ru/#access_token=$secret&token_type=bearer&expires_in=100'
    ];
    for (final input in values) {
      String? header;
      parseYandexTokenInput(input).authorize((value) => header = value);
      expect(header, 'OAuth $secret');
    }
  });
  for (final input in [
    'https://evil.test/#access_token=$secret',
    'https://user@music.yandex.ru/#access_token=$secret',
    'https://music.yandex.ru/?access_token=$secret',
    'https://music.yandex.ru/#access_token=a&access_token=b',
    'http://music.yandex.ru/#access_token=$secret',
    'secret\nInjected: value',
    ''
  ]) {
    test('invalid token input exposes no source text: ${input.length}', () {
      try {
        parseYandexTokenInput(input);
        fail('Must reject');
      } on ArgumentError catch (error) {
        expect(error.toString(), isNot(contains(secret)));
      }
    });
  }

  group('actual Windows DPAPI backend', () {
    late Directory root;
    late PathProviderPlatform originalPaths;
    TargetPlatform? originalTarget;
    const store = SecureYandexCredentialStore();
    setUp(() async {
      root =
          await Directory.systemTemp.createTemp('cmp_credentials_Музыка test_');
      originalPaths = PathProviderPlatform.instance;
      originalTarget = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      PathProviderPlatform.instance = _Paths(root.path);
      FlutterSecureStorageWindows.registerWith();
    });
    tearDown(() async {
      PathProviderPlatform.instance = originalPaths;
      debugDefaultTargetPlatformOverride = originalTarget;
      final resolved = await root.resolveSymbolicLinks();
      expect(resolved, root.absolute.path);
      await root.delete(
          recursive:
              true); // Exclusively created fixture, checked absolute target.
    });
    test('read absent key creates no file or plaintext fallback', () async {
      expect(await store.read(), isNull);
      expect(await root.list().length, 0);
    });
    test('write/read with fresh backend uses ciphertext on disk', () async {
      await store.write(record);
      final files = (await root.list().toList()).whereType<File>().toList();
      expect(files, hasLength(1));
      final bytes = await files.single.readAsBytes();
      expect(latin1.decode(bytes), isNot(contains(secret)));
      expect(latin1.decode(bytes),
          isNot(contains(SecureYandexCredentialStore.key)));
      FlutterSecureStorageWindows
          .registerWith(); // Fresh native backend, reads the persisted DPAPI file.
      expect((await store.read())!.encode(), record.encode());
    });
    test('update/delete preserve unrelated protected key', () async {
      const backend = FlutterSecureStorage(
          wOptions: WindowsOptions(useBackwardCompatibility: false));
      await backend.write(key: 'fixture_sibling', value: 'keep');
      await store.write(record);
      await store.delete();
      expect(await store.read(), isNull);
      expect(await backend.read(key: 'fixture_sibling'), 'keep');
    });
    test('damaged ciphertext raises a sanitized failure without deleting it',
        () async {
      await store.write(record);
      final file = (await root.list().toList()).whereType<File>().single;
      await file.writeAsBytes([1, 2, 3, 4], flush: true);
      await expectLater(
          store.read(), throwsA(isA<YandexCredentialException>()));
      expect(await file.readAsBytes(), [1, 2, 3, 4]);
    });
    test('unwritable destination never stores plaintext elsewhere', () async {
      final sentinel = File('${root.path}${Platform.pathSeparator}sentinel');
      await sentinel.writeAsString('keep');
      PathProviderPlatform.instance = _Paths(sentinel.path);
      await expectLater(
          store.write(record), throwsA(isA<YandexCredentialException>()));
      expect(await sentinel.readAsString(), 'keep');
      expect(await root.list().length, 1);
    });
    test('failed atomic replacement preserves the previous protected record',
        () async {
      await store.write(record);
      final file = (await root.list().toList()).whereType<File>().single;
      final original = await file.readAsBytes();
      final unlock = lockAgainstReplacement(file);
      try {
        await expectLater(
            store.write(YandexSavedCredential(
                account: account,
                token: YandexAccessToken('different-synthetic-token'))),
            throwsA(isA<YandexCredentialException>()));
      } finally {
        unlock();
      }
      expect(await file.readAsBytes(), original);
      expect((await store.read())!.encode(), record.encode());
      expect(await root.list().length, 1);
    });
  }, skip: Platform.isWindows ? false : 'Native DPAPI requires Windows');
}

final class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}
