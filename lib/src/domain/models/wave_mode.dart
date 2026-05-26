enum WaveMode {
  balanced,
  discovery,
  focus,
  favorites,
  deepCuts;

  String get storageKey => switch (this) {
        WaveMode.balanced => 'balanced',
        WaveMode.discovery => 'discovery',
        WaveMode.focus => 'focus',
        WaveMode.favorites => 'favorites',
        WaveMode.deepCuts => 'deep_cuts',
      };

  String get label => switch (this) {
        WaveMode.balanced => 'Сбалансированный',
        WaveMode.discovery => 'Открытия',
        WaveMode.focus => 'Фокус',
        WaveMode.favorites => 'Любимое',
        WaveMode.deepCuts => 'Редкое',
      };

  static WaveMode fromStorageKey(String? value) {
    return WaveMode.values.firstWhere(
      (mode) => mode.storageKey == value,
      orElse: () => WaveMode.balanced,
    );
  }
}
