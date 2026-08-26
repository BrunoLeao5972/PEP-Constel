import 'package:flutter/material.dart';

import '../theme/settings_tokens.dart';

/// Um grupo de configurações dentro de um card, com cabeçalho próprio.
///
/// É a unidade de leitura da tela: antes, todas as seções eram divisórias
/// horizontais numa coluna única, e a pessoa precisava rolar lendo títulos
/// soltos para descobrir onde uma seção terminava e a outra começava. Com
/// borda e fundo próprios, o agrupamento fica visível de longe — e é o que
/// permite o layout de duas colunas fazer sentido.
class SettingsSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;

  /// Uma linha dizendo pra que serve a seção. Não é decoração: metade das
  /// dúvidas de instalação em campo é sobre o que cada opção faz.
  final String? subtitle;

  final Widget child;

  /// Faz o card ocupar toda a altura disponível e o [child] esticar dentro
  /// dele — usado pelo preview do Painel, que precisa ficar fixo na tela.
  final bool fillHeight;

  const SettingsSectionCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
    this.fillHeight = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = SettingsTokens.of(context);

    return Container(
      decoration: BoxDecoration(
        color: tokens.cardBackground,
        borderRadius: BorderRadius.circular(SettingsTokens.cardRadius),
        border: Border.all(color: tokens.cardBorder),
      ),
      padding: const EdgeInsets.all(SettingsTokens.cardPadding),
      child: Column(
        mainAxisSize: fillHeight ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: tokens.primaryAction),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: tokens.secondaryText,
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (fillHeight) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

/// Distribui os cards em duas colunas no desktop e numa só em telas
/// estreitas.
///
/// São duas `Column` lado a lado, e não um `GridView`: os cards têm alturas
/// bem diferentes (um switch contra um formulário inteiro), e uma grade de
/// verdade esticaria todos à altura do maior, deixando buracos enormes.
class SettingsCardGrid extends StatelessWidget {
  final List<Widget> children;

  const SettingsCardGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < SettingsTokens.twoColumnBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _withSpacing(children),
          );
        }

        // Alternado (0, 2, 4... à esquerda; 1, 3, 5... à direita) para a
        // ordem de leitura em zigue-zague bater com a ordem em que os cards
        // foram declarados.
        final left = <Widget>[];
        final right = <Widget>[];
        for (var i = 0; i < children.length; i++) {
          (i.isEven ? left : right).add(children[i]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _withSpacing(left),
              ),
            ),
            const SizedBox(width: SettingsTokens.cardSpacing),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _withSpacing(right),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _withSpacing(List<Widget> cards) {
    final spaced = <Widget>[];
    for (var i = 0; i < cards.length; i++) {
      if (i > 0) spaced.add(const SizedBox(height: SettingsTokens.cardSpacing));
      spaced.add(cards[i]);
    }
    return spaced;
  }
}
