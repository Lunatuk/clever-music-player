import 'dart:async';

import 'package:clever_music_player/src/android/audio_documents.dart';
import 'package:clever_music_player/src/domain/models/models.dart';
import 'package:clever_music_player/src/domain/repositories/settings_repository.dart';

final class TestAudioFolders
    implements AudioDocuments, AudioDocumentFolders, AudioDocumentFolderAccess {
  final first = ContentUriAudioSource('content://test.documents/tree/Music');
  final second = ContentUriAudioSource('content://test.documents/tree/Other');
  List<ContentUriAudioSource> grants = [];
  final inaccessible = <ContentUriAudioSource>{};
  final broken = <ContentUriAudioSource>{};
  final sessions = <int, ContentUriAudioSource>{};
  final opened = <ContentUriAudioSource>[];
  int grantReads = 0,
      picks = 0,
      opens = 0,
      closes = 0,
      metadataReads = 0,
      inspections = 0;
  int _next = 1;
  int count = 2;
  ContentUriAudioSource? picked;
  AudioDocumentSelection? selection;
  Future<List<ContentUriAudioSource>> Function()? listAction;
  Future<AudioFolderAccess> Function(ContentUriAudioSource)? inspectAction;
  Future<AudioDocumentMetadata> Function(ContentUriAudioSource)? readAction;
  Future<AudioFolderPage> Function(int)? pageAction;
  Future<ContentUriAudioSource?> Function()? pickAction;
  ContentUriAudioSource track(ContentUriAudioSource tree, int index) =>
      ContentUriAudioSource('${tree.storageValue}/document/song$index');
  @override
  Future<AudioDocumentSelection?> pickAudio() async => selection;
  @override
  Future<ContentUriAudioSource?> pickAudioFolder() async {
    picks++;
    return pickAction == null ? picked ?? first : await pickAction!();
  }

  @override
  Future<List<ContentUriAudioSource>> listAudioFolderGrants() async {
    grantReads++;
    return listAction == null ? grants : await listAction!();
  }

  @override
  Future<AudioFolderAccess> inspectAudioFolder(
      ContentUriAudioSource tree) async {
    inspections++;
    return inspectAction == null
        ? AudioFolderAccess(
            readable: !inaccessible.contains(tree),
            name: tree == first ? 'Музыка' : 'Другая папка')
        : await inspectAction!(tree);
  }

  @override
  Future<int> openAudioFolder(ContentUriAudioSource tree) async {
    if (inaccessible.contains(tree)) throw StateError('access lost');
    opens++;
    opened.add(tree);
    final id = _next++;
    sessions[id] = tree;
    return id;
  }

  @override
  Future<AudioFolderPage> readAudioFolderPage(int session) async {
    if (pageAction != null) return pageAction!(session);
    final tree = sessions[session]!;
    if (broken.contains(tree)) throw StateError('provider failed');
    return AudioFolderPage([for (var i = 0; i < count; i++) track(tree, i)],
        visited: count, done: true);
  }

  @override
  Future<void> closeAudioFolder(int session) async {
    closes++;
    sessions.remove(session);
  }

  @override
  Future<AudioDocumentMetadata> readAudio(ContentUriAudioSource source) async {
    metadataReads++;
    return readAction == null
        ? const AudioDocumentMetadata(title: 'Song')
        : await readAction!(source);
  }
}

final class TestFolderSettings implements SettingsRepository {
  final values = <String, String>{};
  int reads = 0, writes = 0;
  Future<String?> Function(String)? readAction;
  Future<void> Function(String, String)? writeAction;
  @override
  Future<String?> readString(String key) async {
    reads++;
    return readAction == null ? values[key] : await readAction!(key);
  }

  @override
  Future<void> writeString(String key, String value) async {
    writes++;
    await writeAction?.call(key, value);
    values[key] = value;
  }

  @override
  Future<AppSetting?> read(String key) async {
    final value = await readString(key);
    return value == null
        ? null
        : AppSetting(key: key, value: value, updatedAt: DateTime(2026));
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
