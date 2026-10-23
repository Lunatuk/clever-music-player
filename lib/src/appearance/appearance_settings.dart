import 'dart:convert';

enum AppearanceMode { system, light, dark }

enum AppearanceMotion { off, slow, normal, fast }

/// Portable preferences, independent of Flutter widgets and platform storage.
/// New visual options belong here instead of being hard-coded in each screen.
final class AppearanceSettings {
  const AppearanceSettings({
    this.mode = AppearanceMode.dark,
    this.accentRgb = 0xffcc33,
    this.motion = AppearanceMotion.normal,
    this.compact = false,
    this.coverRadius = 8,
  });
  static const storageKey = 'appearance.v1';
  final AppearanceMode mode;
  final int accentRgb;
  final AppearanceMotion motion;
  final bool compact;
  final int coverRadius;

  AppearanceSettings copyWith({
    AppearanceMode? mode,
    int? accentRgb,
    AppearanceMotion? motion,
    bool? compact,
    int? coverRadius,
  }) =>
      AppearanceSettings(
          mode: mode ?? this.mode,
          accentRgb: (accentRgb ?? this.accentRgb).clamp(0, 0xffffff),
          motion: motion ?? this.motion,
          compact: compact ?? this.compact,
          coverRadius: (coverRadius ?? this.coverRadius).clamp(0, 24));

  String encode() => jsonEncode({
        'version': 1,
        'mode': mode.name,
        'accentRgb': accentRgb,
        'motion': motion.name,
        'compact': compact,
        'coverRadius': coverRadius,
      });

  static AppearanceSettings decode(String? raw) {
    const defaults = AppearanceSettings();
    if (raw == null || raw.length > 4096) return defaults;
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['version'] != 1) return defaults;
      T enumValue<T extends Enum>(List<T> values, Object? name, T fallback) =>
          values.where((v) => v.name == name).firstOrNull ?? fallback;
      return defaults.copyWith(
          mode: enumValue(AppearanceMode.values, data['mode'], defaults.mode),
          motion: enumValue(
              AppearanceMotion.values, data['motion'], defaults.motion),
          accentRgb: data['accentRgb'] is int &&
                  data['accentRgb'] >= 0 &&
                  data['accentRgb'] <= 0xffffff
              ? data['accentRgb'] as int
              : defaults.accentRgb,
          compact: data['compact'] is bool
              ? data['compact'] as bool
              : defaults.compact,
          coverRadius: data['coverRadius'] is int
              ? data['coverRadius'] as int
              : defaults.coverRadius);
    } on FormatException {
      return defaults;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettings &&
      other.mode == mode &&
      other.accentRgb == accentRgb &&
      other.motion == motion &&
      other.compact == compact &&
      other.coverRadius == coverRadius;
  @override
  int get hashCode =>
      Object.hash(mode, accentRgb, motion, compact, coverRadius);
}
