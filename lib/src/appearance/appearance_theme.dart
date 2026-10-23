import 'package:flutter/material.dart';

import 'appearance_settings.dart';

Duration appearanceDuration(AppearanceMotion motion, [int milliseconds = 240]) {
  final factor = switch (motion) {
    AppearanceMotion.off => 0.0,
    AppearanceMotion.slow => 1.5,
    AppearanceMotion.normal => 1.0,
    AppearanceMotion.fast => .65,
  };
  return Duration(milliseconds: (milliseconds * factor).round());
}

/// Semantic visual tokens shared by phone and desktop layouts.
final class AppearanceTokens extends ThemeExtension<AppearanceTokens> {
  const AppearanceTokens(
      {required this.accent,
      required this.onAccent,
      required this.muted,
      required this.rowPadding,
      required this.coverRadius,
      required this.motion});
  final Color accent, onAccent, muted;
  final double rowPadding, coverRadius;
  final AppearanceMotion motion;
  Duration duration(BuildContext context, [int milliseconds = 240]) {
    if (MediaQuery.disableAnimationsOf(context) ||
        motion == AppearanceMotion.off) {
      return Duration.zero;
    }
    return appearanceDuration(motion, milliseconds);
  }

  @override
  AppearanceTokens copyWith(
          {Color? accent,
          Color? onAccent,
          Color? muted,
          double? rowPadding,
          double? coverRadius,
          AppearanceMotion? motion}) =>
      AppearanceTokens(
          accent: accent ?? this.accent,
          onAccent: onAccent ?? this.onAccent,
          muted: muted ?? this.muted,
          rowPadding: rowPadding ?? this.rowPadding,
          coverRadius: coverRadius ?? this.coverRadius,
          motion: motion ?? this.motion);
  @override
  AppearanceTokens lerp(covariant AppearanceTokens? other, double t) =>
      other == null
          ? this
          : AppearanceTokens(
              accent: Color.lerp(accent, other.accent, t)!,
              onAccent: Color.lerp(onAccent, other.onAccent, t)!,
              muted: Color.lerp(muted, other.muted, t)!,
              rowPadding: rowPadding + (other.rowPadding - rowPadding) * t,
              coverRadius: coverRadius + (other.coverRadius - coverRadius) * t,
              motion: other.motion);
  static AppearanceTokens of(BuildContext context) =>
      Theme.of(context).extension<AppearanceTokens>() ??
      const AppearanceTokens(
          accent: Color(0xffffcc33),
          onAccent: Colors.black,
          muted: Color(0xffaaaaaa),
          rowPadding: 10,
          coverRadius: 8,
          motion: AppearanceMotion.normal);
}

Color readableOn(Color background) {
  final light = background.computeLuminance();
  return (light + .05) / .05 >= 1.05 / (light + .05)
      ? Colors.black
      : Colors.white;
}

ThemeData createAppearanceTheme(
    AppearanceSettings settings, Brightness brightness,
    {String? fontFamily}) {
  final dark = brightness == Brightness.dark;
  final accent = Color(0xff000000 | settings.accentRgb);
  final background = dark ? const Color(0xff101010) : const Color(0xfffafafa);
  final panel = dark ? const Color(0xff202020) : const Color(0xffeeeeee);
  final text = dark ? const Color(0xfff5f5f5) : const Color(0xff202020);
  final muted = dark ? const Color(0xffaaaaaa) : const Color(0xff606060);
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
          surface: background,
          onSurface: text,
          onSurfaceVariant: muted,
          surfaceContainer: panel,
          surfaceContainerLow: panel,
          surfaceContainerHighest:
              dark ? const Color(0xff303030) : const Color(0xffdddddd));
  final tokens = AppearanceTokens(
      accent: accent,
      onAccent: readableOn(accent),
      muted: muted,
      rowPadding: settings.compact ? 6 : 10,
      coverRadius: settings.coverRadius.toDouble(),
      motion: settings.motion);
  return ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      extensions: [tokens],
      visualDensity:
          settings.compact ? VisualDensity.compact : VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
          backgroundColor: background, foregroundColor: text, elevation: 0),
      dividerTheme:
          DividerThemeData(color: muted.withValues(alpha: .18), space: 1),
      inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: panel,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none)),
      pageTransitionsTheme: PageTransitionsTheme(builders: {
        for (final platform in TargetPlatform.values)
          platform: _AppearanceTransitions(),
      }));
}

ThemeMode appearanceThemeMode(AppearanceMode mode) => switch (mode) {
      AppearanceMode.system => ThemeMode.system,
      AppearanceMode.light => ThemeMode.light,
      AppearanceMode.dark => ThemeMode.dark,
    };

/// Existing routes honor reduced motion; new routes also use configured timing.
final class _AppearanceTransitions extends PageTransitionsBuilder {
  const _AppearanceTransitions();
  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    final tokens = AppearanceTokens.of(context);
    if (tokens.duration(context) == Duration.zero) return child;
    return FadeTransition(
        opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
        child: child);
  }
}

Route<T> appearanceRoute<T>(BuildContext context, WidgetBuilder builder) =>
    PageRouteBuilder<T>(
        pageBuilder: (context, animation, secondary) => builder(context),
        transitionDuration: AppearanceTokens.of(context).duration(context),
        reverseTransitionDuration:
            AppearanceTokens.of(context).duration(context),
        transitionsBuilder: (context, animation, secondary, child) =>
            FadeTransition(
                opacity:
                    animation.drive(CurveTween(curve: Curves.easeOutCubic)),
                child: child));
