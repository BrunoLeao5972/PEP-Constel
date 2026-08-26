import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/customer_facing_theme_config.dart';
import '../../../../core/config/customer_facing_theme_config_provider.dart';
import '../../../../core/theme/app_colors.dart';

/// Miniatura viva do Painel Chamador, para as Configurações.
///
/// Observa o mesmo `customerFacingThemeConfigProvider` da tela real e resolve
/// as cores com o mesmo [CustomerFacingThemeConfig.resolve] — então qualquer
/// toque num preset repinta esta miniatura no mesmo frame, e o que aparece
/// aqui é, por construção, o que vai aparecer na TV do salão.
///
/// Os pedidos são de mentira ("0002", "Mesa 04"): o objetivo é o cliente
/// conseguir escolher as cores sem precisar de movimento na cozinha nem sair
/// da tela de Configurações.
class CustomerFacingPreviewWidget extends ConsumerWidget {
  /// Paleta de tema contra a qual resolver o que ainda está em "automático".
  /// `null` usa o tema ativo do app — passar [AppColors.dark] ou
  /// [AppColors.light] permite conferir como o Painel fica no OUTRO modo sem
  /// trocar o tema do app inteiro (a TV do salão pode estar no modo oposto ao
  /// do computador em que se está configurando).
  final AppColors? themeColors;

  const CustomerFacingPreviewWidget({super.key, this.themeColors});

  /// Tamanho virtual em que a miniatura é desenhada; o `FittedBox` abaixo
  /// encaixa isso na largura que a tela de Configurações der. Desenhar num
  /// tamanho fixo e escalar o conjunto (em vez de recalcular cada fonte)
  /// mantém as proporções idênticas às do Painel de verdade em qualquer
  /// espaço — inclusive no celular.
  static const _designWidth = 640.0;
  static const _designHeight = 380.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref
        .watch(customerFacingThemeConfigProvider)
        .resolve(themeColors ?? context.colors);

    return LayoutBuilder(
      builder: (context, constraints) {
        // A miniatura tem proporção fixa: normalmente a largura manda, mas
        // quando ela mora num card de altura definida (o preview fixo ao
        // lado dos controles), quem manda é a altura — senão ela estouraria
        // o card em janelas baixas.
        var width = constraints.maxWidth;
        var height = width * (_designHeight / _designWidth);
        if (constraints.maxHeight.isFinite && height > constraints.maxHeight) {
          height = constraints.maxHeight;
          width = height * (_designWidth / _designHeight);
        }

        return SizedBox(
          width: width,
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: _designWidth,
                height: _designHeight,
                child: _PreviewPanel(palette: palette),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  final CustomerFacingPalette palette;

  const _PreviewPanel({required this.palette});

  // Pedidos de exemplo — cobrem os dois formatos de rótulo que o Painel
  // mostra na prática: senha do PDV/KDS ("0002") e modalidade + localizador
  // ("Mesa 04").
  static const _preparing = ['0002', 'Mesa 04', '0003', 'Cartão 12'];
  static const _readyQueue = ['0001', 'Mesa 07'];
  static const _callingNow = '0002';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.background,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          Text(
            'ACOMPANHE SEU PEDIDO',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: palette.headerText,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '12:45',
            style: TextStyle(fontSize: 12, color: palette.clockText),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _PreviewSection(
                    section: CustomerFacingPanelSection.inPreparation,
                    palette: palette,
                    child: _PreviewCardsGrid(
                      labels: _preparing,
                      section: CustomerFacingPanelSection.inPreparation,
                      palette: palette,
                    ),
                  ),
                ),
                _PreviewDivider(palette: palette),
                Expanded(
                  flex: 2,
                  child: _PreviewSection(
                    section: CustomerFacingPanelSection.callingNow,
                    palette: palette,
                    child: Center(
                      child: _PreviewHighlightCard(palette: palette),
                    ),
                  ),
                ),
                _PreviewDivider(palette: palette),
                Expanded(
                  flex: 3,
                  child: _PreviewSection(
                    section: CustomerFacingPanelSection.readyQueue,
                    palette: palette,
                    child: _PreviewCardsGrid(
                      labels: _readyQueue,
                      section: CustomerFacingPanelSection.readyQueue,
                      palette: palette,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Solução Sistemas - A sua cozinha ainda mais eficiente',
            style: TextStyle(fontSize: 9, color: palette.watermarkInk),
          ),
        ],
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  final CustomerFacingPanelSection section;
  final CustomerFacingPalette palette;
  final Widget child;

  const _PreviewSection({
    required this.section,
    required this.palette,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final color = palette.sectionColor(section);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mesmo IconData da tela real (vem do enum compartilhado):
                // é o que garante que o ícone escolhido aqui é o que o
                // cliente vê no salão.
                Icon(section.icon, color: color, size: 15),
                const SizedBox(width: 5),
                Text(
                  section.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _PreviewCardsGrid extends StatelessWidget {
  final List<String> labels;
  final CustomerFacingPanelSection section;
  final CustomerFacingPalette palette;

  const _PreviewCardsGrid({
    required this.labels,
    required this.section,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final color = palette.sectionColor(section);

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: labels.length,
      itemBuilder: (context, index) {
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: palette.cardBackground,
            borderRadius: BorderRadius.circular(palette.cardBorderRadius),
            border: Border.all(color: palette.cardBorderFor(color), width: 1.4),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              labels[index],
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: palette.cardTextFor(color),
                height: 1,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PreviewHighlightCard extends StatelessWidget {
  final CustomerFacingPalette palette;

  const _PreviewHighlightCard({required this.palette});

  @override
  Widget build(BuildContext context) {
    final color = palette.callingNow;

    return Container(
      width: 116,
      height: 108,
      decoration: BoxDecoration(
        color: palette.cardBackground,
        borderRadius: BorderRadius.circular(palette.highlightCardBorderRadius),
        border: Border.all(
          color: palette.cardBorderOverride ?? color,
          width: 1.6,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.18),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'PEDIDO',
            style: TextStyle(
              color: palette.mutedText,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _PreviewPanel._callingNow,
                style: TextStyle(
                  color: palette.cardTextFor(color),
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Pronto para retirada',
            style: TextStyle(
              color: palette.bodyText.withValues(alpha: 0.85),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewDivider extends StatelessWidget {
  final CustomerFacingPalette palette;

  const _PreviewDivider({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: palette.dividerColor);
  }
}
