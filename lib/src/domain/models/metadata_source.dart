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
      MetadataSource.embeddedTags => 'tags',
      MetadataSource.filename => 'filename',
      MetadataSource.fallback => 'fallback',
      MetadataSource.manual => 'manual',
      MetadataSource.acousticFingerprint => 'fingerprint',
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
