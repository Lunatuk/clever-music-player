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
        WaveMode.balanced => 'Balanced',
        WaveMode.discovery => 'Discovery',
        WaveMode.focus => 'Focus',
        WaveMode.favorites => 'Favorites',
        WaveMode.deepCuts => 'Deep cuts',
      };

  static WaveMode fromStorageKey(String? value) {
    return WaveMode.values.firstWhere(
      (mode) => mode.storageKey == value,
      orElse: () => WaveMode.balanced,
    );
  }
}
