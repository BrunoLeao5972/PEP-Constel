import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Tokens de superfície da tela de Configurações.
///
/// Por que existe uma paleta própria aqui em vez de usar só [AppColors]: a
/// tela de Configurações é a única do app feita de **cards dentro de cards**
/// (um card de seção sobre o fundo da página, com campos de texto rebaixados
/// dentro dele). Isso pede três níveis de superfície — fundo, card, campo —
/// enquanto o resto do app precisa de dois. Colocar esses níveis extras em
/// [AppColors] mudaria a cara de Cozinha, Administrativo e Painel sem
/// necessidade; deixá-los aqui mantém o raio de alcance no tamanho do
/// problema.
///
/// Os valores do modo escuro são os da identidade nova (#1E202E de card,
/// #2A2D3D de borda, #141622 de campo, #8A8F9E de texto secundário); o modo
/// claro tem os equivalentes, porque o app tem os dois temas e a tela não
/// pode virar um bloco escuro no meio do tema claro.
@immutable
class SettingsTokens {
  /// Cantos, respiros e espessuras — os mesmos em qualquer tema.
  static const cardRadius = 12.0;
  static const cardPadding = 20.0;
  static const cardSpacing = 20.0;
  static const inputRadius = 8.0;

  /// A partir desta largura os cards se organizam em duas colunas.
  static const twoColumnBreakpoint = 900.0;

  /// Teto de largura do conteúdo: numa TV/monitor 4K, deixar os cards
  /// esticarem até a borda transformaria cada linha de texto num campo de
  /// futebol.
  static const maxContentWidth = 1360.0;

  final Color pageBackground;
  final Color cardBackground;
  final Color cardBorder;
  final Color inputFill;
  final Color secondaryText;

  /// Dourado da marca para TODA ação primária (Salvar, Conectar, Testar) —
  /// no lugar do roxo, que aparecia só aqui e destoava do resto do produto.
  final Color primaryAction;

  /// Texto/ícone por cima do dourado: escuro, porque texto branco sobre
  /// #FDB813 fica em 1,9:1 de contraste — ilegível.
  final Color onPrimaryAction;

  const SettingsTokens({
    required this.pageBackground,
    required this.cardBackground,
    required this.cardBorder,
    required this.inputFill,
    required this.secondaryText,
    required this.primaryAction,
    required this.onPrimaryAction,
  });

  static const dark = SettingsTokens(
    pageBackground: Color(0xFF161821),
    cardBackground: Color(0xFF1E202E),
    cardBorder: Color(0xFF2A2D3D),
    inputFill: Color(0xFF141622),
    secondaryText: Color(0xFF8A8F9E),
    primaryAction: AppStatusColors.accent,
    onPrimaryAction: Color(0xFF161821),
  );

  static const light = SettingsTokens(
    pageBackground: Color(0xFFF4F5F8),
    cardBackground: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE2E8F0),
    inputFill: Color(0xFFF8FAFC),
    secondaryText: Color(0xFF64748B),
    primaryAction: AppStatusColors.accent,
    onPrimaryAction: Color(0xFF0F172A),
  );

  static SettingsTokens of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// Tema aplicado uma vez na raiz da tela, em vez de estilo repetido em cada
  /// campo e botão.
  ///
  /// É o que faz um `TextField` solto, um `SegmentedButton` ou o
  /// [PrinterSettingsWidget] já nascerem com a cara nova sem precisar saber
  /// que estão dentro de Configurações — e o que garante que ninguém esqueça
  /// de estilizar um campo novo no futuro.
  ThemeData applyTo(ThemeData base) {
    const transparent = Color(0x00000000);

    return base.copyWith(
      scaffoldBackgroundColor: pageBackground,
      dividerColor: cardBorder,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        // Rótulo sempre em cima do campo: com o rótulo flutuando só quando há
        // foco, um formulário preenchido vira uma pilha de valores sem nome.
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle:
            TextStyle(color: secondaryText, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(color: secondaryText.withValues(alpha: 0.7)),
        border: _inputBorder(cardBorder),
        enabledBorder: _inputBorder(cardBorder),
        disabledBorder: _inputBorder(cardBorder.withValues(alpha: 0.6)),
        focusedBorder: _inputBorder(primaryAction, width: 1.6),
        errorBorder: _inputBorder(base.colorScheme.error),
        focusedErrorBorder: _inputBorder(base.colorScheme.error, width: 1.6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryAction,
          foregroundColor: onPrimaryAction,
          disabledBackgroundColor: primaryAction.withValues(alpha: 0.28),
          disabledForegroundColor: onPrimaryAction.withValues(alpha: 0.5),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(inputRadius)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: base.extension<AppColors>()?.textColor,
          side: BorderSide(color: cardBorder),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(inputRadius)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primaryAction),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? onPrimaryAction
                : secondaryText),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? primaryAction : inputFill),
        trackOutlineColor: WidgetStateProperty.all(cardBorder),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? primaryAction
                  : transparent),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? onPrimaryAction
                  : secondaryText),
          side: WidgetStatePropertyAll(BorderSide(color: cardBorder)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(inputRadius))),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primaryAction),
    );
  }

  OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(inputRadius),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}
