import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/customer_facing_theme_config.dart';
import '../../../../core/config/customer_facing_theme_config_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../theme/settings_tokens.dart';
import 'customer_facing_preview_widget.dart';
import 'settings_section_card.dart';

/// Seção "Personalização do Painel Chamador" das Configurações: os controles
/// de cor à esquerda e o preview vivo à direita (empilhados no celular).
///
/// Não tem botão "Salvar" de propósito — cada toque já grava e já aparece no
/// preview e na tela do Painel. Um botão de salvar aqui só criaria o estado
/// intermediário "mudei mas não salvei", justamente o que o preview existe
/// para eliminar.
class CustomerFacingThemeSection extends ConsumerStatefulWidget {
  const CustomerFacingThemeSection({super.key});

  @override
  ConsumerState<CustomerFacingThemeSection> createState() =>
      _CustomerFacingThemeSectionState();
}

class _CustomerFacingThemeSectionState
    extends ConsumerState<CustomerFacingThemeSection> {
  /// Largura a partir da qual controles e preview cabem lado a lado.
  static const _sideBySideBreakpoint = 820.0;

  /// Qual cor está aberta para edição. É estado 100% efêmero de UI (não vai
  /// pro Riverpod de propósito): não é dado compartilhado, morre junto com a
  /// tela e não interessa a mais ninguém.
  CustomerFacingColorSlot? _openSlot;

  /// Tema contra o qual o preview resolve as cores não personalizadas —
  /// começa no tema atual do app e pode ser trocado só aqui, sem mexer no
  /// tema do app (a TV do salão pode estar no modo oposto ao do computador
  /// onde alguém está configurando).
  Brightness? _previewBrightness;

  final _hexController = TextEditingController();

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  /// Abre (ou fecha) o editor de uma cor, já com o campo hexadecimal no valor
  /// que aquele campo tem hoje — personalizado ou vindo do tema. Abrir vazio
  /// obrigava a pessoa a descobrir o HEX atual em outro lugar antes de
  /// conseguir ajustá-lo.
  void _toggleSlot(CustomerFacingColorSlot slot, Color activeColor) {
    setState(() {
      if (_openSlot == slot) {
        _openSlot = null;
        return;
      }
      _openSlot = slot;
      _hexController.text = colorToHex(activeColor);
    });
  }

  /// Aplica uma cor vinda de um preset, do ajuste fino RGB ou do
  /// "Automático", e deixa o campo hexadecimal refletindo o novo valor — é
  /// esta linha que mantém sliders, HEX e preview dizendo sempre a mesma
  /// coisa, independente de por onde a cor entrou.
  ///
  /// [live] marca o valor que ainda está sendo arrastado: aplica na tela na
  /// hora, mas adia a gravação em disco (ver
  /// [CustomerFacingThemeConfigNotifier.setColorLive]).
  void _applyColor(CustomerFacingColorSlot slot, Color? color,
      {bool live = false}) {
    final notifier = ref.read(customerFacingThemeConfigProvider.notifier);
    if (live) {
      notifier.setColorLive(slot, color);
    } else {
      notifier.setColor(slot, color);
    }

    final text = color == null ? '' : colorToHex(color);
    if (_hexController.text == text) return;
    _hexController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Digitação no campo hexadecimal: aplica só quando o texto já é uma cor
  /// válida e **não** mexe no controller (isso jogaria o cursor pro fim a
  /// cada tecla). Enquanto o valor está pela metade, a última cor válida
  /// continua valendo.
  void _onHexChanged(CustomerFacingColorSlot slot, String raw) {
    final color = colorFromHex(raw);
    if (color != null) {
      ref
          .read(customerFacingThemeConfigProvider.notifier)
          .setColor(slot, color);
    }
    setState(() {}); // só para ligar/desligar o aviso de formato do campo
  }

  /// Abre o ajuste fino RGB da cor de [info].
  ///
  /// O diálogo já começa na cor que o Painel está usando (mesmo que ela venha
  /// do tema), aplica cada movimento de slider na hora e, no "Cancelar",
  /// devolve exatamente o que havia antes — inclusive o estado "sem cor
  /// escolhida", que um simples "guardar a cor de antes" perderia.
  Future<void> _openRgbPicker(
      _SlotInfo info, Color? chosen, Color activeColor) {
    return showDialog<void>(
      context: context,
      // Barreira mais leve que o padrão do Material: o preview atrás continua
      // legível enquanto os sliders andam, que é o ponto do ajuste fino.
      barrierColor: const Color(0x66000000),
      builder: (_) => _RgbPickerDialog(
        title: info.label,
        initialColor: activeColor,
        onChanged: (color) => _applyColor(info.slot, color, live: true),
        onCommitted: (color) => _applyColor(info.slot, color),
        onCancelled: () => _applyColor(info.slot, chosen),
      ),
    );
  }

  Future<void> _restoreDefaults() async {
    await ref
        .read(customerFacingThemeConfigProvider.notifier)
        .restoreDefaults();
    if (!mounted) return;
    setState(() {
      _openSlot = null;
      _hexController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Painel Chamador de volta às cores padrão.'),
        backgroundColor: context.colors.successColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(customerFacingThemeConfigProvider);
    final previewBrightness =
        _previewBrightness ?? Theme.of(context).brightness;
    final previewTheme =
        previewBrightness == Brightness.dark ? AppColors.dark : AppColors.light;
    final palette = config.resolve(previewTheme);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Só dá para prender o preview se a aba disser qual é a altura dela.
        // Dentro de um scroll (altura infinita) não existe "ficar parado":
        // aí os dois cards viram uma coluna que rola junto.
        final hasBoundedHeight = constraints.maxHeight.isFinite;
        final isWide = constraints.maxWidth >= _sideBySideBreakpoint;

        // Com altura definida e espaço horizontal, os controles rolam por
        // dentro do próprio card — é o que deixa o preview parado ao lado.
        final split = hasBoundedHeight && isWide;
        final controls = _buildControls(context, config, palette);

        final controlsCard = SettingsSectionCard(
          icon: Icons.palette_outlined,
          title: 'Cores do Painel',
          subtitle: 'Cada ajuste aparece na hora no preview e na aba Painel, '
              'vale no Windows e no Android, e fica salvo neste aparelho — '
              'não precisa salvar.',
          fillHeight: split,
          child: split ? SingleChildScrollView(child: controls) : controls,
        );

        final previewCard = SettingsSectionCard(
          icon: Icons.tv_outlined,
          title: 'Preview em tempo real',
          subtitle: 'É o mesmo desenho da tela do cliente, com as mesmas '
              'cores e ícones — só com pedidos de exemplo.',
          fillHeight: split,
          child: _buildPreviewPane(
            context,
            previewBrightness,
            expandPreview: split,
          ),
        );

        if (split) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: controlsCard),
              const SizedBox(width: SettingsTokens.cardSpacing),
              Expanded(child: previewCard),
            ],
          );
        }

        // Estreito: preview em cima (é o que se quer olhar) e controles
        // embaixo, tudo num scroll só.
        final stacked = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            previewCard,
            const SizedBox(height: SettingsTokens.cardSpacing),
            controlsCard,
          ],
        );

        return hasBoundedHeight
            ? SingleChildScrollView(child: stacked)
            : stacked;
      },
    );
  }

  Widget _buildPreviewPane(
    BuildContext context,
    Brightness previewBrightness, {
    required bool expandPreview,
  }) {
    final tokens = SettingsTokens.of(context);

    final preview = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: CustomerFacingPreviewWidget(
          themeColors: previewBrightness == Brightness.dark
              ? AppColors.dark
              : AppColors.light,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Expandido, o preview recebe uma altura definida e se encaixa nela
        // (a miniatura tem proporção fixa e se ajusta sozinha); no modo
        // empilhado ele usa a altura que a largura pedir.
        if (expandPreview)
          Expanded(child: Align(alignment: Alignment.topCenter, child: preview))
        else
          preview,
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Ver como fica no tema:',
                style: TextStyle(
                    color: context.colors.textSecondaryColor, fontSize: 12),
              ),
            ),
            SegmentedButton<Brightness>(
              segments: const [
                ButtonSegment(
                  value: Brightness.dark,
                  icon: Icon(Icons.dark_mode_outlined, size: 16),
                  label: Text('Escuro'),
                ),
                ButtonSegment(
                  value: Brightness.light,
                  icon: Icon(Icons.light_mode_outlined, size: 16),
                  label: Text('Claro'),
                ),
              ],
              selected: {previewBrightness},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _previewBrightness = selection.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'As cores que você não personalizou acompanham o tema; as '
          'escolhidas por você valem nos dois. A assinatura do rodapé fica '
          'fora da paleta de propósito: ela sai sempre na cor contrária ao '
          'fundo, para nunca se camuflar.',
          style:
              TextStyle(color: context.colors.textSecondaryColor, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildControls(
    BuildContext context,
    CustomerFacingThemeConfig config,
    CustomerFacingPalette palette,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in _slotGroups) ...[
          Text(
            group.title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: context.colors.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 4),
          for (final slot in group.slots)
            _buildSlotTile(context, slot, config, palette),
          const SizedBox(height: 18),
        ],
        _buildRadiusControl(context, config),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: config.isDefault ? null : _restoreDefaults,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('Restaurar Padrões'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSlotTile(
    BuildContext context,
    _SlotInfo info,
    CustomerFacingThemeConfig config,
    CustomerFacingPalette palette,
  ) {
    final chosen = config.colorFor(info.slot);
    final isOpen = _openSlot == info.slot;

    // A cor que o Painel está usando AGORA para este campo — a escolhida pelo
    // usuário ou, enquanto não houver uma, a que vem do tema. É ela que
    // aparece no quadradinho, no subtítulo em HEX e como ponto de partida do
    // ajuste fino: um valor só, em vez de o rótulo falar de uma coisa e o
    // slider abrir em outra.
    final activeColor = info.resolve(palette);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _toggleSlot(info.slot, activeColor),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                _ColorSwatch(color: activeColor, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        colorToHex(activeColor),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.textSecondaryColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isOpen ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: context.colors.textSecondaryColor,
                ),
              ],
            ),
          ),
        ),
        if (isOpen) _buildSlotEditor(context, info, chosen, activeColor),
      ],
    );
  }

  Widget _buildSlotEditor(
    BuildContext context,
    _SlotInfo info,
    Color? chosen,
    Color activeColor,
  ) {
    final typed = _hexController.text.trim();
    final hexIsInvalid = typed.isNotEmpty && colorFromHex(typed) == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: context.colors.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PRESETS DA MARCA',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: context.colors.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _colorPresets)
                Tooltip(
                  message: '${preset.name} (${colorToHex(preset.color)})',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _applyColor(info.slot, preset.color),
                    child: _ColorSwatch(
                      color: preset.color,
                      isSelected: chosen == preset.color,
                      size: 32,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _hexController,
            decoration: InputDecoration(
              labelText: 'Hexadecimal',
              hintText: colorToHex(activeColor),
              isDense: true,
              errorText: hexIsInvalid ? 'Use o formato #RRGGBB' : null,
            ),
            onChanged: (value) => _onHexChanged(info.slot, value),
          ),
          const SizedBox(height: 10),
          // Wrap, e não Row: nos 312 px úteis de um celular os dois botões não
          // cabem lado a lado, e aqui o de baixo simplesmente desce.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openRgbPicker(info, chosen, activeColor),
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Ajuste fino RGB'),
              ),
              TextButton.icon(
                onPressed:
                    chosen == null ? null : () => _applyColor(info.slot, null),
                icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                label: const Text('Automático'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRadiusControl(
      BuildContext context, CustomerFacingThemeConfig config) {
    final radius = config.cardTheme.cardBorderRadius;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FORMATO DOS CARDS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: context.colors.textSecondaryColor,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: radius,
                min: 0,
                max: CustomerFacingCardTheme.maxCardBorderRadius,
                divisions: CustomerFacingCardTheme.maxCardBorderRadius.round(),
                label: '${radius.round()} px',
                activeColor: context.colors.accentColor,
                onChanged: (value) => ref
                    .read(customerFacingThemeConfigProvider.notifier)
                    .setCardBorderRadius(value),
              ),
            ),
            SizedBox(
              width: 54,
              child: Text(
                '${radius.round()} px',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: context.colors.textSecondaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Quadradinho de cor usado tanto na lista de cores quanto nos presets.
///
/// Mostra a cor pura, sem nenhum selo por cima: quem diz de onde ela veio é o
/// HEX no subtítulo, e o quadradinho serve para conferir a cor em si.
class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final double size;

  const _ColorSwatch({
    required this.color,
    required this.size,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected
              ? context.colors.accentColor
              : context.colors.borderColor,
          width: isSelected ? 2.5 : 1.5,
        ),
      ),
    );
  }
}

/// Ajuste fino de uma cor, canal a canal (R, G, B e opacidade), de 0 a 255.
///
/// Os presets resolvem "quero o dourado da marca"; este diálogo resolve "quero
/// aquele dourado, só que um tom menos alaranjado" — que é o pedido que
/// chega quando o estabelecimento tem uma identidade visual própria.
///
/// Cada movimento de slider já vale na tela ([onChanged], enquanto arrasta) e
/// só vira gravação quando o dedo sai ([onCommitted]); [onCancelled] devolve o
/// que havia antes de abrir. Assim o preview atrás do diálogo acompanha o
/// arrasto sem transformar o arrasto em centenas de gravações em disco.
class _RgbPickerDialog extends StatefulWidget {
  final String title;
  final Color initialColor;
  final ValueChanged<Color> onChanged;
  final ValueChanged<Color> onCommitted;
  final VoidCallback onCancelled;

  const _RgbPickerDialog({
    required this.title,
    required this.initialColor,
    required this.onChanged,
    required this.onCommitted,
    required this.onCancelled,
  });

  @override
  State<_RgbPickerDialog> createState() => _RgbPickerDialogState();
}

class _RgbPickerDialogState extends State<_RgbPickerDialog> {
  late int _red;
  late int _green;
  late int _blue;
  late int _alpha;

  @override
  void initState() {
    super.initState();
    _red = widget.initialColor.redByte;
    _green = widget.initialColor.greenByte;
    _blue = widget.initialColor.blueByte;
    _alpha = widget.initialColor.alphaByte;
  }

  Color get _color => Color.fromARGB(_alpha, _red, _green, _blue);

  void _apply(Color color, {required bool committed}) {
    setState(() {
      _red = color.redByte;
      _green = color.greenByte;
      _blue = color.blueByte;
      _alpha = color.alphaByte;
    });
    if (committed) {
      widget.onCommitted(color);
    } else {
      widget.onChanged(color);
    }
  }

  /// Texto do HEX sobre a própria cor. Uma cor com opacidade só existe
  /// misturada com o que está atrás dela, então o contraste é calculado sobre
  /// essa mistura — senão um verde 20% transparente pediria texto branco por
  /// causa do verde, e apareceria branco sobre um fundo quase claro.
  Color _hexTextColor(BuildContext context) {
    final flattened = Color.alphaBlend(_color, context.colors.cardColor);
    return flattened.computeLuminance() < 0.45
        ? AppColors.light.cardColor
        : AppColors.light.textColor;
  }

  @override
  Widget build(BuildContext context) {
    final opaque = Color.fromARGB(255, _red, _green, _blue);

    return AlertDialog(
      backgroundColor: context.colors.cardColor,
      title: Text('Ajuste fino — ${widget.title}'),
      // ConstrainedBox (e não SizedBox de largura fixa): no desktop o diálogo
      // pararia de crescer em 360, e num celular estreito ele encolhe junto
      // com a tela em vez de estourar.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 66,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.colors.borderColor),
                ),
                child: Text(
                  colorToHex(_color),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: _hexTextColor(context),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _ChannelSlider(
                label: 'R',
                value: _red,
                gradientStart: Color.fromARGB(255, 0, _green, _blue),
                gradientEnd: Color.fromARGB(255, 255, _green, _blue),
                onChanged: (value) => _apply(
                    Color.fromARGB(_alpha, value, _green, _blue),
                    committed: false),
                onChangeEnd: (value) => _apply(
                    Color.fromARGB(_alpha, value, _green, _blue),
                    committed: true),
              ),
              _ChannelSlider(
                label: 'G',
                value: _green,
                gradientStart: Color.fromARGB(255, _red, 0, _blue),
                gradientEnd: Color.fromARGB(255, _red, 255, _blue),
                onChanged: (value) => _apply(
                    Color.fromARGB(_alpha, _red, value, _blue),
                    committed: false),
                onChangeEnd: (value) => _apply(
                    Color.fromARGB(_alpha, _red, value, _blue),
                    committed: true),
              ),
              _ChannelSlider(
                label: 'B',
                value: _blue,
                gradientStart: Color.fromARGB(255, _red, _green, 0),
                gradientEnd: Color.fromARGB(255, _red, _green, 255),
                onChanged: (value) => _apply(
                    Color.fromARGB(_alpha, _red, _green, value),
                    committed: false),
                onChangeEnd: (value) => _apply(
                    Color.fromARGB(_alpha, _red, _green, value),
                    committed: true),
              ),
              _ChannelSlider(
                label: 'A',
                value: _alpha,
                gradientStart: opaque.withValues(alpha: 0),
                gradientEnd: opaque,
                onChanged: (value) => _apply(
                    Color.fromARGB(value, _red, _green, _blue),
                    committed: false),
                onChangeEnd: (value) => _apply(
                    Color.fromARGB(value, _red, _green, _blue),
                    committed: true),
              ),
              const SizedBox(height: 4),
              Text(
                'A = opacidade. Em 0 a cor some da tela do cliente.',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textSecondaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onCancelled();
            Navigator.of(context).pop();
          },
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onCommitted(_color);
            Navigator.of(context).pop();
          },
          child: const Text('Concluir'),
        ),
      ],
    );
  }
}

/// Um canal do ajuste fino: faixa com o gradiente do canal, slider por cima e
/// o valor 0-255 do lado.
///
/// O gradiente mostra, antes de arrastar, o que aquele canal vai fazer com a
/// cor ATUAL (as outras duas ficam fixas) — é o que diferencia um ajuste fino
/// de três barras cinzas com números.
class _ChannelSlider extends StatelessWidget {
  final String label;
  final int value;
  final Color gradientStart;
  final Color gradientEnd;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onChangeEnd;

  const _ChannelSlider({
    required this.label,
    required this.value,
    required this.gradientStart,
    required this.gradientEnd,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.colors.textSecondaryColor,
            ),
          ),
        ),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                // Recuo do tamanho do polegar do slider, para o gradiente
                // começar e terminar exatamente onde ele consegue chegar.
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    gradient:
                        LinearGradient(colors: [gradientStart, gradientEnd]),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: context.colors.borderColor),
                  ),
                ),
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 10,
                  // A trilha do próprio slider fica invisível: quem desenha a
                  // faixa é o gradiente atrás.
                  activeTrackColor: const Color(0x00000000),
                  inactiveTrackColor: const Color(0x00000000),
                  // Com 255 divisões, o Material desenharia 256 marquinhas
                  // em cima do gradiente — some com elas: a precisão de 1 em
                  // 1 vem das divisões, não de enxergar cada tique.
                  tickMarkShape: SliderTickMarkShape.noTickMark,
                  thumbColor: context.colors.textColor,
                  overlayColor: context.colors.accentColor.withValues(
                    alpha: 0.14,
                  ),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 9),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 18),
                ),
                child: Slider(
                  value: value.toDouble(),
                  max: 255,
                  divisions: 255,
                  label: '$value',
                  onChanged: (raw) => onChanged(raw.round()),
                  onChangeEnd: (raw) => onChangeEnd(raw.round()),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: TextStyle(
              color: context.colors.textSecondaryColor,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// Rótulo de cada cor configurável e como achar o valor que ela tem hoje.
///
/// Fica na camada de UI (e não no modelo, em `core/config`) porque é texto de
/// tela: o modelo continua sabendo só que a cor pode ser nula.
@immutable
class _SlotInfo {
  final CustomerFacingColorSlot slot;
  final String label;

  /// Cor que o Painel usa hoje para este campo — é o que o quadradinho, o
  /// HEX do subtítulo e o ajuste fino RGB mostram, personalizada ou não.
  final Color Function(CustomerFacingPalette palette) resolve;

  const _SlotInfo({
    required this.slot,
    required this.label,
    required this.resolve,
  });
}

@immutable
class _SlotGroup {
  final String title;
  final List<_SlotInfo> slots;

  const _SlotGroup(this.title, this.slots);
}

final _slotGroups = <_SlotGroup>[
  _SlotGroup('TELA', [
    _SlotInfo(
      slot: CustomerFacingColorSlot.background,
      label: 'Fundo da tela',
      resolve: (palette) => palette.background,
    ),
    _SlotInfo(
      slot: CustomerFacingColorSlot.headerText,
      label: 'Título e relógio',
      resolve: (palette) => palette.headerText,
    ),
  ]),
  _SlotGroup('TÍTULOS E ÍCONES DAS COLUNAS', [
    _SlotInfo(
      slot: CustomerFacingColorSlot.inPreparation,
      label: 'Em preparo',
      resolve: (palette) => palette.inPreparation,
    ),
    _SlotInfo(
      slot: CustomerFacingColorSlot.callingNow,
      label: 'Chamando agora',
      resolve: (palette) => palette.callingNow,
    ),
    _SlotInfo(
      slot: CustomerFacingColorSlot.readyQueue,
      label: 'Fila de prontos',
      resolve: (palette) => palette.readyQueue,
    ),
  ]),
  _SlotGroup('CARDS DE SENHA', [
    _SlotInfo(
      slot: CustomerFacingColorSlot.cardBackground,
      label: 'Fundo dos cards',
      resolve: (palette) => palette.cardBackground,
    ),
    _SlotInfo(
      slot: CustomerFacingColorSlot.cardBorder,
      label: 'Borda dos cards',
      resolve: (palette) =>
          palette.cardBorderOverride ??
          palette.cardBorderFor(palette.callingNow),
    ),
    _SlotInfo(
      slot: CustomerFacingColorSlot.cardText,
      label: 'Número da senha',
      resolve: (palette) => palette.cardTextFor(palette.callingNow),
    ),
  ]),
];

@immutable
class _ColorPreset {
  final String name;
  final Color color;

  const _ColorPreset(this.name, this.color);
}

/// Atalhos de cor: primeiro a paleta da marca (as mesmas de
/// [AppStatusColors], para o Painel não sair do design system sem querer) e
/// depois os neutros de fundo/superfície dos dois temas.
final _colorPresets = <_ColorPreset>[
  const _ColorPreset('Roxo Constel', AppStatusColors.primary),
  const _ColorPreset('Lilás Constel', AppStatusColors.secondary),
  const _ColorPreset('Dourado Constel', AppStatusColors.accent),
  const _ColorPreset('Âmbar', AppStatusColors.warning),
  const _ColorPreset('Verde', AppStatusColors.success),
  const _ColorPreset('Azul', AppStatusColors.info),
  const _ColorPreset('Vermelho', AppStatusColors.error),
  _ColorPreset('Grafite (fundo escuro)', AppColors.dark.backgroundColor),
  _ColorPreset('Chumbo (card escuro)', AppColors.dark.cardColor),
  _ColorPreset('Off-white (fundo claro)', AppColors.light.backgroundColor),
  _ColorPreset('Branco', AppColors.light.cardColor),
  const _ColorPreset('Preto', Color(0xFF000000)),
  _ColorPreset('Cinza claro', AppColors.dark.textColor),
  _ColorPreset('Cinza escuro', AppColors.light.textSecondaryColor),
];
