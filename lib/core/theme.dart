import 'package:flutter/material.dart';

/// Netflix-inspired dark theme with a Popcorn Studio identity: deep charcoal
/// surfaces, signal red for primary actions and warm popcorn amber for
/// secondary highlights.
class AppTheme {
  AppTheme._();

  static const Color background = Color(0xFF0E0F13);
  static const Color surface = Color(0xFF171923);
  static const Color surfaceHigh = Color(0xFF21242F);
  static const Color accent = Color(0xFFE50914);
  static const Color accentAlt = Color(0xFFF5B23E);
  static const Color textPrimary = Color(0xFFF5F6FA);
  static const Color textSecondary = Color(0xFF9AA0B4);
  static const Color divider = Color(0xFF262A36);
  static const Color success = Color(0xFF3DBE7B);
  static const Color warning = Color(0xFFE0A93E);
  static const Color danger = Color(0xFFE04848);

  static ThemeData dark() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      primary: accent,
      secondary: accentAlt,
      surface: surface,
    );
    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceHigh,
        modalBackgroundColor: surfaceHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: const TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        hintStyle: const TextStyle(color: textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: accent, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: textSecondary),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: textPrimary)),
      sliderTheme: const SliderThemeData(
        activeTrackColor: accent,
        thumbColor: accent,
        inactiveTrackColor: divider,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: divider,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? accent : surfaceHigh,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        selectedIconTheme: const IconThemeData(color: accent),
        selectedLabelTextStyle: const TextStyle(
          color: accent,
          fontWeight: FontWeight.w700,
        ),
        unselectedIconTheme: const IconThemeData(color: textSecondary),
        unselectedLabelTextStyle: const TextStyle(color: textSecondary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color:
                states.contains(WidgetState.selected) ? accent : textSecondary,
          ),
        ),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 11.5, color: textSecondary),
        ),
      ),
      dividerTheme: const DividerThemeData(color: divider, thickness: 1),
      listTileTheme: const ListTileThemeData(
        iconColor: textSecondary,
        textColor: textPrimary,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceHigh,
        labelStyle: const TextStyle(color: textPrimary, fontSize: 12),
        side: BorderSide.none,
      ),
    );
  }
}
