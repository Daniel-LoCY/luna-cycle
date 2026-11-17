import 'package:material_ui/material_ui.dart';

abstract final class LunaColors {
  static const cream = Color(0xFFFAF8F6);
  static const lavender = Color(0xFFAA91D6);
  static const pink = Color(0xFFF2B7C6);
  static const mint = Color(0xFFA7D5C4);
  static const ink = Color(0xFF282632);
  static const muted = Color(0xFF77737F);
  static const surface = Color(0xFFFFFFFF);
  static const dark = Color(0xFF201E25);
}

abstract final class LunaTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: LunaColors.lavender,
      brightness: brightness,
      surface: isDark ? LunaColors.dark : LunaColors.cream,
      primary: isDark ? const Color(0xFFC7B4EF) : const Color(0xFF69518E),
      secondary: isDark ? const Color(0xFFFFC6D4) : const Color(0xFF985768),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? LunaColors.dark : LunaColors.cream,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? LunaColors.dark : LunaColors.cream,
        foregroundColor: isDark ? Colors.white : LunaColors.ink,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF2B2832) : LunaColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF26232C) : LunaColors.surface,
        indicatorColor: isDark
            ? const Color(0xFF51446A)
            : const Color(0xFFEDE5F7),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
