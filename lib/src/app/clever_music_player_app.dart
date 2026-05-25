import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ui/screens/home_screen.dart';

final class CleverMusicPlayerApp extends StatelessWidget {
  const CleverMusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff7c5cff),
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xff8ea2ff),
      onPrimary: const Color(0xff111735),
      secondary: const Color(0xffff7ab6),
      onSecondary: const Color(0xff32101f),
      tertiary: const Color(0xff73d4ff),
      onTertiary: const Color(0xff071d28),
      surface: const Color(0xff101116),
      onSurface: const Color(0xfff3f0f7),
      surfaceContainerLowest: const Color(0xff0b0c10),
      surfaceContainerLow: const Color(0xff161821),
      surfaceContainer: const Color(0xff1d202a),
      surfaceContainerHigh: const Color(0xff252936),
      surfaceContainerHighest: const Color(0xff303543),
      outlineVariant: const Color(0xff444a5f),
    );
    final roundedRectangle = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    );

    return MaterialApp(
      title: 'Clever Music Player',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      scrollBehavior: const _DesktopScrollBehavior(),
      darkTheme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surfaceContainerLowest,
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.surfaceContainerLowest,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          color: colorScheme.surfaceContainerLow,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          thickness: 1,
          space: 1,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: roundedRectangle,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.onSurface,
            side: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
            shape: roundedRectangle,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: colorScheme.tertiary,
            shape: roundedRectangle,
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: colorScheme.surfaceContainerHigh,
          selectedColor: colorScheme.primaryContainer,
          disabledColor: colorScheme.surfaceContainer,
          labelStyle: TextStyle(color: colorScheme.onSurface),
          secondaryLabelStyle: TextStyle(color: colorScheme.onPrimaryContainer),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surfaceContainerHigh,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
          ),
          isDense: true,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: colorScheme.primary,
          inactiveTrackColor: colorScheme.outlineVariant,
          thumbColor: colorScheme.primary,
          overlayColor: colorScheme.primary.withValues(alpha: 0.15),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colorScheme.onPrimary
                : colorScheme.outline,
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest,
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

final class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}
