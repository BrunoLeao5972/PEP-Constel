import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Monta o [ThemeData] completo de cada modo a partir de [AppColors] — a
/// paleta é a única fonte de verdade; aqui só existe a "tradução" dela pros
/// componentes padrão do Material (AppBar, Card, botões, texto).
class AppThemes {
  static ThemeData get dark => _build(Brightness.dark, AppColors.dark);
  static ThemeData get light => _build(Brightness.light, AppColors.light);

  static ThemeData _build(Brightness brightness, AppColors colors) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.backgroundColor,
      primaryColor: colors.primaryColor,
      dividerColor: colors.borderColor,
      // Registra a paleta como ThemeExtension: é o que permite qualquer
      // widget ler `context.colors.xxx` e recalcular automaticamente quando
      // o MaterialApp troca de theme/darkTheme (inclusive com a transição
      // animada que o MaterialApp já faz sozinho por padrão).
      extensions: [colors],
      colorScheme: isDark
          ? ColorScheme.dark(
              primary: colors.primaryColor,
              secondary: colors.accentColor,
              surface: colors.cardColor,
              onSurface: colors.textColor,
              error: colors.errorColor,
            )
          : ColorScheme.light(
              primary: colors.primaryColor,
              secondary: colors.accentColor,
              surface: colors.cardColor,
              onSurface: colors.textColor,
              error: colors.errorColor,
            ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.cardColor,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: colors.textColor,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      // No claro, o card ganha borda + sombra leve pra criar profundidade
      // (o fundo off-white e o card branco são próximos demais pra contar só
      // com a diferença de cor, como acontecia no escuro).
      cardTheme: CardTheme(
        color: colors.cardColor,
        elevation: isDark ? 2 : 0,
        shadowColor: colors.shadowColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side:
              isDark ? BorderSide.none : BorderSide(color: colors.borderColor),
        ),
      ),
      textTheme: GoogleFonts.spaceGroteskTextTheme(
        TextTheme(
          displayLarge:
              TextStyle(color: colors.textColor, fontWeight: FontWeight.bold),
          titleLarge:
              TextStyle(color: colors.accentColor, fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(color: colors.textColor),
          bodyMedium: TextStyle(color: colors.textColor),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
