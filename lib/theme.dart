import 'package:flutter/material.dart';

// Та же агрономическая палитра, что и в мини-аппе внутри Telegram (src/miniappPage.ts) —
// зелёный/золотой, кремовый фон в светлой теме, тёмно-зелёный в тёмной.
class AgroColors {
  static const green = Color(0xFF2E7D32);
  static const greenDark = Color(0xFF1B5E20);
  static const greenLight = Color(0xFF66BB6A);
  static const gold = Color(0xFFD9A441);
  static const goldDark = Color(0xFFB5822B);
  static const brown = Color(0xFF6D4C41);
  static const danger = Color(0xFFC1462F);
  static const bgLight = Color(0xFFF4EFE2);
  static const bgDark = Color(0xFF16211A);
}

ThemeData buildAgroTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AgroColors.green,
    secondary: AgroColors.gold,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isDark ? AgroColors.bgDark : AgroColors.bgLight,
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? AgroColors.bgDark : AgroColors.bgLight,
      foregroundColor: isDark ? Colors.white : const Color(0xFF2B2118),
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
