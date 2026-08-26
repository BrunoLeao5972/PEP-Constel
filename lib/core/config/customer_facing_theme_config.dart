import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Cada cor personalizável do Painel Chamador (tela do cliente).
///
/// Existe para que a tela de Configurações consiga listar e editar todas as
/// cores num laço só, em vez de repetir nove blocos de UI quase idênticos —
/// enquanto [CustomerFacingThemeConfig] continua expondo cada cor com nome
/// próprio (`backgroundColor`, `cardTheme.cardBorderColor`, ...) para quem lê
/// a configuração no código.
enum CustomerFacingColorSlot {
  background,
  headerText,
  inPreparation,
  callingNow,
  readyQueue,
  cardBackground,
  cardBorder,
  cardText,
}

/// As três seções fixas do Painel, com o título e o ícone que as identificam.
///
/// Os ícones são [IconData] vetorizados de propósito — antes eram emojis em
/// string ("🔥", "📢", "🔔"), que dependiam da fonte de emoji instalada (o
/// desenho mudava entre Windows e Android, e em algumas TVs virava um
/// quadrado vazio) e não aceitavam cor nem tamanho vindos do tema. Como o
/// preview das Configurações e a tela real leem os dois campos daqui, é
/// estruturalmente impossível eles saírem de sincronia.
enum CustomerFacingPanelSection {
  inPreparation(
    title: 'EM PREPARO',
    icon: Icons.local_fire_department_rounded,
    colorSlot: CustomerFacingColorSlot.inPreparation,
  ),
  callingNow(
    title: 'CHAMANDO AGORA',
    icon: Icons.campaign_rounded,
    colorSlot: CustomerFacingColorSlot.callingNow,
  ),
  readyQueue(
    title: 'FILA DE PRONTOS',
    icon: Icons.notifications_active_rounded,
    colorSlot: CustomerFacingColorSlot.readyQueue,
  );

  const CustomerFacingPanelSection({
    required this.title,
    required this.icon,
    required this.colorSlot,
  });

  final String title;
  final IconData icon;
  final CustomerFacingColorSlot colorSlot;
}

/// Cores dos títulos/ícones de cada coluna do Painel.
///
/// `null` em qualquer campo significa "automático": cai no padrão de fábrica
/// da marca (os mesmos valores de [AppStatusColors]), documentado em cada
/// constante abaixo.
@immutable
class CustomerFacingColumnHeaderColors {
  static const defaultInPreparationColor = AppStatusColors.warning; // #FFB300
  static const defaultCallingNowColor = AppStatusColors.accent; // #FDB813
  static const defaultReadyQueueColor = AppStatusColors.success; // #4CAF50

  final Color? inPreparationColor;
  final Color? callingNowColor;
  final Color? readyQueueColor;

  const CustomerFacingColumnHeaderColors({
    this.inPreparationColor,
    this.callingNowColor,
    this.readyQueueColor,
  });

  bool get isDefault =>
      inPreparationColor == null &&
      callingNowColor == null &&
      readyQueueColor == null;

  Map<String, dynamic> toJson() => {
        'inPreparationColor': _colorToArgb(inPreparationColor),
        'callingNowColor': _colorToArgb(callingNowColor),
        'readyQueueColor': _colorToArgb(readyQueueColor),
      };

  factory CustomerFacingColumnHeaderColors.fromJson(Map<String, dynamic> json) {
    return CustomerFacingColumnHeaderColors(
      inPreparationColor: _colorFromArgb(json['inPreparationColor']),
      callingNowColor: _colorFromArgb(json['callingNowColor']),
      readyQueueColor: _colorFromArgb(json['readyQueueColor']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CustomerFacingColumnHeaderColors &&
      other.inPreparationColor == inPreparationColor &&
      other.callingNowColor == callingNowColor &&
      other.readyQueueColor == readyQueueColor;

  @override
  int get hashCode =>
      Object.hash(inPreparationColor, callingNowColor, readyQueueColor);
}

/// Aparência dos cards de senha/comanda do Painel (o "0002" da tela).
///
/// As três cores aceitam `null` = automático: o fundo segue o card do tema, e
/// borda e texto seguem a cor da própria coluna (âmbar em Em Preparo, verde
/// em Fila de Prontos...), que é o comportamento histórico da tela.
@immutable
class CustomerFacingCardTheme {
  static const defaultCardBorderRadius = 8.0;

  /// Limite de segurança do raio: acima disso o card vira uma cápsula e o
  /// número da senha começa a ser cortado nas resoluções menores.
  static const maxCardBorderRadius = 32.0;

  final Color? cardBackgroundColor;
  final Color? cardBorderColor;
  final Color? cardTextColor;
  final double cardBorderRadius;

  const CustomerFacingCardTheme({
    this.cardBackgroundColor,
    this.cardBorderColor,
    this.cardTextColor,
    this.cardBorderRadius = defaultCardBorderRadius,
  });

  bool get isDefault =>
      cardBackgroundColor == null &&
      cardBorderColor == null &&
      cardTextColor == null &&
      cardBorderRadius == defaultCardBorderRadius;

  Map<String, dynamic> toJson() => {
        'cardBackgroundColor': _colorToArgb(cardBackgroundColor),
        'cardBorderColor': _colorToArgb(cardBorderColor),
        'cardTextColor': _colorToArgb(cardTextColor),
        'cardBorderRadius': cardBorderRadius,
      };

  factory CustomerFacingCardTheme.fromJson(Map<String, dynamic> json) {
    final rawRadius = json['cardBorderRadius'];
    return CustomerFacingCardTheme(
      cardBackgroundColor: _colorFromArgb(json['cardBackgroundColor']),
      cardBorderColor: _colorFromArgb(json['cardBorderColor']),
      cardTextColor: _colorFromArgb(json['cardTextColor']),
      cardBorderRadius: rawRadius is num
          ? rawRadius.toDouble().clamp(0.0, maxCardBorderRadius)
          : defaultCardBorderRadius,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CustomerFacingCardTheme &&
      other.cardBackgroundColor == cardBackgroundColor &&
      other.cardBorderColor == cardBorderColor &&
      other.cardTextColor == cardTextColor &&
      other.cardBorderRadius == cardBorderRadius;

  @override
  int get hashCode => Object.hash(
      cardBackgroundColor, cardBorderColor, cardTextColor, cardBorderRadius);
}

/// Personalização do Painel Chamador, salva no aparelho e válida nas duas
/// plataformas (Windows e Android) — cada instalação tem a sua, porque quem
/// escolhe a cara da tela do cliente é o estabelecimento, não o banco.
///
/// **Toda cor é opcional de propósito.** `null` não é "sem cor": é
/// "automático", e quem traduz isso para uma cor concreta é [resolve], num
/// lugar só, a partir da paleta do tema ativo. Assim uma instalação que nunca
/// abriu essa configuração continua vendo exatamente o Painel de sempre
/// (fundo #161821 no escuro, #F4F5F8 no claro), e quem personaliza só o que
/// quer não perde o tema nos campos que não tocou.
@immutable
class CustomerFacingThemeConfig {
  final Color? backgroundColor;
  final Color? headerTextColor;
  final CustomerFacingColumnHeaderColors columnHeaderColors;
  final CustomerFacingCardTheme cardTheme;

  const CustomerFacingThemeConfig({
    this.backgroundColor,
    this.headerTextColor,
    this.columnHeaderColors = const CustomerFacingColumnHeaderColors(),
    this.cardTheme = const CustomerFacingCardTheme(),
  });

  /// True quando nada foi personalizado — a tela de Configurações usa isso
  /// para desabilitar o botão "Restaurar Padrões".
  bool get isDefault =>
      backgroundColor == null &&
      headerTextColor == null &&
      columnHeaderColors.isDefault &&
      cardTheme.isDefault;

  /// Cor escolhida para [slot], ou `null` se ela está em automático.
  Color? colorFor(CustomerFacingColorSlot slot) {
    switch (slot) {
      case CustomerFacingColorSlot.background:
        return backgroundColor;
      case CustomerFacingColorSlot.headerText:
        return headerTextColor;
      case CustomerFacingColorSlot.inPreparation:
        return columnHeaderColors.inPreparationColor;
      case CustomerFacingColorSlot.callingNow:
        return columnHeaderColors.callingNowColor;
      case CustomerFacingColorSlot.readyQueue:
        return columnHeaderColors.readyQueueColor;
      case CustomerFacingColorSlot.cardBackground:
        return cardTheme.cardBackgroundColor;
      case CustomerFacingColorSlot.cardBorder:
        return cardTheme.cardBorderColor;
      case CustomerFacingColorSlot.cardText:
        return cardTheme.cardTextColor;
    }
  }

  /// Nova configuração com [slot] valendo [color] — passar `null` devolve
  /// aquele campo para o automático.
  ///
  /// Substitui um `copyWith` tradicional nas cores: com campos anuláveis, o
  /// `copyWith` não consegue distinguir "não mexe nesse campo" de "volta esse
  /// campo pro automático" sem um valor-sentinela. Uma cor por chamada
  /// resolve isso sem gambiarra — e é exatamente como a UI edita, uma de cada
  /// vez.
  CustomerFacingThemeConfig withColor(
      CustomerFacingColorSlot slot, Color? color) {
    switch (slot) {
      case CustomerFacingColorSlot.background:
        return _copy(backgroundColor: color, clearBackground: color == null);
      case CustomerFacingColorSlot.headerText:
        return _copy(headerTextColor: color, clearHeaderText: color == null);
      case CustomerFacingColorSlot.inPreparation:
        return _copy(
          columnHeaderColors: CustomerFacingColumnHeaderColors(
            inPreparationColor: color,
            callingNowColor: columnHeaderColors.callingNowColor,
            readyQueueColor: columnHeaderColors.readyQueueColor,
          ),
        );
      case CustomerFacingColorSlot.callingNow:
        return _copy(
          columnHeaderColors: CustomerFacingColumnHeaderColors(
            inPreparationColor: columnHeaderColors.inPreparationColor,
            callingNowColor: color,
            readyQueueColor: columnHeaderColors.readyQueueColor,
          ),
        );
      case CustomerFacingColorSlot.readyQueue:
        return _copy(
          columnHeaderColors: CustomerFacingColumnHeaderColors(
            inPreparationColor: columnHeaderColors.inPreparationColor,
            callingNowColor: columnHeaderColors.callingNowColor,
            readyQueueColor: color,
          ),
        );
      case CustomerFacingColorSlot.cardBackground:
        return _copy(
          cardTheme: CustomerFacingCardTheme(
            cardBackgroundColor: color,
            cardBorderColor: cardTheme.cardBorderColor,
            cardTextColor: cardTheme.cardTextColor,
            cardBorderRadius: cardTheme.cardBorderRadius,
          ),
        );
      case CustomerFacingColorSlot.cardBorder:
        return _copy(
          cardTheme: CustomerFacingCardTheme(
            cardBackgroundColor: cardTheme.cardBackgroundColor,
            cardBorderColor: color,
            cardTextColor: cardTheme.cardTextColor,
            cardBorderRadius: cardTheme.cardBorderRadius,
          ),
        );
      case CustomerFacingColorSlot.cardText:
        return _copy(
          cardTheme: CustomerFacingCardTheme(
            cardBackgroundColor: cardTheme.cardBackgroundColor,
            cardBorderColor: cardTheme.cardBorderColor,
            cardTextColor: color,
            cardBorderRadius: cardTheme.cardBorderRadius,
          ),
        );
    }
  }

  /// Novo raio de borda dos cards, já limitado à faixa segura
  /// (0 a [CustomerFacingCardTheme.maxCardBorderRadius]).
  CustomerFacingThemeConfig withCardBorderRadius(double radius) {
    return _copy(
      cardTheme: CustomerFacingCardTheme(
        cardBackgroundColor: cardTheme.cardBackgroundColor,
        cardBorderColor: cardTheme.cardBorderColor,
        cardTextColor: cardTheme.cardTextColor,
        cardBorderRadius:
            radius.clamp(0.0, CustomerFacingCardTheme.maxCardBorderRadius),
      ),
    );
  }

  CustomerFacingThemeConfig _copy({
    Color? backgroundColor,
    bool clearBackground = false,
    Color? headerTextColor,
    bool clearHeaderText = false,
    CustomerFacingColumnHeaderColors? columnHeaderColors,
    CustomerFacingCardTheme? cardTheme,
  }) {
    return CustomerFacingThemeConfig(
      backgroundColor:
          clearBackground ? null : backgroundColor ?? this.backgroundColor,
      headerTextColor:
          clearHeaderText ? null : headerTextColor ?? this.headerTextColor,
      columnHeaderColors: columnHeaderColors ?? this.columnHeaderColors,
      cardTheme: cardTheme ?? this.cardTheme,
    );
  }

  /// Transforma a configuração (cheia de `null` = automático) na paleta
  /// concreta que a tela desenha, usando [themeColors] como base dos campos
  /// não personalizados.
  ///
  /// É o único lugar do app que decide um fallback do Painel: a tela real e o
  /// preview das Configurações chamam este mesmo método, então é impossível o
  /// preview mostrar uma cor e o Painel outra.
  CustomerFacingPalette resolve(AppColors themeColors) {
    final background = backgroundColor ?? themeColors.backgroundColor;

    // Quando o fundo foi personalizado, as cores automáticas restantes seguem
    // a LUMINÂNCIA desse fundo — não o tema do app. Sem isso, um fundo escuro
    // escolhido enquanto o app está no tema claro deixaria texto quase preto
    // sobre fundo quase preto: o Painel ficaria ilegível por uma combinação
    // que o usuário nem escolheu diretamente. Sem personalização nenhuma,
    // `background` é o próprio fundo do tema, então esta conta devolve
    // exatamente a paleta do tema ativo e nada muda.
    final base =
        background.computeLuminance() < 0.35 ? AppColors.dark : AppColors.light;

    final headerText = headerTextColor ?? themeColors.accentColor;

    return CustomerFacingPalette(
      background: background,
      headerText: headerText,
      // O relógio acompanha o título quando o título foi personalizado (é uma
      // cor só de cabeçalho, como pede a configuração), mas continua discreto
      // no automático.
      clockText: headerTextColor == null
          ? base.textSecondaryColor
          : headerText.withValues(alpha: 0.78),
      inPreparation: columnHeaderColors.inPreparationColor ??
          CustomerFacingColumnHeaderColors.defaultInPreparationColor,
      callingNow: columnHeaderColors.callingNowColor ??
          CustomerFacingColumnHeaderColors.defaultCallingNowColor,
      readyQueue: columnHeaderColors.readyQueueColor ??
          CustomerFacingColumnHeaderColors.defaultReadyQueueColor,
      cardBackground: cardTheme.cardBackgroundColor ?? base.cardColor,
      cardBorderOverride: cardTheme.cardBorderColor,
      cardTextOverride: cardTheme.cardTextColor,
      cardBorderRadius: cardTheme.cardBorderRadius,
      watermarkInk: _watermarkInkOn(background, base),
      mutedText: base.textSecondaryColor,
      bodyText: base.textColor,
      dividerColor: base.borderColor,
    );
  }

  Map<String, dynamic> toJson() => {
        'backgroundColor': _colorToArgb(backgroundColor),
        'headerTextColor': _colorToArgb(headerTextColor),
        'columnHeaderColors': columnHeaderColors.toJson(),
        'cardTheme': cardTheme.toJson(),
      };

  /// Lê o JSON salvo tolerando qualquer formato inesperado (chave que não
  /// existe mais, tipo trocado, valor fora da faixa): cada campo que não dá
  /// para entender volta ao automático, em vez de derrubar a leitura inteira
  /// — uma personalização gravada por outra versão do app nunca deixa o
  /// Painel sem abrir.
  factory CustomerFacingThemeConfig.fromJson(Map<String, dynamic> json) {
    final rawColumns = json['columnHeaderColors'];
    final rawCard = json['cardTheme'];
    return CustomerFacingThemeConfig(
      backgroundColor: _colorFromArgb(json['backgroundColor']),
      headerTextColor: _colorFromArgb(json['headerTextColor']),
      columnHeaderColors: rawColumns is Map<String, dynamic>
          ? CustomerFacingColumnHeaderColors.fromJson(rawColumns)
          : const CustomerFacingColumnHeaderColors(),
      cardTheme: rawCard is Map<String, dynamic>
          ? CustomerFacingCardTheme.fromJson(rawCard)
          : const CustomerFacingCardTheme(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CustomerFacingThemeConfig &&
      other.backgroundColor == backgroundColor &&
      other.headerTextColor == headerTextColor &&
      other.columnHeaderColors == columnHeaderColors &&
      other.cardTheme == cardTheme;

  @override
  int get hashCode => Object.hash(
      backgroundColor, headerTextColor, columnHeaderColors, cardTheme);
}

/// Paleta já resolvida do Painel: nenhuma cor obrigatória aqui é `null`,
/// então nem a tela nem o preview precisam saber o que era automático e o que
/// foi escolhido pelo usuário.
@immutable
class CustomerFacingPalette {
  final Color background;
  final Color headerText;
  final Color clockText;
  final Color inPreparation;
  final Color callingNow;
  final Color readyQueue;
  final Color cardBackground;

  /// Cor fixa de borda/texto dos cards quando o usuário escolheu uma; `null`
  /// mantém o comportamento histórico de cada card usar a cor da sua coluna
  /// (ver [cardBorderFor] e [cardTextFor]).
  final Color? cardBorderOverride;
  final Color? cardTextOverride;

  final double cardBorderRadius;

  /// Tinta da assinatura "Solução Sistemas" no rodapé. **Não é
  /// personalizável de propósito** — ver [_watermarkInkOn].
  final Color watermarkInk;

  /// Textos de apoio que não são configuráveis (estados vazios, rótulo
  /// "PEDIDO", divisórias) — vêm da paleta compatível com o fundo em uso.
  final Color mutedText;
  final Color bodyText;
  final Color dividerColor;

  const CustomerFacingPalette({
    required this.background,
    required this.headerText,
    required this.clockText,
    required this.inPreparation,
    required this.callingNow,
    required this.readyQueue,
    required this.cardBackground,
    required this.cardBorderOverride,
    required this.cardTextOverride,
    required this.cardBorderRadius,
    required this.watermarkInk,
    required this.mutedText,
    required this.bodyText,
    required this.dividerColor,
  });

  Color sectionColor(CustomerFacingPanelSection section) {
    switch (section) {
      case CustomerFacingPanelSection.inPreparation:
        return inPreparation;
      case CustomerFacingPanelSection.callingNow:
        return callingNow;
      case CustomerFacingPanelSection.readyQueue:
        return readyQueue;
    }
  }

  Color cardTextFor(Color sectionColor) => cardTextOverride ?? sectionColor;

  Color cardBorderFor(Color sectionColor) =>
      cardBorderOverride ?? sectionColor.withValues(alpha: 0.35);

  /// O card grande de "CHAMANDO AGORA" arredonda proporcionalmente ao raio
  /// escolhido para os cards pequenos — ele é ~2,5x maior, então repetir o
  /// mesmo raio nos dois deixaria o card grande com cara de quadrado ao lado
  /// dos pequenos.
  double get highlightCardBorderRadius => (cardBorderRadius * 2)
      .clamp(0.0, CustomerFacingCardTheme.maxCardBorderRadius * 1.5);
}

/// `#RRGGBB` (ou `#AARRGGBB` quando há transparência) — o formato mostrado e
/// aceito pelo campo hexadecimal das Configurações.
String colorToHex(Color color) {
  final argb = _colorToArgb(color)!;
  final hex = argb.toRadixString(16).padLeft(8, '0').toUpperCase();
  return argb >> 24 == 0xFF ? '#${hex.substring(2)}' : '#$hex';
}

/// Interpreta o que o usuário digitou no campo hexadecimal, aceitando as
/// formas mais comuns (`#RRGGBB`, `RRGGBB`, `#RGB`, `#AARRGGBB`). Devolve
/// `null` enquanto o texto ainda não é uma cor válida — a UI usa isso para
/// não aplicar nada no meio da digitação.
Color? colorFromHex(String input) {
  var hex = input.trim().replaceFirst('#', '').replaceAll(' ', '');
  if (hex.length == 3) {
    // #RGB -> #RRGGBB
    hex = hex.split('').map((c) => '$c$c').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final argb = int.tryParse(hex, radix: 16);
  return argb == null ? null : Color(argb);
}

/// Tinta da assinatura "Solução Sistemas" sobre [background] — sempre a cor
/// contrária, para a marca d'água nunca se camuflar no fundo escolhido.
///
/// Ela é a única cor do Painel que **não** entra na paleta configurável: por
/// mais que o estabelecimento personalize a tela, a assinatura continua
/// legível, porque é calculada a partir do fundo em vez de escolhida.
///
/// O critério é razão de contraste (a fórmula do WCAG), e **não** a inversão
/// dos canais RGB, que é a solução que parece óbvia e falha justamente onde
/// mais importa: o inverso de um cinza médio `#808080` é `#7F7F7F` — a marca
/// d'água sumiria por completo no fundo. Aqui as duas tintas possíveis são
/// medidas contra o fundo e vence a de maior contraste — o que garante pelo
/// menos 4,58:1 em QUALQUER fundo, acima do mínimo de 4,5:1 que o WCAG pede
/// para texto normal (ver [_watermarkLightInk]).
Color _watermarkInkOn(Color background, AppColors base) {
  // Cor de fundo translúcida só existe misturada com o que está atrás dela;
  // é sobre essa mistura que o contraste precisa ser medido.
  final flattened = Color.alphaBlend(background, base.backgroundColor);

  return _contrastRatio(flattened, _watermarkLightInk) >=
          _contrastRatio(flattened, _watermarkDarkInk)
      ? _watermarkLightInk
      : _watermarkDarkInk;
}

/// As duas tintas possíveis da marca d'água — os extremos do espectro, e não
/// as cores de texto do tema.
///
/// Com só duas opções, o pior fundo possível é o cinza de luminância ~0,18,
/// onde as duas empatam. Branco e preto puros entregam 4,58:1 ali, acima do
/// mínimo de 4,5:1 do WCAG. Usar o quase-preto do design system (`#0F172A`)
/// no lugar do preto parece mais elegante e derruba esse pior caso para
/// 4,41:1 — sacrificaria justamente a garantia que esta cor existe para dar.
const _watermarkLightInk = Color(0xFFFFFFFF);
const _watermarkDarkInk = Color(0xFF000000);

/// Razão de contraste do WCAG entre duas cores: 1,0 = idênticas, 21,0 =
/// preto contra branco.
double _contrastRatio(Color a, Color b) {
  final luminanceA = a.computeLuminance();
  final luminanceB = b.computeLuminance();
  return luminanceA > luminanceB
      ? (luminanceA + 0.05) / (luminanceB + 0.05)
      : (luminanceB + 0.05) / (luminanceA + 0.05);
}

/// Os canais da cor em 0-255, que é como o olho (e o ajuste fino RGB das
/// Configurações) pensa em cor.
///
/// O Flutter 3.27 passou a guardar cada componente como `double` 0..1 (`.r`,
/// `.g`, `.b`, `.a`) e deprecou `.red`/`.green`/`.blue`/`.alpha`. A conversão
/// mora aqui, num lugar só, com o mesmo arredondamento que grava a cor no
/// JSON — senão um canal ajustado no slider poderia voltar do disco com um
/// valor diferente do que estava na tela.
extension ColorChannels on Color {
  int get redByte => _channelToByte(r);
  int get greenByte => _channelToByte(g);
  int get blueByte => _channelToByte(b);
  int get alphaByte => _channelToByte(a);
}

int _channelToByte(double component) => (component * 255).round().clamp(0, 255);

/// Cor -> inteiro ARGB para o JSON. Escrito na mão porque `Color.value` está
/// deprecado no Flutter 3.27 (cada canal virou ponto flutuante) e o
/// substituto oficial `toARGB32()` só existe a partir do 3.29.
int? _colorToArgb(Color? color) {
  if (color == null) return null;
  return color.alphaByte << 24 |
      color.redByte << 16 |
      color.greenByte << 8 |
      color.blueByte;
}

Color? _colorFromArgb(Object? raw) {
  if (raw is! int) return null;
  if (raw < 0 || raw > 0xFFFFFFFF) return null;
  return Color(raw);
}
