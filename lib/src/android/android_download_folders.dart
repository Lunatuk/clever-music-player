import 'package:flutter/services.dart';

import '../domain/models/audio_source_reference.dart';
import 'audio_documents.dart';

final class DownloadFolderAccess {
  const DownloadFolderAccess(
      {required this.readable,
      required this.writable,
      required this.canCreate,
      this.name});
  final bool readable, writable, canCreate;
  final String? name;
  bool get usable => readable && writable && canCreate;
}

/// This does not register a library root or write any document in the tree.
abstract interface class DownloadFolderDocuments {
  Future<ContentUriAudioSource?> pickDownloadFolder();
  Future<DownloadFolderAccess> inspectDownloadFolder(
      ContentUriAudioSource tree);
}

final class AndroidDownloadFolders implements DownloadFolderDocuments {
  const AndroidDownloadFolders({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel(
                'dev.lunatuk.clever_music_player/audio_documents');
  final MethodChannel _channel;

  static ContentUriAudioSource parseTree(String value) {
    if (value.length > 8192) throw const FormatException('Некорректная папка.');
    final tree = ContentUriAudioSource(value);
    if (!isAudioFolderUri(tree) || tree.uri.hasQuery || tree.uri.hasFragment) {
      throw const FormatException('Некорректная папка.');
    }
    return tree;
  }

  @override
  Future<ContentUriAudioSource?> pickDownloadFolder() async {
    final data =
        await _channel.invokeMapMethod<String, Object?>('pickDownloadFolder');
    if (data == null) return null;
    final uri = data['uri'];
    if (uri is! String) throw const FormatException('Некорректная папка.');
    return parseTree(uri);
  }

  @override
  Future<DownloadFolderAccess> inspectDownloadFolder(
      ContentUriAudioSource tree) async {
    parseTree(tree.storageValue);
    final data = await _channel.invokeMapMethod<String, Object?>(
        'inspectDownloadFolder', {'uri': tree.storageValue});
    final readable = data?['readable'],
        writable = data?['writable'],
        canCreate = data?['canCreate'],
        name = data?['name'];
    if (readable is! bool ||
        writable is! bool ||
        canCreate is! bool ||
        (name != null && (name is! String || name.length > 256))) {
      throw const FormatException('Некорректный доступ к папке.');
    }
    return DownloadFolderAccess(
        readable: readable,
        writable: writable,
        canCreate: canCreate,
        name: name is String && name.trim().isNotEmpty ? name.trim() : null);
  }
}
