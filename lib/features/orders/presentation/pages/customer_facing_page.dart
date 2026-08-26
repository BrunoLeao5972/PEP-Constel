import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/config/customer_facing_theme_config.dart';
import '../../../../core/config/customer_facing_theme_config_provider.dart';
import '../../../../core/config/panel_display_config.dart';
import '../../../../core/config/panel_display_config_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/order.dart';
import '../providers/order_caller_provider.dart';
import '../providers/order_provider.dart';

/// Painel Chamador — a única tela do app que quem olha é o CLIENTE, não o
/// operador. Duas consequências que explicam quase todas as decisões daqui:
///
/// 1. **Ela roda em tela alheia**: TV de 55" no salão (Windows), tablet de 10"
///    preso na parede (Android), notebook de 13" no balcão. Nada é medido em
///    pixel fixo — tudo passa por [_PanelMetrics], que deriva uma escala do
///    espaço real disponível, e abaixo de 760 px de largura o layout de três
///    colunas vira empilhado.
/// 2. **A aparência é do estabelecimento**: cores, ícones e cards saem de
///    [customerFacingThemeConfigProvider] (ver Configurações > Personalização
///    do Painel Chamador), sempre resolvidos por
///    [CustomerFacingThemeConfig.resolve] — nunca de `context.colors` direto,
///    senão o preview das Configurações mostraria uma coisa e a tela outra.
class CustomerFacingPage extends ConsumerWidget {
  const CustomerFacingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersStreamProvider);
    final callLabels = ref.watch(orderCallLabelsProvider);
    final panelDisplay = ref.watch(panelDisplayConfigProvider);
    final palette =
        ref.watch(customerFacingThemeConfigProvider).resolve(context.colors);

    return Scaffold(
      backgroundColor: palette.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final metrics = _PanelMetrics.fromConstraints(constraints);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PanelHeader(palette: palette, metrics: metrics),
              Expanded(
                child: ordersAsync.when(
                  data: (allOrders) {
                    final board = _BoardData.from(allOrders, panelDisplay);
                    return metrics.isStacked
                        ? _StackedBoard(
                            board: board,
                            callLabels: callLabels,
                            palette: palette,
                            metrics: metrics,
                          )
                        : _ColumnsBoard(
                            board: board,
                            callLabels: callLabels,
                            palette: palette,
                            metrics: metrics,
                          );
                  },
                  loading: () => Center(
                    child: CircularProgressIndicator(color: palette.headerText),
                  ),
                  // Erro de conexão não pode virar a tela vermelha do Flutter
                  // (nem o texto cru da exceção) na frente do cliente: vira
                  // uma mensagem discreta, com a mesma cara do resto do
                  // Painel, e o erro de verdade vai pro log — quem precisa do
                  // diagnóstico é o técnico, na Cozinha/Configurações, que já
                  // mostram a falha de conexão com detalhe.
                  error: (err, stack) {
                    debugPrint(
                        '[PainelChamador] erro ao carregar pedidos: $err');
                    return _PanelMessage(
                      message: 'Não foi possível carregar os pedidos agora.',
                      palette: palette,
                      metrics: metrics,
                    );
                  },
                ),
              ),
              _PanelFooter(palette: palette, metrics: metrics),
            ],
          );
        },
      ),
    );
  }
}

/// Escala e forma do Painel para o espaço realmente disponível.
///
/// Uma TV Full HD tem 1,5x a largura do notebook em que a tela foi desenhada
/// e é vista de 5 metros; um tablet de parede tem metade. Em vez de espalhar
/// `if (isTablet)` pela tela, tudo multiplica por [scale], calculado uma vez
/// por frame a partir do menor entre largura e altura — o menor, porque uma
/// janela larga e baixa (TV com 3 colunas) precisa caber na altura também.
@immutable
class _PanelMetrics {
  /// Abaixo disso três colunas não cabem sem cortar o número da senha, e o
  /// Painel passa a empilhar as seções (celular, tablet em pé).
  static const _stackedBreakpoint = 760.0;

  /// Resolução em que o layout original foi desenhado — é a referência do
  /// `scale == 1.0`, então nessas medidas a tela sai idêntica ao que era.
  static const _designWidth = 1280.0;
  static const _designHeight = 780.0;

  final double scale;
  final bool isStacked;

  const _PanelMetrics._({required this.scale, required this.isStacked});

  factory _PanelMetrics.fromConstraints(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    // Dentro do Scaffold a altura é finita, mas basta alguém montar esta tela
    // dentro de um scroll um dia para ela virar infinita — e aí a escala
    // explodiria em vez de simplesmente ignorar a altura.
    final height =
        constraints.maxHeight.isFinite ? constraints.maxHeight : _designHeight;

    if (width < _stackedBreakpoint) {
      // Empilhado a referência é a largura de um celular comum: aqui a
      // altura sobra (a tela rola em seções), quem aperta é a largura.
      return _PanelMetrics._(
        scale: (width / 420).clamp(0.85, 1.4),
        isStacked: true,
      );
    }

    return _PanelMetrics._(
      scale: math
          .min(width / _designWidth, height / _designHeight)
          .clamp(0.7, 2.0),
      isStacked: false,
    );
  }

  /// Tamanho (fonte, espaçamento, card) proporcional à tela.
  double size(double base) => base * scale;
}

/// Os pedidos já filtrados e separados nas três seções do Painel.
@immutable
class _BoardData {
  final List<Order> preparing;
  final Order? currentCall;
  final List<Order> readyQueue;

  const _BoardData({
    required this.preparing,
    required this.currentCall,
    required this.readyQueue,
  });

  factory _BoardData.from(List<Order> allOrders, PanelDisplayConfig display) {
    final orders =
        allOrders.where((o) => display.isVisible(o.modalityName)).toList();

    final preparing = orders
        .where((o) =>
            o.status == OrderStatus.emPreparo || o.status == OrderStatus.novo)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final ready = orders.where((o) => o.status == OrderStatus.pronto).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return _BoardData(
      preparing: preparing,
      currentCall: ready.isNotEmpty ? ready.first : null,
      readyQueue: ready.length > 1 ? ready.sublist(1) : const <Order>[],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  final CustomerFacingPalette palette;
  final _PanelMetrics metrics;

  const _PanelHeader({required this.palette, required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        metrics.size(16),
        metrics.size(28),
        metrics.size(16),
        metrics.size(20),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'ACOMPANHE SEU PEDIDO',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: metrics.size(36),
                fontWeight: FontWeight.w900,
                color: palette.headerText,
                letterSpacing: metrics.size(2),
              ),
            ),
          ),
          SizedBox(height: metrics.size(4)),
          _PanelClock(palette: palette, metrics: metrics),
        ],
      ),
    );
  }
}

/// Relógio do cabeçalho.
///
/// É um `StatefulWidget` com timer próprio porque o Painel fica dias abertos
/// na mesma tela: formatar `DateTime.now()` direto no `build` congelava o
/// horário no momento em que a aba foi montada (o `IndexedStack` do app
/// mantém a tela viva), e o cliente via um relógio parado.
class _PanelClock extends StatefulWidget {
  final CustomerFacingPalette palette;
  final _PanelMetrics metrics;

  const _PanelClock({required this.palette, required this.metrics});

  @override
  State<_PanelClock> createState() => _PanelClockState();
}

class _PanelClockState extends State<_PanelClock> {
  static final _format = DateFormat('HH:mm');

  late String _formatted = _format.format(DateTime.now());
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Confere de segundo em segundo, mas só repinta quando o MINUTO vira —
    // um `setState` por segundo numa TV parada seria desperdício puro.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = _format.format(DateTime.now());
      if (now != _formatted && mounted) {
        setState(() => _formatted = now);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatted,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: widget.metrics.size(20),
        color: widget.palette.clockText,
      ),
    );
  }
}

/// Layout de tela grande (TV, notebook, tablet deitado): as três seções lado
/// a lado, com "CHAMANDO AGORA" no meio.
class _ColumnsBoard extends StatelessWidget {
  final _BoardData board;
  final Map<String, String> callLabels;
  final CustomerFacingPalette palette;
  final _PanelMetrics metrics;

  const _ColumnsBoard({
    required this.board,
    required this.callLabels,
    required this.palette,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _SectionColumn(
            section: CustomerFacingPanelSection.inPreparation,
            palette: palette,
            metrics: metrics,
            child: _OrderCardsGrid(
              orders: board.preparing,
              callLabels: callLabels,
              section: CustomerFacingPanelSection.inPreparation,
              palette: palette,
              metrics: metrics,
              emptyMessage: 'Nenhum pedido em preparo',
              tileWidth: 190,
            ),
          ),
        ),
        _PanelDivider(palette: palette),
        Expanded(
          // Mesmo flex do "Em Preparo" nas laterais — é o que mantém o card
          // de chamada exatamente no centro da tela.
          flex: 2,
          child: _SectionColumn(
            section: CustomerFacingPanelSection.callingNow,
            palette: palette,
            metrics: metrics,
            child: Center(
              child: board.currentCall == null
                  ? _PanelMessage(
                      message: 'Nenhum pedido\nsendo chamado',
                      palette: palette,
                      metrics: metrics,
                    )
                  : _HighlightCard(
                      label: _labelOf(board.currentCall!),
                      palette: palette,
                      metrics: metrics,
                    ),
            ),
          ),
        ),
        _PanelDivider(palette: palette),
        Expanded(
          flex: 3,
          child: _SectionColumn(
            section: CustomerFacingPanelSection.readyQueue,
            palette: palette,
            metrics: metrics,
            child: _OrderCardsGrid(
              orders: board.readyQueue,
              callLabels: callLabels,
              section: CustomerFacingPanelSection.readyQueue,
              palette: palette,
              metrics: metrics,
              emptyMessage: 'Sem pedidos aguardando retirada',
              tileWidth: 170,
            ),
          ),
        ),
      ],
    );
  }

  String _labelOf(Order order) => callLabels[order.id] ?? order.pdvCallerLabel;
}

/// Layout estreito (celular, tablet em pé): a chamada atual em cima, com
/// destaque, e as duas filas embaixo dividindo o que sobra.
class _StackedBoard extends StatelessWidget {
  final _BoardData board;
  final Map<String, String> callLabels;
  final CustomerFacingPalette palette;
  final _PanelMetrics metrics;

  const _StackedBoard({
    required this.board,
    required this.callLabels,
    required this.palette,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final currentCall = board.currentCall;

    return Column(
      children: [
        _SectionHeader(
          section: CustomerFacingPanelSection.callingNow,
          palette: palette,
          metrics: metrics,
        ),
        SizedBox(
          height: metrics.size(170),
          child: Center(
            child: currentCall == null
                ? _PanelMessage(
                    message: 'Nenhum pedido sendo chamado',
                    palette: palette,
                    metrics: metrics,
                  )
                : _HighlightCard(
                    label: callLabels[currentCall.id] ??
                        currentCall.pdvCallerLabel,
                    palette: palette,
                    metrics: metrics,
                  ),
          ),
        ),
        SizedBox(height: metrics.size(8)),
        Expanded(
          child: _SectionColumn(
            section: CustomerFacingPanelSection.inPreparation,
            palette: palette,
            metrics: metrics,
            child: _OrderCardsGrid(
              orders: board.preparing,
              callLabels: callLabels,
              section: CustomerFacingPanelSection.inPreparation,
              palette: palette,
              metrics: metrics,
              emptyMessage: 'Nenhum pedido em preparo',
              tileWidth: 150,
            ),
          ),
        ),
        Expanded(
          child: _SectionColumn(
            section: CustomerFacingPanelSection.readyQueue,
            palette: palette,
            metrics: metrics,
            child: _OrderCardsGrid(
              orders: board.readyQueue,
              callLabels: callLabels,
              section: CustomerFacingPanelSection.readyQueue,
              palette: palette,
              metrics: metrics,
              emptyMessage: 'Sem pedidos aguardando retirada',
              tileWidth: 150,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionColumn extends StatelessWidget {
  final CustomerFacingPanelSection section;
  final CustomerFacingPalette palette;
  final _PanelMetrics metrics;
  final Widget child;

  const _SectionColumn({
    required this.section,
    required this.palette,
    required this.metrics,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _SectionHeader(
          section: section,
          palette: palette,
          metrics: metrics,
        ),
        Expanded(child: child),
      ],
    );
  }
}

/// Título da seção: ícone vetorizado + texto, os dois na cor configurada.
///
/// O ícone entrou no lugar dos emojis 🔥/📢/🔔 que a tela usava — como texto,
/// eles eram desenhados pela fonte de emoji do sistema (diferente entre
/// Windows e Android, ausente em algumas TVs) e ignoravam a cor da coluna.
class _SectionHeader extends StatelessWidget {
  final CustomerFacingPanelSection section;
  final CustomerFacingPalette palette;
  final _PanelMetrics metrics;

  const _SectionHeader({
    required this.section,
    required this.palette,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final color = palette.sectionColor(section);
    final fontSize = metrics.size(22);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: metrics.size(12),
        vertical: metrics.size(16),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(section.icon, color: color, size: fontSize * 1.25),
            SizedBox(width: metrics.size(10)),
            Text(
              section.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCardsGrid extends StatelessWidget {
  final List<Order> orders;
  final Map<String, String> callLabels;
  final CustomerFacingPanelSection section;
  final CustomerFacingPalette palette;
  final _PanelMetrics metrics;
  final String emptyMessage;

  /// Largura desejada de cada card na resolução de referência — a quantidade
  /// de colunas sai daí, então card e coluna crescem juntos com a tela.
  final double tileWidth;

  const _OrderCardsGrid({
    required this.orders,
    required this.callLabels,
    required this.section,
    required this.palette,
    required this.metrics,
    required this.emptyMessage,
    required this.tileWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return _PanelMessage(
        message: emptyMessage,
        palette: palette,
        metrics: metrics,
      );
    }

    final color = palette.sectionColor(section);

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / metrics.size(tileWidth))
            .floor()
            .clamp(1, 6);

        return GridView.builder(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.size(14),
            vertical: metrics.size(12),
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 3.3,
            crossAxisSpacing: metrics.size(12),
            mainAxisSpacing: metrics.size(12),
          ),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return _OrderCard(
              label: callLabels[order.id] ?? order.pdvCallerLabel,
              sectionColor: color,
              palette: palette,
              metrics: metrics,
            );
          },
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final String label;
  final Color sectionColor;
  final CustomerFacingPalette palette;
  final _PanelMetrics metrics;

  const _OrderCard({
    required this.label,
    required this.sectionColor,
    required this.palette,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: metrics.size(8)),
      decoration: BoxDecoration(
        color: palette.cardBackground,
        borderRadius: BorderRadius.circular(palette.cardBorderRadius),
        border: Border.all(
          color: palette.cardBorderFor(sectionColor),
          width: metrics.size(1.6),
        ),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: TextStyle(
            fontSize: metrics.size(30),
            fontWeight: FontWeight.w800,
            color: palette.cardTextFor(sectionColor),
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// O card grande da senha que está sendo chamada agora.
class _HighlightCard extends StatelessWidget {
  final String label;
  final CustomerFacingPalette palette;
  final _PanelMetrics metrics;

  const _HighlightCard({
    required this.label,
    required this.palette,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final color = palette.callingNow;

    // FittedBox por fora: o card tem proporção fixa (é o elemento que o
    // cliente enxerga do outro lado do salão), então quando a coluna aperta
    // ele encolhe inteiro — texto junto — em vez de quebrar o layout.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        width: metrics.size(238),
        height: metrics.size(224),
        decoration: BoxDecoration(
          color: palette.cardBackground,
          borderRadius:
              BorderRadius.circular(palette.highlightCardBorderRadius),
          border: Border.all(
            color: palette.cardBorderOverride ?? color,
            width: metrics.size(2),
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.18),
              blurRadius: metrics.size(14),
              spreadRadius: metrics.size(1),
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
                letterSpacing: metrics.size(1.6),
                fontSize: metrics.size(17),
              ),
            ),
            SizedBox(height: metrics.size(4)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: metrics.size(12)),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    color: palette.cardTextFor(color),
                    fontSize: metrics.size(73),
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
            SizedBox(height: metrics.size(6)),
            Text(
              'Pronto para retirada',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.bodyText.withValues(alpha: 0.85),
                fontSize: metrics.size(17),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelDivider extends StatelessWidget {
  final CustomerFacingPalette palette;

  const _PanelDivider({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: palette.dividerColor);
  }
}

/// Estado vazio / mensagem de erro — mesma tipografia discreta nos dois
/// casos, porque nenhum dos dois é problema do cliente que está lendo.
class _PanelMessage extends StatelessWidget {
  final String message;
  final CustomerFacingPalette palette;
  final _PanelMetrics metrics;

  const _PanelMessage({
    required this.message,
    required this.palette,
    required this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(metrics.size(12)),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.mutedText,
            fontSize: metrics.size(16),
          ),
        ),
      ),
    );
  }
}

class _PanelFooter extends StatelessWidget {
  final CustomerFacingPalette palette;
  final _PanelMetrics metrics;

  const _PanelFooter({required this.palette, required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: metrics.size(14)),
      child: Text(
        'Solução Sistemas - A sua cozinha ainda mais eficiente',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: palette.watermarkInk,
          fontSize: metrics.size(13),
        ),
      ),
    );
  }
}
