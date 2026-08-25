import 'package:flutter/material.dart';

/// Cores de status/ação e marca — as MESMAS nos dois temas, de propósito.
///
/// Elas só aparecem em ícones, badges (sobre fundo translúcido da própria
/// cor) e botões — nunca como texto corrido sobre fundo branco puro — então
/// o contraste continua ótimo nos dois modos sem precisar de uma versão
/// "escurecida para o claro" (isso já foi tentado e deixava as cores sem
/// vida). Ficam fora de [AppColors] de propósito, como constantes únicas
/// compartilhadas pelas duas paletas, pra impedir estruturalmente que
/// alguém edite só uma delas no futuro e quebre essa garantia de novo.
class AppStatusColors {
  const AppStatusColors._();

  static const primary = Color(0xFF6E48AA); // Roxo Constel
  static const secondary = Color(0xFF9D50BB); // Lilás Constel
  static const accent = Color(0xFFFDB813); // Dourado Constel — marca/destaque

  static const info = Color(0xFF2196F3); // Recebido / novo
  static const warning = Color(0xFFFFB300); // Em preparo
  static const success = Color(0xFF4CAF50); // Pronto / finalizado
  static const error = Color(0xFFE53935); // Atraso / erro / reverter
}

/// Paleta de SUPERFÍCIE E TEXTO — a parte que realmente muda entre claro e
/// escuro (fundo, cards, bordas, sombra, texto). Exposta via [ThemeExtension]
/// para qualquer widget ler com `Theme.of(context).extension<AppColors>()!`
/// — ou o atalho `context.colors` — e reagir automaticamente à troca de
/// tema, sem precisar saber qual dos dois modos está ativo.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  // Superfície
  final Color backgroundColor;
  final Color cardColor;
  final Color borderColor;
  final Color shadowColor;

  // Texto
  final Color textColor;
  final Color textSecondaryColor;

  // Marca/status — mesmos valores em dark e light (ver AppStatusColors),
  // só repetidos aqui pra ficarem acessíveis pelo mesmo `context.colors.*`
  // usado pelas cores de superfície.
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final Color infoColor;
  final Color warningColor;
  final Color successColor;
  final Color errorColor;

  const AppColors({
    required this.backgroundColor,
    required this.cardColor,
    required this.borderColor,
    required this.shadowColor,
    required this.textColor,
    required this.textSecondaryColor,
    this.primaryColor = AppStatusColors.primary,
    this.secondaryColor = AppStatusColors.secondary,
    this.accentColor = AppStatusColors.accent,
    this.infoColor = AppStatusColors.info,
    this.warningColor = AppStatusColors.warning,
    this.successColor = AppStatusColors.success,
    this.errorColor = AppStatusColors.error,
  });

  /// Fundo bem escuro (como no KDS original) — ambiente de cozinha com
  /// pouca luz ambiente costuma preferir esse modo.
  static const dark = AppColors(
    backgroundColor: Color(0xFF161821),
    cardColor: Color(0xFF212433),
    borderColor: Color(0x1AFFFFFF), // ~ Colors.white10, nomeado pra reuso
    shadowColor: Color(
        0x00000000), // sem sombra própria — o contraste já vem do fundo escuro
    textColor: Color(0xFFE1E1E6),
    textSecondaryColor: Color(0xFFA8A8B3),
  );

  /// Fundo off-white (NÃO branco puro) — evita ofuscar em ambientes de
  /// cozinha muito iluminados. Cards brancos com borda suave e sombra leve
  /// criam a profundidade que o fundo escuro já dava de graça por contraste.
  static const light = AppColors(
    backgroundColor: Color(0xFFF4F5F8),
    cardColor: Color(0xFFFFFFFF),
    borderColor: Color(0xFFE2E8F0),
    shadowColor: Color(0x1A0F172A),
    textColor: Color(0xFF0F172A),
    textSecondaryColor: Color(0xFF64748B),
  );

  @override
  AppColors copyWith({
    Color? backgroundColor,
    Color? cardColor,
    Color? borderColor,
    Color? shadowColor,
    Color? textColor,
    Color? textSecondaryColor,
    Color? primaryColor,
    Color? secondaryColor,
    Color? accentColor,
    Color? infoColor,
    Color? warningColor,
    Color? successColor,
    Color? errorColor,
  }) {
    return AppColors(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      cardColor: cardColor ?? this.cardColor,
      borderColor: borderColor ?? this.borderColor,
      shadowColor: shadowColor ?? this.shadowColor,
      textColor: textColor ?? this.textColor,
      textSecondaryColor: textSecondaryColor ?? this.textSecondaryColor,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      accentColor: accentColor ?? this.accentColor,
      infoColor: infoColor ?? this.infoColor,
      warningColor: warningColor ?? this.warningColor,
      successColor: successColor ?? this.successColor,
      errorColor: errorColor ?? this.errorColor,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      backgroundColor: Color.lerp(backgroundColor, other.backgroundColor, t)!,
      cardColor: Color.lerp(cardColor, other.cardColor, t)!,
      borderColor: Color.lerp(borderColor, other.borderColor, t)!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
      textColor: Color.lerp(textColor, other.textColor, t)!,
      textSecondaryColor:
          Color.lerp(textSecondaryColor, other.textSecondaryColor, t)!,
      primaryColor: Color.lerp(primaryColor, other.primaryColor, t)!,
      secondaryColor: Color.lerp(secondaryColor, other.secondaryColor, t)!,
      accentColor: Color.lerp(accentColor, other.accentColor, t)!,
      infoColor: Color.lerp(infoColor, other.infoColor, t)!,
      warningColor: Color.lerp(warningColor, other.warningColor, t)!,
      successColor: Color.lerp(successColor, other.successColor, t)!,
      errorColor: Color.lerp(errorColor, other.errorColor, t)!,
    );
  }
}

/// Acesso ergonômico à paleta ativa: `context.colors.backgroundColor` em vez
/// de `Theme.of(context).extension<AppColors>()!.backgroundColor`.
extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
