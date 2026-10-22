import 'package:path/path.dart' as p;

import 'audio_source_reference.dart';

/// Provider evidence, obtained by checking direct parent membership and name.
/// URI shape alone cannot establish membership (document IDs are opaque).
final class DocumentPublicationLocation {
  DocumentPublicationLocation(
      {required this.tree, required this.document, required this.displayName}) {
    final root = tree.uri, source = document.uri;
    final roots = root.pathSegments, parts = source.pathSegments;
    if (tree.storageValue.length > 8192 ||
        document.storageValue.length > 8192 ||
        root.hasQuery ||
        root.hasFragment ||
        source.hasQuery ||
        source.hasFragment ||
        roots.length != 2 ||
        roots[0] != 'tree' ||
        roots[1].isEmpty ||
        parts.length != 4 ||
        parts[0] != 'tree' ||
        parts[2] != 'document' ||
        parts[1] != roots[1] ||
        parts[3].isEmpty ||
        parts[3] == roots[1] ||
        root.authority != source.authority ||
        [...roots, ...parts].any((s) => s.contains('\u0000')) ||
        displayName.isEmpty ||
        displayName.length > 255 ||
        displayName.contains('/') ||
        displayName.contains('\\') ||
        displayName.runes.any((r) => r < 32 || r == 127)) {
      throw const FormatException('Некорректное назначение документа.');
    }
  }
  final ContentUriAudioSource tree, document;
  final String displayName;
}

/// This binds provider evidence to the current persisted destination. Physical
/// membership/hash verification happens outside the short SQLite transaction.
bool publicationSourceMatchesDestination({
  required AudioSourceReference source,
  required String destination,
  required String fileName,
  DocumentPublicationLocation? documentLocation,
}) {
  if (source is ContentUriAudioSource) {
    return documentLocation != null &&
        documentLocation.tree.storageValue == destination &&
        documentLocation.document == source &&
        documentLocation.displayName == fileName;
  }
  if (source is! FileAudioSource ||
      documentLocation != null ||
      AudioSourceReference.isContentUriValue(destination)) {
    return false;
  }
  return source.path == p.normalize(p.absolute(p.join(destination, fileName)));
}
