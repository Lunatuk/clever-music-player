import 'audio_source_reference.dart';

/// DocumentsContract identity. A tree selects an access grant, not another
/// document. IDs remain opaque: no filesystem/path/title matching is valid.
typedef AudioDocumentIdentity = ({String authority, String documentId});

AudioDocumentIdentity? audioDocumentIdentity(String address) {
  if (!AudioSourceReference.isContentUriValue(address)) return null;
  try {
    final uri = ContentUriAudioSource(address).uri;
    if (uri.hasQuery || uri.hasFragment) return null;
    final parts = uri.pathSegments;
    final String id;
    if (parts.length == 4 &&
        parts[0] == 'tree' &&
        parts[1].isNotEmpty &&
        parts[2] == 'document') {
      id = parts[3];
    } else if (parts.length == 2 && parts[0] == 'document') {
      id = parts[1];
    } else {
      return null;
    }
    if (id.isEmpty || id.contains('\u0000')) return null;
    return (authority: uri.authority, documentId: id);
  } on FormatException {
    return null;
  }
}
