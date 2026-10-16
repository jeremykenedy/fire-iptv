import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------------------
  // Palette
  // ---------------------------------------------------------------------------

  static const _background = Color(0xFF101C30);
  static const _surface = Color(0xFF1B2B44);
  static const _surfaceVariant = Color(0xFF273B58);
  static const _outline = Color(0xFF405570);
  static const defaultAccent = Color(0xFFFFB54A);
  static const defaultAccentHex = 'FFB54A';
  static const _onPrimary = Color(0xFF101C30);
  static const _onBackground = Color(0xFFF2F2F7);
  static const _onSurface = Color(0xFFEBEBF5);
  static const _onSurfaceVariant = Color(0xFF8E8E93);
  static const _error = Color(0xFFFF453A);

  // Available accent color swatches
  static const List<({String label, Color color})> accentSwatches = [
    (label: 'Amber', color: defaultAccent),
    (label: 'Blue', color: Color(0xFF0A84FF)),
    (label: 'Purple', color: Color(0xFFBF5AF2)),
    (label: 'Pink', color: Color(0xFFFF2D55)),
    (label: 'Orange', color: Color(0xFFFF9F0A)),
    (label: 'Green', color: Color(0xFF30D158)),
    (label: 'Teal', color: Color(0xFF5AC8FA)),
  ];

  // Public accessors so one-off screens (e.g. the setup wizard, which draws
  // its own gradient background before the app's theme is fully "committed")
  // can match the real palette instead of re-declaring their own hex values.
  static const backgroundColor = _background;
  static const surfaceColor = _surface;
  static const surfaceVariantColor = _surfaceVariant;
  static const outlineColor = _outline;
  static const mutedTextColor = _onSurfaceVariant;

  static Color accentFromHex(String hex) {
    try {
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return defaultAccent;
    }
  }

  /// Bundled Google Sans (see pubspec.yaml).
  static const fontFamily = 'GoogleSans';

  static String hexFromAccent(Color c) =>
      c.toARGB32().toRadixString(16).toUpperCase().substring(2);

  // ---------------------------------------------------------------------------
  // Dark theme (the app's only theme — see AppTheme.dark() usage in app.dart)
  // ---------------------------------------------------------------------------

  static ThemeData dark([Color? accent]) {
    final primary = accent ?? defaultAccent;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: _background,
      // Android's modern "fade forwards" route transition (the one Google's
      // own apps use) instead of the default zoom.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      colorScheme: ColorScheme.dark(
        primary: primary,
        onPrimary: _onPrimary,
        secondary: primary,
        onSecondary: _onPrimary,
        surface: _surface,
        onSurface: _onSurface,
        surfaceContainerHighest: _surfaceVariant,
        onSurfaceVariant: _onSurfaceVariant,
        outline: _outline,
        outlineVariant: _surfaceVariant,
        inverseSurface: _onBackground,
        onInverseSurface: _background,
        surfaceTint: Colors.transparent,
        error: _error,
        onError: _onPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _background,
        foregroundColor: _onBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        indicatorColor: primary.withValues(alpha: 0.24),
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? primary
                  : _onSurfaceVariant,
              size: 24,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: fontFamily,
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w600
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? _onBackground
                  : _onSurfaceVariant,
            )),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: _surface,
        selectedItemColor: primary,
        unselectedItemColor: _onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _surfaceVariant,
        selectedColor: primary.withValues(alpha: 0.2),
        labelStyle: const TextStyle(
            fontFamily: fontFamily, color: _onSurface, fontSize: 13),
        side: const BorderSide(color: Colors.transparent),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: const TextStyle(
            fontFamily: fontFamily, color: _onSurfaceVariant),
      ),
      // Google Sans type scale: tighter, heavier headings; relaxed body.
      textTheme: TextTheme(
        displaySmall: const TextStyle(
            color: _onBackground,
            fontSize: 34,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
            height: 1.15),
        headlineLarge: const TextStyle(
            color: _onBackground,
            fontSize: 30,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
            height: 1.2),
        headlineMedium: const TextStyle(
            color: _onBackground,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            height: 1.25),
        headlineSmall: const TextStyle(
            color: _onBackground, fontSize: 21, fontWeight: FontWeight.w600),
        titleLarge: const TextStyle(
            color: _onBackground, fontSize: 19, fontWeight: FontWeight.w600),
        titleMedium: const TextStyle(
            color: _onBackground, fontSize: 16, fontWeight: FontWeight.w500),
        titleSmall: const TextStyle(
            color: _onBackground, fontSize: 14, fontWeight: FontWeight.w600),
        bodyLarge:
            const TextStyle(color: _onSurface, fontSize: 16, height: 1.45),
        bodyMedium:
            const TextStyle(color: _onSurface, fontSize: 14, height: 1.4),
        bodySmall: const TextStyle(
            color: _onSurfaceVariant, fontSize: 12.5, height: 1.35),
        labelLarge: TextStyle(
            color: primary, fontSize: 14, fontWeight: FontWeight.w600),
        labelMedium: const TextStyle(
            color: _onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2),
        labelSmall: const TextStyle(
            color: _onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6),
      ),
      dividerTheme: const DividerThemeData(
        color: _surfaceVariant,
        thickness: 0.5,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: _onSurfaceVariant,
        textColor: _onSurface,
        tileColor: Colors.transparent,
      ),
      iconTheme: const IconThemeData(color: _onSurfaceVariant),
      // Explicit track: Material 3 draws it in secondaryContainer, which
      // (unset here) falls back to secondary == primary — making every
      // progress bar look 100% full regardless of its value.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: Colors.white.withValues(alpha: 0.15),
        circularTrackColor: Colors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: _onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cardRadius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cardRadius),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _onSurface,
          side: const BorderSide(color: _outline),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(cardRadius),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        titleTextStyle: const TextStyle(
            fontFamily: fontFamily,
            color: _onBackground,
            fontSize: 18,
            fontWeight: FontWeight.w600),
        contentTextStyle: const TextStyle(
            fontFamily: fontFamily, color: _onSurface, fontSize: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _surfaceVariant,
        contentTextStyle: const TextStyle(
            fontFamily: fontFamily, color: _onSurface),
        actionTextColor: primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared constants
  // ---------------------------------------------------------------------------

  static const posterAspectRatio = 2 / 3;
  static const cardRadius = 12.0;

  static BoxDecoration focusDecoration(Color accent) => BoxDecoration(
        border: Border.all(color: accent, width: 3),
        borderRadius: BorderRadius.circular(cardRadius),
      );

  /// Style for a destructive/irreversible confirm action in a dialog
  /// (Delete, Remove) — a solid error-colored FilledButton, applied
  /// consistently everywhere a destructive confirm button appears.
  static ButtonStyle destructiveButtonStyle(BuildContext context) =>
      FilledButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.error,
        foregroundColor: Theme.of(context).colorScheme.onError,
      );
}
