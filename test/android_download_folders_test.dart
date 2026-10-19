import 'package:clever_music_player/src/android/android_download_folders.dart';
import 'package:clever_music_player/src/domain/models/audio_source_reference.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel =
      MethodChannel('dev.lunatuk.clever_music_player/audio_documents');
  const adapter = AndroidDownloadFolders(channel: channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final tree = ContentUriAudioSource(
      'content://music.documents/tree/primary%3A%D0%9C%D1%83%D0%B7%D1%8B%D0%BA%D0%B0');
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('download picker uses separate capability and preserves the exact URI',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickDownloadFolder');
      return {'uri': tree.storageValue};
    });
    expect(await adapter.pickDownloadFolder(), tree);
  });
  test('picker cancellation does not fabricate a destination', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await adapter.pickDownloadFolder(), isNull);
  });
  test('read-only, write-only and no-create providers are not usable',
      () async {
    for (var bits = 0; bits < 8; bits++) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'inspectDownloadFolder');
        expect(call.arguments, {'uri': tree.storageValue});
        return {
          'readable': bits & 1 != 0,
          'writable': bits & 2 != 0,
          'canCreate': bits & 4 != 0,
          'name': ' Музыка '
        };
      });
      final access = await adapter.inspectDownloadFolder(tree);
      expect(access.usable, bits == 7);
      expect(access.name, 'Музыка');
    }
  });
  test('malformed native capability results fail closed', () async {
    for (final value in [
      null,
      <String, Object>{},
      {'readable': true, 'writable': true, 'canCreate': 1},
      {'readable': true, 'writable': true, 'canCreate': true, 'name': 'x' * 257}
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      await expectLater(
          adapter.inspectDownloadFolder(tree), throwsFormatException);
    }
  });
  test(
      'non-tree, decorated, oversized and remote addresses never reach native code',
      () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return null;
    });
    for (final value in [
      'https://example.org/tree/x',
      'content://music.documents/document/x',
      'content://music.documents/tree/x/document/y',
      'content://music.documents/tree/x?key=1',
      'content://music.documents/tree/x#fragment',
      'content://music.documents/tree/${'x' * 8192}'
    ]) {
      expect(
          () => AndroidDownloadFolders.parseTree(value), throwsFormatException);
    }
    await expectLater(
        adapter.inspectDownloadFolder(
            ContentUriAudioSource('content://music.documents/document/x')),
        throwsFormatException);
    expect(calls, 0);
  });
  test('picker rejects invalid returned data', () async {
    for (final value in [
      <String, Object>{},
      {'uri': 42},
      {'uri': 'content://music.documents/document/x'}
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      await expectLater(adapter.pickDownloadFolder(), throwsFormatException);
    }
  });
}
