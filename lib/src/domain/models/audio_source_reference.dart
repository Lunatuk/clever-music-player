/// A persisted local audio address. It does not grant access to the resource.
/// Storage strings remain compatible with existing absolute desktop paths.
sealed class AudioSourceReference {
  const AudioSourceReference();

  factory AudioSourceReference.fromStorage(String value) {
    if (isContentUriValue(value)) return ContentUriAudioSource(value);
    if (_isUriAddress(value)) {
      throw UnsupportedError('Неподдерживаемый тип источника музыки.');
    }
    return FileAudioSource(value);
  }

  static bool isContentUriValue(String value) =>
      value.toLowerCase().startsWith('content://');

  /// A path or the original content URI, without file/path normalization.
  String get storageValue;

  @override
  bool operator ==(Object other) =>
      other is AudioSourceReference &&
      other.runtimeType == runtimeType &&
      other.storageValue == storageValue;

  @override
  int get hashCode => Object.hash(runtimeType, storageValue);
}

final class FileAudioSource extends AudioSourceReference {
  factory FileAudioSource(String path) {
    if (path.isEmpty || path.contains('\u0000') || _isUriAddress(path)) {
      throw const FormatException('Файловый источник должен содержать путь.');
    }
    return FileAudioSource._(path);
  }

  const FileAudioSource._(this.path);
  final String path;
  @override
  String get storageValue => path;
}

final class ContentUriAudioSource extends AudioSourceReference {
  factory ContentUriAudioSource(String value) {
    if (_invalidUriCharacters.hasMatch(value) ||
        _invalidEscape.hasMatch(value)) {
      throw const FormatException(
          'Некорректное кодирование URI аудиоисточника.');
    }
    final Uri uri;
    try {
      uri = Uri.parse(value);
    } on FormatException {
      throw const FormatException('Некорректный URI аудиоисточника.');
    }
    if (uri.scheme != 'content' ||
        !uri.hasAuthority ||
        uri.authority.isEmpty ||
        uri.path.isEmpty ||
        value.contains('\u0000')) {
      throw const FormatException(
          'Ожидается content URI с провайдером и путём.');
    }
    return ContentUriAudioSource._(value, uri);
  }

  const ContentUriAudioSource._(this.storageValue, this.uri);
  @override
  final String storageValue;
  final Uri uri;
}

final _uriAddress = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://');
final _windowsDrivePath = RegExp(r'^[a-zA-Z]:[/\\]');
final _invalidUriCharacters = RegExp(r'[\x00-\x20\x7f]');
final _invalidEscape = RegExp(r'%(?![0-9a-fA-F]{2})');

bool _isUriAddress(String value) =>
    !_windowsDrivePath.hasMatch(value) && _uriAddress.hasMatch(value);
