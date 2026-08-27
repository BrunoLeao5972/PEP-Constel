import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

  /// Folga só na altura intrínseca relatada (ver [_IntrinsicHeightSlack]) —
  /// cobre a imprecisão conhecida do Flutter ao medir a altura intrínseca de
  /// `TextField`/`InputDecorator` (pode subestimar alguns pixels conforme
  /// fonte/DPI/plataforma), sem inflar o card no layout de verdade.
  static const _intrinsicHeightSlack = 16.0;

  @override
  Widget build(BuildContext context) {
    final tokens = SettingsTokens.of(context);

    final card = Container(
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

    if (fillHeight) return card;

    // Só entra em jogo quando o card divide linha com outro mais alto (ver
    // SettingsCardGrid, que iguala os dois via IntrinsicHeight): sem a
    // folga, um card com TextField podia relatar precisar de menos altura
    // intrínseca do que realmente precisa no layout de verdade — a linha
    // saía travada exatamente no limite, e QUALQUER coisa reduzindo essa
    // margem quase nula (fonte carregando depois do primeiro frame, DPI de
    // outra máquina) estourava o card por poucos pixels. Não dá pra resolver
    // detectando "estou apertado" em tempo real — um LayoutBuilder aqui
    // quebraria o próprio IntrinsicHeight, que exige que todo descendente
    // saiba responder sua altura intrínseca sem rodar um layout de verdade.
    return _IntrinsicHeightSlack(
      extraIntrinsicHeight: _intrinsicHeightSlack,
      child: card,
    );
  }
}

/// Relata `extraIntrinsicHeight` A MAIS do que [child] pediria, só nas
/// consultas de altura intrínseca (as que `IntrinsicHeight` usa pra decidir
/// a altura de uma linha) — no layout de verdade, [child] recebe exatamente
/// as constraints que chegam, sem folga nenhuma, então isto não muda o
/// tamanho real de nada.
///
/// Sem isso, dar folga direto no `Column` do card (um `SizedBox` extra
/// dentro dele, por exemplo) não resolve a imprecisão do TextField: a folga
/// entraria IGUALMENTE na altura intrínseca relatada e na altura real
/// pedida, cancelando-se — o cálculo seguinte mostra por quê. Sendo `R` a
/// altura real que o card precisa e `R - g` o que ele relata de intrínseca
/// (`g` = o quanto o Flutter subestima), somar `S` dentro do card dá
/// `(R - g + S)` de intrínseca contra `(R + S)` de real: a diferença
/// continua `g`, não importa o valor de `S`. Aqui a folga só entra do lado
/// da consulta intrínseca, então ela de fato reduz essa diferença.
class _IntrinsicHeightSlack extends SingleChildRenderObjectWidget {
  final double extraIntrinsicHeight;

  const _IntrinsicHeightSlack({
    required this.extraIntrinsicHeight,
    required Widget super.child,
  });

  @override
  _RenderIntrinsicHeightSlack createRenderObject(BuildContext context) {
    return _RenderIntrinsicHeightSlack(extraIntrinsicHeight);
  }

  @override
  void updateRenderObject(
      BuildContext context, _RenderIntrinsicHeightSlack renderObject) {
    renderObject.extraIntrinsicHeight = extraIntrinsicHeight;
  }
}

class _RenderIntrinsicHeightSlack extends RenderProxyBox {
  _RenderIntrinsicHeightSlack(this.extraIntrinsicHeight);

  double extraIntrinsicHeight;

  @override
  double computeMinIntrinsicHeight(double width) {
    final base = super.computeMinIntrinsicHeight(width);
    return base.isFinite ? base + extraIntrinsicHeight : base;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final base = super.computeMaxIntrinsicHeight(width);
    return base.isFinite ? base + extraIntrinsicHeight : base;
  }
}

/// Distribui os cards em duas colunas no desktop e numa só em telas
/// estreitas — cada LINHA de duas colunas com a mesma altura (a do card
/// mais alto do par), e não cada card "abraçando" só o próprio conteúdo.
///
/// A versão anterior jogava os cards em duas colunas que ACUMULAVAM altura
/// de forma independente (0, 2, 4... numa coluna; 1, 3, 5... na outra). Com
/// cards de conteúdo bem diferente (um switch contra um formulário inteiro),
/// isso não só deixava pares visualmente desalinhados como, com um número
/// ímpar de cards, sobrava um card sozinho numa coluna com um vão vazio do
/// lado — a "grade" parava de parecer grade a partir da segunda linha.
/// Montar linha por linha (aqui) resolve os dois problemas de uma vez.
class SettingsCardGrid extends StatelessWidget {
  final List<Widget> children;

  const SettingsCardGrid({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            constraints.maxWidth < SettingsTokens.twoColumnBreakpoint ? 1 : 2;

        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += columns) {
          if (rows.isNotEmpty) {
            rows.add(const SizedBox(height: SettingsTokens.cardSpacing));
          }
          rows.add(_buildRow(children.skip(i).take(columns).toList()));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        );
      },
    );
  }

  Widget _buildRow(List<Widget> rowCards) {
    // Coluna única, ou último card sobrando numa linha ímpar: ocupa a linha
    // inteira em vez de ficar preso numa metade ao lado do vazio.
    if (rowCards.length == 1) return rowCards.first;

    // IntrinsicHeight mede a altura que cada card pediria por conta própria
    // e trava a linha inteira nessa medida (a do mais alto) — é o mesmo
    // truque usado pra igualar colunas num layout CSS, só que em Flutter.
    // Nenhum card do app usa lista/grade rolável por dentro (o que quebraria
    // essa medição), então é seguro aqui.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rowCards.length; i++) ...[
            if (i > 0) const SizedBox(width: SettingsTokens.cardSpacing),
            Expanded(child: rowCards[i]),
          ],
        ],
      ),
    );
  }
}
