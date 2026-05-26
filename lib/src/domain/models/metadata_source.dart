enum MetadataSource {
  embeddedTags('embeddedTags'),
  filename('filename'),
  fallback('fallback'),
  manual('manual'),
  acousticFingerprint('acousticFingerprint');

  const MetadataSource(this.storageKey);

  final String storageKey;

  String get displayLabel {
    return switch (this) {
      MetadataSource.embeddedTags => 'теги',
      MetadataSource.filename => 'имя файла',
      MetadataSource.fallback => 'резерв',
      MetadataSource.manual => 'вручную',
      MetadataSource.acousticFingerprint => 'отпечаток',
    };
  }

  static MetadataSource? fromStorageKey(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    for (final source in MetadataSource.values) {
      if (source.storageKey == value) {
        return source;
      }
    }

    return null;
  }
}
