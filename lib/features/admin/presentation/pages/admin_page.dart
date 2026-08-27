import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/config/order_timing_config_provider.dart';
import '../../../../core/config/printer_config_provider.dart';
import '../../../../core/data/mongo_service.dart';
import '../../../../core/config/alert_appearance_config_provider.dart';
import '../../../../core/widgets/order_urgency_shell.dart';
import '../../../orders/presentation/providers/order_provider.dart';
import '../../../orders/domain/entities/order.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../../services/kds_printer_service.dart';
import '../providers/admin_view_provider.dart';

/// Painel Administrativo: diferente da Cozinha (que é um quadro de trabalho
/// ativo, item a item), este é um histórico/dashboard — mostra o que já
/// passou pela cozinha nas últimas 24h, indicadores operacionais (sem
/// valores monetários, isso não é o foco do KDS) e permite imprimir a
/// senha de um pedido de novo. Não tem botões de avançar status (quem mexe no
/// preparo é a Cozinha) — só o de reverter uma etapa, e só pra admins,
/// pra corrigir um avanço feito por engano sem precisar ir até a Cozinha.
class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(displayOrderHistoryProvider);
    final isAdmin =
        ref.watch(authControllerProvider).valueOrNull?.administrador ?? false;

    return Scaffold(
      backgroundColor: context.colors.backgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Abaixo de 700 a página já mostra o histórico em cartões e o
          // Scaffold pai troca a barra lateral fixa por um AppBar com o
          // título "Administrativo" — por isso o título grande é escondido
          // aqui, para não duplicar em telas pequenas.
          final isCompact = constraints.maxWidth < 700;
          final horizontalPadding = isCompact ? 14.0 : 24.0;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              isCompact ? 14 : 24,
              horizontalPadding,
              horizontalPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isCompact) ...[
                  const Text(
                    'Painel Administrativo',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Histórico e indicadores dos pedidos',
                    style: TextStyle(color: context.colors.textSecondaryColor),
                  ),
                ] else
                  Text(
                    'Histórico e indicadores',
                    style: TextStyle(
                      color: context.colors.textSecondaryColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                SizedBox(height: isCompact ? 14 : 24),
                _buildSummaryCards(
                    context,
                    historyAsync,
                    ref.watch(orderTimingConfigProvider).alertMinutes,
                    isCompact),
                SizedBox(height: isCompact ? 14 : 24),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.colors.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.colors.borderColor),
                      boxShadow: [
                        BoxShadow(
                            color: context.colors.shadowColor,
                            blurRadius: 12,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildFilters(context, isCompact, ref),
                        Divider(height: 1, color: context.colors.borderColor),
                        Expanded(
                            child: _buildHistoryList(
                                context, historyAsync, ref, isAdmin)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context,
      AsyncValue<List<Order>> historyAsync, int alertMinutes, bool isCompact) {
    int total = 0;
    int emAndamento = 0;
    int atrasados = 0;
    String tempoMedio = '--';

    historyAsync.whenData((orders) {
      total = orders.length;
      emAndamento =
          orders.where((o) => o.status != OrderStatus.entregue).length;
      atrasados = orders
          .where((o) =>
              o.status != OrderStatus.entregue &&
              DateTime.now().difference(o.timestamp).inMinutes >= alertMinutes)
          .length;

      final delivered = orders
          .where((o) =>
              o.status == OrderStatus.entregue &&
              o.updatedAt != null &&
              o.updatedAt!.isAfter(o.timestamp))
          .toList();
      if (delivered.isNotEmpty) {
        final totalMinutes = delivered.fold<int>(
          0,
          (sum, o) => sum + o.updatedAt!.difference(o.timestamp).inMinutes,
        );
        tempoMedio = _formatMinutes((totalMinutes / delivered.length).round());
      }
    });

    final cards = [
      _buildSummaryCard(context, 'Pedidos (24h)', total.toString(),
          context.colors.infoColor, Icons.receipt_long, isCompact),
      _buildSummaryCard(context, 'Em Andamento', emAndamento.toString(),
          context.colors.warningColor, Icons.restaurant, isCompact),
      _buildSummaryCard(context, 'Atrasados', atrasados.toString(),
          context.colors.errorColor, Icons.warning_amber_rounded, isCompact),
      _buildSummaryCard(context, 'Tempo Médio de Preparo', tempoMedio,
          context.colors.accentColor, Icons.timer, isCompact),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = isCompact ? 10.0 : 16.0;
        final columns = constraints.maxWidth < 500 ? 2 : 4;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard(BuildContext context, String title, String value,
      Color color, IconData icon, bool isCompact) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 10 : 14, vertical: isCompact ? 8 : 10),
      decoration: BoxDecoration(
        color: context.colors.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderColor),
        boxShadow: [
          BoxShadow(
              color: context.colors.shadowColor,
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: isCompact ? 15 : 18),
          SizedBox(width: isCompact ? 6 : 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: context.colors.textSecondaryColor,
                      fontSize: isCompact ? 10 : 11),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: isCompact ? 16 : 18,
                      fontWeight: FontWeight.bold,
                      color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(BuildContext context, bool isCompact, WidgetRef ref) {
    final searchField = TextField(
      onChanged: (value) =>
          ref.read(adminSearchQueryProvider.notifier).state = value,
      decoration: InputDecoration(
        hintText: 'Buscar por nº ou nome...',
        prefixIcon: const Icon(Icons.search, size: 20),
        filled: true,
        fillColor: context.colors.backgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
      ),
    );

    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip(context, ref, 'Todos', null),
          _buildFilterChip(context, ref, 'Recebido', OrderStatus.novo),
          _buildFilterChip(context, ref, 'Em Preparo', OrderStatus.emPreparo),
          _buildFilterChip(context, ref, 'Pronto', OrderStatus.pronto),
          _buildFilterChip(context, ref, 'Entregue', OrderStatus.entregue),
        ],
      ),
    );

    final period = ref.watch(adminHistoryPeriodProvider);
    final periodDropdown = _buildDropdown<AdminHistoryPeriod>(
      context: context,
      value: period,
      items: AdminHistoryPeriod.values,
      labelOf: (p) => p.label,
      onChanged: (value) =>
          ref.read(adminHistoryPeriodProvider.notifier).state = value!,
    );

    final pageSize = ref.watch(adminPageSizeProvider);
    final pageSizeDropdown = _buildDropdown<int>(
      context: context,
      value: pageSize,
      items: adminPageSizeOptions,
      labelOf: (n) => '$n pedidos',
      onChanged: (value) =>
          ref.read(adminPageSizeProvider.notifier).state = value!,
    );

    final periodAndPageSize = Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [periodDropdown, pageSizeDropdown],
    );

    return Padding(
      padding: EdgeInsets.all(isCompact ? 12.0 : 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                const SizedBox(height: 12),
                chips,
                const SizedBox(height: 12),
                periodAndPageSize,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 16),
                  chips,
                ],
              ),
              const SizedBox(height: 12),
              periodAndPageSize,
            ],
          );
        },
      ),
    );
  }

  Widget _buildDropdown<T>({
    required BuildContext context,
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.colors.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          style: TextStyle(color: context.colors.textColor, fontSize: 14),
          dropdownColor: context.colors.cardColor,
          items: [
            for (final item in items)
              DropdownMenuItem(value: item, child: Text(labelOf(item))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildFilterChip(
      BuildContext context, WidgetRef ref, String label, OrderStatus? value) {
    final isSelected = ref.watch(adminStatusFilterProvider) == value;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) =>
            ref.read(adminStatusFilterProvider.notifier).state = value,
        selectedColor: context.colors.primaryColor,
        labelStyle: TextStyle(
            color:
                isSelected ? Colors.white : context.colors.textSecondaryColor),
        backgroundColor: context.colors.backgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        showCheckmark: false,
      ),
    );
  }

  Widget _buildHistoryList(BuildContext context,
      AsyncValue<List<Order>> historyAsync, WidgetRef ref, bool isAdmin) {
    final statusFilter = ref.watch(adminStatusFilterProvider);
    final query = ref.watch(adminSearchQueryProvider).trim().toLowerCase();
    final period = ref.watch(adminHistoryPeriodProvider);
    final pageSize = ref.watch(adminPageSizeProvider);

    return historyAsync.when(
      data: (allOrders) {
        var orders = statusFilter == null
            ? allOrders
            : allOrders.where((o) => o.status == statusFilter).toList();

        if (query.isNotEmpty) {
          orders = orders.where((o) {
            if (o.number.toString().contains(query)) return true;
            if (o.roundCode.contains(query)) return true;
            if (o.modalityDisplay.toLowerCase().contains(query)) return true;
            return o.items.any((i) => i.name.toLowerCase().contains(query));
          }).toList();
        }

        final cutoff = period.cutoff();
        if (cutoff != null) {
          orders = orders.where((o) => o.timestamp.isAfter(cutoff)).toList();
        }

        // A lista já vem ordenada da mais recente pra mais antiga — limitar
        // aqui pega exatamente os N pedidos mais recentes que passaram nos
        // filtros acima, não uma amostra qualquer de N pedidos.
        final totalMatching = orders.length;
        if (orders.length > pageSize) {
          orders = orders.take(pageSize).toList();
        }

        if (orders.isEmpty) {
          return Center(
            child: Text('Nenhum pedido encontrado',
                style: TextStyle(color: context.colors.textSecondaryColor)),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            // Em telas largas (PC), agrupa os pedidos em até 3 colunas lado
            // a lado pra aproveitar melhor o espaço — no celular continua em
            // coluna única. Todos os cartões têm a mesma altura fixa (ver
            // cardHeight), alta o suficiente pra caber os itens de um pedido
            // grande sem precisar rolar.
            //
            // Monta linha por linha (em vez de Wrap) de propósito: um Wrap
            // dentro de um Column só ocupa a largura dos próprios filhos, e
            // o Column (alinhamento padrão "center") acabava centralizando
            // esse bloco mais estreito em vez de grudar os cartões à
            // esquerda.
            const outerPadding = 12.0;
            const spacing = 12.0;
            const cardHeight = 260.0;
            final available = constraints.maxWidth - outerPadding * 2;
            final columns = available >= 1100 ? 3 : (available >= 700 ? 2 : 1);
            final cardWidth = columns == 1
                ? available
                : (available - spacing * (columns - 1)) / columns;

            final rows = <Widget>[];
            for (var i = 0; i < orders.length; i += columns) {
              final rowOrders = orders.skip(i).take(columns).toList();
              rows.add(
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var j = 0; j < rowOrders.length; j++) ...[
                      if (j > 0) const SizedBox(width: spacing),
                      SizedBox(
                        width: cardWidth,
                        height: cardHeight,
                        child: _buildHistoryCard(
                            context, ref, rowOrders[j], isAdmin),
                      ),
                    ],
                  ],
                ),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(outerPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: spacing),
                    child: Text(
                      'Mostrando ${orders.length} de $totalMatching pedidos',
                      style: TextStyle(
                          color: context.colors.textSecondaryColor,
                          fontSize: 13),
                    ),
                  ),
                  for (final row in rows) ...[
                    row,
                    const SizedBox(height: spacing),
                  ],
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Erro: $err')),
    );
  }

  Widget _buildHistoryCard(
      BuildContext context, WidgetRef ref, Order order, bool isAdmin) {
    final elapsed = DateTime.now().difference(order.timestamp).inMinutes;
    final timing = ref.watch(orderTimingConfigProvider);
    final urgency = orderUrgencyFor(order, elapsed, timing);
    final timeColor = orderUrgencyColor(context, urgency,
        alertsEnabled: ref.watch(alertAppearanceConfigProvider).enabled);

    return OrderUrgencyShell(
      urgency: urgency,
      child: Container(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Mesa/Cartão: mostra o código da leva (comandaCodigo), que
                // distingue esse lançamento de outros já feitos na mesma
                // mesa — order.number é compartilhado por todas as levas.
                Text(
                  order.locatorLabel != null
                      ? '#${order.roundCode}'
                      : '#${order.number}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    order.modalityDisplay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: context.colors.textSecondaryColor,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(context, order.status),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _ItemTagsScrollArea(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final item in order.items)
                      _buildItemTag(context, ref, order, item, isAdmin)
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.access_time, size: 13, color: timeColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _buildDurationLabel(order),
                    style: TextStyle(color: timeColor, fontSize: 12),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _printOrder(context, ref, order),
                  icon: const Icon(Icons.print, size: 15),
                  label: const Text('Imprimir'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.textSecondaryColor,
                    side: BorderSide(color: context.colors.borderColor),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemTag(BuildContext context, WidgetRef ref, Order order,
      OrderItem item, bool isAdmin) {
    final statusColor = _getStatusColor(context, item.status);
    final previousStatus = _previousItemStatus(item.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.cardColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildItemThumbnail(context, item.imageUrl),
          const SizedBox(width: 6),
          Tooltip(
            message: _getStatusLabel(item.status),
            child: Icon(_getItemStatusIcon(item.status),
                size: 13, color: statusColor),
          ),
          const SizedBox(width: 5),
          Text(
            '${item.quantity}x',
            style: TextStyle(
                color: context.colors.accentColor,
                fontWeight: FontWeight.bold,
                fontSize: 12),
          ),
          const SizedBox(width: 4),
          Text(item.name, style: const TextStyle(fontSize: 12)),
          if (isAdmin && previousStatus != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: 'Voltar etapa',
              child: InkWell(
                onTap: () => ref
                    .read(orderStatusUpdateProvider.notifier)
                    .updateItemStatus(order.id, item.id, previousStatus),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(Icons.undo,
                      size: 13, color: context.colors.errorColor),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemThumbnail(BuildContext context, String? imageUrl) {
    const size = 20.0;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.backgroundColor,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Icon(Icons.restaurant_menu,
          size: 11, color: context.colors.textSecondaryColor),
    );

    if (imageUrl == null || imageUrl.isEmpty) {
      return placeholder;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => placeholder,
      ),
    );
  }

  /// Ícone exclusivo por etapa de preparo do item — permite identificar o
  /// status de cada item no histórico sem precisar ler o texto do badge.
  IconData _getItemStatusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.novo:
        return Icons.hourglass_empty;
      case OrderStatus.emPreparo:
        return Icons.local_fire_department;
      case OrderStatus.pronto:
        return Icons.check_circle;
      case OrderStatus.entregue:
        return Icons.done_all;
    }
  }

  /// Etapa anterior à do item, ou null se já está na primeira ("novo"). Usado
  /// pelo botão de reverter, disponível só para administradores.
  OrderStatus? _previousItemStatus(OrderStatus status) {
    switch (status) {
      case OrderStatus.novo:
        return null;
      case OrderStatus.emPreparo:
        return OrderStatus.novo;
      case OrderStatus.pronto:
        return OrderStatus.emPreparo;
      case OrderStatus.entregue:
        return OrderStatus.pronto;
    }
  }

  String _buildDurationLabel(Order order) {
    final arrival = DateFormat('HH:mm').format(order.timestamp);
    if (order.status == OrderStatus.entregue && order.updatedAt != null) {
      final minutes = order.updatedAt!.difference(order.timestamp).inMinutes;
      return 'Chegou às $arrival · levou ${_formatMinutes(minutes)}';
    }
    final elapsed = DateTime.now().difference(order.timestamp).inMinutes;
    return 'Chegou às $arrival · em andamento há ${_formatMinutes(elapsed)}';
  }

  /// Formata minutos como "42min" ou, acima de 1h, "1h 23min" (sem os
  /// minutos quando exatos, ex: "2h") — bem mais legível que "157min" pra
  /// pedidos parados há muito tempo.
  String _formatMinutes(int minutes) {
    if (minutes < 60) return '${minutes}min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins == 0 ? '${hours}h' : '${hours}h ${mins}min';
  }

  /// Imprime direto, sem diálogo de confirmação prévio — só um popup de 2
  /// segundos avisando se saiu ou não. O ticket sai com todos os dados do
  /// pedido (itens, quantidades, observações e horário), não só a senha.
  Future<void> _printOrder(
      BuildContext context, WidgetRef ref, Order order) async {
    KdsPrintOutcome outcome;
    try {
      final config = ref.read(printerConfigProvider);
      final db = await ref.read(mongoDbProvider.future);
      outcome = await KdsPrinterService().printOrder(order, config, db: db);
    } catch (e) {
      // Sem isso, uma falha ao montar o ticket ou falar com a impressora
      // (ex.: caractere não suportado, impressora desligada) derrubava a
      // Future sem exibir nada — o usuário só via o botão "não fazer nada".
      outcome = KdsPrintOutcome.failure('Falha ao imprimir: $e');
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.success
            ? 'Pedido #${order.number} impresso.'
            : (outcome.error ?? 'Falha ao imprimir.')),
        backgroundColor: outcome.success
            ? context.colors.successColor
            : context.colors.errorColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, OrderStatus status) {
    final color = _getStatusColor(context, status);
    return Container(
      width: 110,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        _getStatusLabel(status),
        textAlign: TextAlign.center,
        style:
            TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _getStatusColor(BuildContext context, OrderStatus status) {
    switch (status) {
      case OrderStatus.novo:
        return context.colors.infoColor;
      case OrderStatus.emPreparo:
        return context.colors.warningColor;
      case OrderStatus.pronto:
        return context.colors.successColor;
      case OrderStatus.entregue:
        return context.colors.textSecondaryColor;
    }
  }

  String _getStatusLabel(OrderStatus status) {
    switch (status) {
      case OrderStatus.novo:
        return 'NOVO';
      case OrderStatus.emPreparo:
        return 'EM PREPARO';
      case OrderStatus.pronto:
        return 'PRONTO';
      case OrderStatus.entregue:
        return 'ENTREGUE';
    }
  }
}

/// Área de itens de um card do histórico. Fica travada (sem rolagem
/// própria) enquanto os itens couberem no espaço do card — assim um
/// arraste em cima dela continua "vazando" pra lista de histórico por trás,
/// que rola inteira. Só quando o pedido é grande demais pra caber (detectado
/// pela própria métrica de scroll, não por uma contagem fixa de itens) ela
/// vira rolável e mostra a barra de rolagem — mesma técnica já usada na
/// Cozinha pro mesmo problema.
class _ItemTagsScrollArea extends StatefulWidget {
  final Widget child;

  const _ItemTagsScrollArea({required this.child});

  @override
  State<_ItemTagsScrollArea> createState() => _ItemTagsScrollAreaState();
}

class _ItemTagsScrollAreaState extends State<_ItemTagsScrollArea> {
  final _controller = ScrollController();
  bool _overflowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void didUpdateWidget(covariant _ItemTagsScrollArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _checkOverflow() {
    if (!mounted || !_controller.hasClients) return;
    final overflowing = _controller.position.maxScrollExtent > 0;
    if (overflowing != _overflowing) {
      setState(() => _overflowing = overflowing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scrollView = SingleChildScrollView(
      controller: _controller,
      physics: _overflowing
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      child: widget.child,
    );

    if (!_overflowing) return scrollView;

    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: scrollView,
    );
  }
}
