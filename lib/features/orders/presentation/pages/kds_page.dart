import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/config/order_timing_config_provider.dart';
import '../../../../core/config/alert_appearance_config_provider.dart';
import '../../../../core/config/kds_production_mode_config.dart';
import '../../../../core/config/kds_production_mode_config_provider.dart';
import '../../../../core/widgets/order_urgency_shell.dart';
import '../../domain/entities/order.dart';
import '../providers/order_provider.dart';
import '../providers/kds_view_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

class KDSPage extends ConsumerWidget {
  const KDSPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(displayOrdersProvider);

    return Scaffold(
      backgroundColor: context.colors.backgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Mesma estrutura da tela Administrativa: abaixo de 700 o Scaffold
          // pai já mostra um AppBar com o título "Cozinha", então o título
          // grande fica escondido aqui pra não duplicar em telas pequenas.
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
                    'Cozinha',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Preparo dos pedidos',
                    style: TextStyle(color: context.colors.textSecondaryColor),
                  ),
                ] else
                  Text(
                    'Preparo dos pedidos',
                    style: TextStyle(
                      color: context.colors.textSecondaryColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                            child:
                                _buildOrdersBoard(context, ordersAsync, ref)),
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

  Widget _buildFilters(BuildContext context, bool isCompact, WidgetRef ref) {
    final searchField = TextField(
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

    final viewToggle = _buildViewModeToggle(context, ref);

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
                Row(
                  children: [
                    Expanded(child: chips),
                    const SizedBox(width: 8),
                    viewToggle,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 16),
              chips,
              const SizedBox(width: 12),
              viewToggle,
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(
      BuildContext context, WidgetRef ref, String label, OrderStatus? value) {
    final isSelected = ref.watch(kdsStatusFilterProvider) == value;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) =>
            ref.read(kdsStatusFilterProvider.notifier).state = value,
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

  Widget _buildViewModeToggle(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(kdsViewModeProvider);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.colors.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildViewModeButton(context, ref, mode, KdsViewMode.list,
              Icons.view_agenda_outlined, 'Lista'),
          _buildViewModeButton(context, ref, mode, KdsViewMode.kanban,
              Icons.view_column_outlined, 'Kanban'),
        ],
      ),
    );
  }

  Widget _buildViewModeButton(
    BuildContext context,
    WidgetRef ref,
    KdsViewMode current,
    KdsViewMode value,
    IconData icon,
    String tooltip,
  ) {
    final isSelected = current == value;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => ref.read(kdsViewModeProvider.notifier).state = value,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color:
                isSelected ? context.colors.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon,
              size: 18,
              color: isSelected
                  ? Colors.white
                  : context.colors.textSecondaryColor),
        ),
      ),
    );
  }

  Widget _buildOrdersBoard(BuildContext context,
      AsyncValue<List<Order>> ordersAsync, WidgetRef ref) {
    final viewMode = ref.watch(kdsViewModeProvider);
    final statusFilter = ref.watch(kdsStatusFilterProvider);
    return ordersAsync.when(
      data: (allOrders) {
        final orders = statusFilter == null
            ? allOrders
            : allOrders.where((o) => o.status == statusFilter).toList();

        if (viewMode == KdsViewMode.kanban) {
          return _buildKanbanBoard(context, orders, ref);
        }
        if (orders.isEmpty) {
          return _buildEmptyState(context);
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 700;
            // Coluna fixa calculada com floor (não com o delegate de
            // "maxCrossAxisExtent", cujo arredondamento para cima podia
            // decidir por 2 colunas apertadas em larguras só um pouco acima
            // de 340 — sobrando pouquíssimo espaço pro texto de cada item).
            final crossAxisCount =
                (constraints.maxWidth / 340).floor().clamp(1, 6);
            return GridView.builder(
              padding: EdgeInsets.all(isCompact ? 12 : 16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisExtent: 440,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: orders.length,
              itemBuilder: (context, index) =>
                  _buildOrderCard(context, ref, orders[index]),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Erro: $err')),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline,
              size: 64, color: context.colors.successColor),
          const SizedBox(height: 16),
          const Text(
            'Nenhuma demanda pendente!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            'Todos os pedidos foram preparados',
            style: TextStyle(color: context.colors.textSecondaryColor),
          ),
        ],
      ),
    );
  }

  // Coluna "Entregue" não entra mais no board — a Cozinha não precisa
  // acompanhar pedidos já entregues aqui (isso é papel do Administrativo).
  // Com uma coluna a menos, deixa as 3 restantes esticarem e ocuparem o
  // espaço todo em vez de ficarem com largura fixa e sobrar tela vazia.
  static const _kanbanColumns = [
    OrderStatus.novo,
    OrderStatus.emPreparo,
    OrderStatus.pronto,
  ];
  static const _kanbanMinColumnWidth = 300.0;

  Widget _buildKanbanBoard(
      BuildContext context, List<Order> orders, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final needsScroll = constraints.maxWidth <
            _kanbanMinColumnWidth * _kanbanColumns.length;

        final row = Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final status in _kanbanColumns) ...[
              if (status != _kanbanColumns.first) const SizedBox(width: 12),
              needsScroll
                  ? SizedBox(
                      width: _kanbanMinColumnWidth,
                      child: _buildKanbanColumn(
                          context,
                          status,
                          orders.where((o) => o.status == status).toList(),
                          ref),
                    )
                  : Expanded(
                      child: _buildKanbanColumn(
                          context,
                          status,
                          orders.where((o) => o.status == status).toList(),
                          ref),
                    ),
            ],
          ],
        );

        return Padding(
          padding: const EdgeInsets.all(12),
          child: needsScroll
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal, child: row)
              : row,
        );
      },
    );
  }

  Widget _buildKanbanColumn(BuildContext context, OrderStatus status,
      List<Order> orders, WidgetRef ref) {
    final color = _getStatusColor(context, status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _getKanbanColumnLabel(status),
                  style: TextStyle(
                      color: color, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              Text(
                '${orders.length}',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: orders.isEmpty
              ? Center(
                  child: Text(
                    'Nenhum pedido',
                    style: TextStyle(
                        color: context.colors.textSecondaryColor, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => SizedBox(
                    height: 420,
                    child: _buildOrderCard(context, ref, orders[index]),
                  ),
                ),
        ),
      ],
    );
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

  String _getKanbanColumnLabel(OrderStatus status) {
    switch (status) {
      case OrderStatus.novo:
        return 'Recebido';
      case OrderStatus.emPreparo:
        return 'Em Preparo';
      case OrderStatus.pronto:
        return 'Pronto';
      case OrderStatus.entregue:
        return 'Entregue';
    }
  }

  Widget _buildOrderCard(BuildContext context, WidgetRef ref, Order order) {
    final elapsed = DateTime.now().difference(order.timestamp).inMinutes;
    final isAdmin =
        ref.watch(authControllerProvider).valueOrNull?.administrador ?? false;
    final timing = ref.watch(orderTimingConfigProvider);
    final urgency = orderUrgencyFor(order, elapsed, timing);
    final timeColor = orderUrgencyColor(context, urgency,
        alertsEnabled: ref.watch(alertAppearanceConfigProvider).enabled);
    final productionMode = ref.watch(kdsProductionModeConfigProvider).mode;

    return OrderUrgencyShell(
      urgency: urgency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                // Mesa/Cartão: mostra o código da leva (comandaCodigo), que
                // é o que distingue esse lançamento de outros já feitos na
                // mesma mesa — o número da ocupação (order.number) é
                // compartilhado por todas as levas, não serve pra isso.
                Text(
                  order.locatorLabel != null
                      ? '#${order.roundCode}'
                      : '#${order.number}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
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
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.access_time, size: 13, color: timeColor),
                const SizedBox(width: 4),
                Text(
                  _formatMinutes(elapsed),
                  style: TextStyle(
                    color: timeColor,
                    fontSize: 12,
                    fontWeight: urgency == OrderUrgency.normal
                        ? FontWeight.normal
                        : FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 16, color: context.colors.borderColor),
          Expanded(
            child: _OrderItemsList(
              order: order,
              itemRowBuilder: (context, item) => _buildKdsItemRow(
                  context, ref, order, item, isAdmin, productionMode),
            ),
          ),
          _buildOrderObservation(context, order.observations),
          _buildCardAction(context, ref, order, productionMode, isAdmin),
        ],
      ),
    );
  }

  /// Barra de ação no rodapé do card — o que muda entre os três modos de
  /// produção (ver [KdsProductionMode]).
  ///
  /// Em [KdsProductionMode.perItem], só a entrega usa essa barra (item a
  /// item não tem como um ficar "pronto" e ainda fazer sentido entregar os
  /// outros separado — a comanda só chega em "pronto" quando TODOS os itens
  /// já chegaram lá, ver `Order.status`), exatamente como sempre foi.
  ///
  /// Em [KdsProductionMode.wholeOrder], a mesma barra existe em CADA etapa —
  /// Iniciar Comanda, Finalizar Comanda, Entregar — sempre avançando todos
  /// os itens de uma vez (`updateStatus`, que já grava o status em todos os
  /// itens da comanda num só update no Mongo).
  ///
  /// Em [KdsProductionMode.mixed], ver [_buildMixedCardAction].
  Widget _buildCardAction(BuildContext context, WidgetRef ref, Order order,
      KdsProductionMode mode, bool isAdmin) {
    switch (mode) {
      case KdsProductionMode.perItem:
        if (order.status != OrderStatus.pronto) {
          return const SizedBox(height: 12);
        }
        return _cardActionBar(
          context,
          label: 'ENTREGAR',
          color: context.colors.successColor,
          onTap: () => ref
              .read(orderStatusUpdateProvider.notifier)
              .updateStatus(order.id, OrderStatus.entregue),
        );

      case KdsProductionMode.wholeOrder:
        switch (order.status) {
          case OrderStatus.novo:
            return _cardActionBar(
              context,
              label: 'INICIAR PREPARO',
              color: context.colors.warningColor,
              onTap: () => ref
                  .read(orderStatusUpdateProvider.notifier)
                  .updateStatus(order.id, OrderStatus.emPreparo),
            );
          case OrderStatus.emPreparo:
            return _cardActionRow(
              context,
              revertTo: isAdmin ? OrderStatus.novo : null,
              onRevert: (status) => ref
                  .read(orderStatusUpdateProvider.notifier)
                  .updateStatus(order.id, status),
              label: 'FINALIZAR PREPARO',
              color: context.colors.successColor,
              onTap: () => ref
                  .read(orderStatusUpdateProvider.notifier)
                  .updateStatus(order.id, OrderStatus.pronto),
            );
          case OrderStatus.pronto:
            return _cardActionRow(
              context,
              revertTo: isAdmin ? OrderStatus.emPreparo : null,
              onRevert: (status) => ref
                  .read(orderStatusUpdateProvider.notifier)
                  .updateStatus(order.id, status),
              label: 'ENTREGAR',
              color: context.colors.successColor,
              onTap: () => ref
                  .read(orderStatusUpdateProvider.notifier)
                  .updateStatus(order.id, OrderStatus.entregue),
            );
          case OrderStatus.entregue:
            return const SizedBox(height: 12);
        }

      case KdsProductionMode.mixed:
        return _buildMixedCardAction(context, ref, order, isAdmin);
    }
  }

  /// Rodapé do modo [KdsProductionMode.mixed]: só aparece quando TODOS os
  /// itens da comanda estão exatamente na mesma etapa (ver
  /// [_buildItemAction], que sempre mostra o botão de cada item nesse modo,
  /// independente disso). Num estado misturado (ex: um item já iniciado
  /// sozinho, os outros ainda não), o operador segue avançando pelos chips
  /// de cada item até os itens realinharem — só então a barra em massa
  /// reaparece. É exatamente o "não ter que escolher se é tudo ou nada"
  /// pedido: as duas formas de agir convivem, e quem decide a cada toque é
  /// o operador, não uma configuração prévia.
  ///
  /// A checagem de "pronto" aceita itens já `entregue` juntos (não exige
  /// TODOS exatamente `pronto`): um admin pode reverter um item de
  /// `entregue` pra `pronto` individualmente (nesta tela ou no
  /// Administrativo — ver `admin_page.dart`), o que reabre essa comanda no
  /// quadro ativo com um estado pronto+entregue misto — sem essa folga não
  /// haveria como reentregar aquele item pela Cozinha (não existe avanço
  /// por item até "entregue", só em massa). Mesmo critério que
  /// `Order.status == pronto` já usava antes desse recurso existir.
  Widget _buildMixedCardAction(
      BuildContext context, WidgetRef ref, Order order, bool isAdmin) {
    final items = order.items;
    if (items.isEmpty) return const SizedBox(height: 12);
    bool allAt(OrderStatus status) => items.every((i) => i.status == status);
    final allProntoOuEntregue = items.every((i) =>
        i.status == OrderStatus.pronto || i.status == OrderStatus.entregue);

    if (allAt(OrderStatus.entregue)) return const SizedBox(height: 12);

    if (allAt(OrderStatus.novo)) {
      return _cardActionBar(
        context,
        label: 'INICIAR PREPARO',
        color: context.colors.warningColor,
        onTap: () => ref
            .read(orderStatusUpdateProvider.notifier)
            .updateStatus(order.id, OrderStatus.emPreparo),
      );
    }

    if (allAt(OrderStatus.emPreparo)) {
      return _cardActionRow(
        context,
        revertTo: isAdmin ? OrderStatus.novo : null,
        onRevert: (status) => ref
            .read(orderStatusUpdateProvider.notifier)
            .updateStatus(order.id, status),
        label: 'FINALIZAR PREPARO',
        color: context.colors.successColor,
        onTap: () => ref
            .read(orderStatusUpdateProvider.notifier)
            .updateStatus(order.id, OrderStatus.pronto),
      );
    }

    if (allProntoOuEntregue) {
      return _cardActionRow(
        context,
        revertTo: isAdmin ? OrderStatus.emPreparo : null,
        onRevert: (status) => ref
            .read(orderStatusUpdateProvider.notifier)
            .updateStatus(order.id, status),
        label: 'ENTREGAR',
        color: context.colors.successColor,
        onTap: () => ref
            .read(orderStatusUpdateProvider.notifier)
            .updateStatus(order.id, OrderStatus.entregue),
      );
    }

    // Estado misturado de verdade (nem todos na mesma etapa) — sem ação em
    // massa; cada item segue avançando pelo próprio chip até realinhar.
    return const SizedBox(height: 12);
  }

  /// A barra colorida de largura total (o "ENTREGAR" de sempre), com um
  /// rótulo e cor configuráveis pra virar também "INICIAR PREPARO" e
  /// "FINALIZAR PREPARO".
  ///
  /// [borderRadius] arredonda só os cantos que realmente tocam a borda do
  /// card — por padrão os dois de baixo (quando a barra ocupa a linha
  /// inteira sozinha); [_cardActionRow] passa uma versão com só o canto
  /// direito quando ela divide a linha com o botão de voltar.
  Widget _cardActionBar(
    BuildContext context, {
    required String label,
    required Color color,
    required VoidCallback onTap,
    BorderRadius borderRadius = const BorderRadius.only(
      bottomLeft: Radius.circular(kOrderCardRadius),
      bottomRight: Radius.circular(kOrderCardRadius),
    ),
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: borderRadius,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: color, borderRadius: borderRadius),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2),
        ),
      ),
    );
  }

  /// A mesma barra, com um botão pequeno de "voltar etapa" ao lado quando
  /// [revertTo] não é nulo — dá ao administrador, no modo comanda inteira, a
  /// mesma capacidade de corrigir um toque errado que já existia por item.
  ///
  /// Os dois ficam encostados um no outro (sem vão entre eles) e só o canto
  /// que cada um ocupa de verdade no card é arredondado — o de voltar tem o
  /// canto inferior esquerdo, a barra principal o direito — pra parecer um
  /// rodapé só, cortado em duas cores, em vez de dois botões soltos.
  /// `CrossAxisAlignment.stretch` garante que os dois cheguem exatamente na
  /// mesma altura (senão o botão de voltar, menor, sobraria com um vão em
  /// cima ou embaixo dele, quebrando esse efeito de rodapé contínuo).
  Widget _cardActionRow(
    BuildContext context, {
    required OrderStatus? revertTo,
    required ValueChanged<OrderStatus> onRevert,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    if (revertTo == null) {
      return _cardActionBar(context, label: label, color: color, onTap: onTap);
    }

    // IntrinsicHeight, e não só `CrossAxisAlignment.stretch`: stretch sozinho
    // precisa que a altura AMBIENTE já chegue limitada até aqui pra fazer
    // sentido esticar os dois filhos até ela — e o card aparece embutido em
    // mais de um lugar (grade, coluna do Kanban) nem todos garantindo isso
    // sempre. IntrinsicHeight mede a altura que o MAIOR dos dois pediria
    // sozinho e trava a linha nela, sem depender do que vem de fora — só
    // funciona sem custo/risco aqui porque nenhum dos dois filhos tem
    // conteúdo rolável (o motivo de não usar em qualquer lugar).
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardRevertButton(context, onTap: () => onRevert(revertTo)),
          Expanded(
            child: _cardActionBar(
              context,
              label: label,
              color: color,
              onTap: onTap,
              borderRadius: const BorderRadius.only(
                  bottomRight: Radius.circular(kOrderCardRadius)),
            ),
          ),
        ],
      ),
    );
  }

  /// Metade esquerda do rodapé quando a barra de ação vem acompanhada de
  /// "voltar etapa" — só o canto inferior esquerdo é arredondado (o único
  /// que toca de verdade o contorno do card; o direito encosta na barra
  /// principal, que arredonda o canto dela). Widget próprio, e não uma
  /// variação de [_revertButton] (usado nos chips por item, compacto e com
  /// os 4 cantos iguais): aqui ele estica pra acompanhar a altura da barra
  /// ao lado (`CrossAxisAlignment.stretch` no Row de [_cardActionRow]).
  Widget _cardRevertButton(BuildContext context,
      {required VoidCallback onTap}) {
    const radius =
        BorderRadius.only(bottomLeft: Radius.circular(kOrderCardRadius));
    return Tooltip(
      message: 'Voltar etapa',
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: context.colors.errorColor.withValues(alpha: 0.12),
            borderRadius: radius,
          ),
          child: Icon(Icons.undo, size: 16, color: context.colors.errorColor),
        ),
      ),
    );
  }

  Widget _buildKdsItemRow(BuildContext context, WidgetRef ref, Order order,
      OrderItem item, bool isAdmin, KdsProductionMode mode) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildItemThumbnail(context, item.imageUrl),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.quantity}x ${item.name}',
                  style: const TextStyle(fontSize: 13),
                ),
                if (item.observation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.observation!,
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: context.colors.warningColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _buildItemAction(context, ref, order, item, isAdmin, mode),
        ],
      ),
    );
  }

  /// Observação do PEDIDO como um todo (diferente da observação de cada
  /// item, mostrada junto do próprio produto) — fica no final do card.
  ///
  /// No claro, o texto fica escuro (não âmbar) pra garantir leitura em cima
  /// do fundo amarelo suave — em cima de fundo escuro o próprio âmbar já é
  /// legível e continua reforçando "isso é um aviso" sozinho.
  Widget _buildOrderObservation(BuildContext context, String? observations) {
    if (observations == null || observations.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor =
        isDark ? context.colors.warningColor : context.colors.textColor;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:
            context.colors.warningColor.withValues(alpha: isDark ? 0.1 : 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: context.colors.warningColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sticky_note_2_outlined,
              size: 14, color: context.colors.warningColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              observations,
              style: TextStyle(fontSize: 12, color: textColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemThumbnail(BuildContext context, String? imageUrl) {
    const size = 26.0;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.colors.cardColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: Icon(Icons.restaurant_menu,
          size: 13, color: context.colors.textSecondaryColor),
    );

    if (imageUrl == null || imageUrl.isEmpty) {
      return placeholder;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => placeholder,
      ),
    );
  }

  /// Botão de ação por produto: cada item avança seu próprio preparo,
  /// independente dos outros itens do mesmo pedido. Administradores também
  /// veem um botão pra voltar uma etapa (corrigir um avanço feito por
  /// engano), um passo de cada vez.
  Widget _buildItemAction(BuildContext context, WidgetRef ref, Order order,
      OrderItem item, bool isAdmin, KdsProductionMode mode) {
    // No modo comanda inteira, quem avança é o botão do rodapé do card (ver
    // _buildCardAction) — o item só mostra em que pé está, sem chip
    // clicável, pra não sugerir uma ação que não existe nesse modo.
    if (mode == KdsProductionMode.wholeOrder) {
      return _buildItemStatusGlyph(context, item.status);
    }

    switch (item.status) {
      case OrderStatus.novo:
        return _actionChip(
          context,
          label: 'Iniciar',
          icon: Icons.play_arrow,
          color: context.colors.warningColor,
          onTap: () => ref
              .read(orderStatusUpdateProvider.notifier)
              .updateItemStatus(order.id, item.id, OrderStatus.emPreparo),
        );
      case OrderStatus.emPreparo:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAdmin) ...[
              _revertButton(
                context,
                onTap: () => ref
                    .read(orderStatusUpdateProvider.notifier)
                    .updateItemStatus(order.id, item.id, OrderStatus.novo),
              ),
              const SizedBox(width: 6),
            ],
            _actionChip(
              context,
              label: 'Finalizar',
              icon: Icons.check,
              color: context.colors.successColor,
              onTap: () => ref
                  .read(orderStatusUpdateProvider.notifier)
                  .updateItemStatus(order.id, item.id, OrderStatus.pronto),
            ),
          ],
        );
      case OrderStatus.pronto:
        if (!isAdmin) {
          return Icon(Icons.check_circle,
              color: context.colors.successColor, size: 20);
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _revertButton(
              context,
              onTap: () => ref
                  .read(orderStatusUpdateProvider.notifier)
                  .updateItemStatus(order.id, item.id, OrderStatus.emPreparo),
            ),
            const SizedBox(width: 6),
            Icon(Icons.check_circle,
                color: context.colors.successColor, size: 20),
          ],
        );
      case OrderStatus.entregue:
        return Icon(Icons.check_circle,
            color: context.colors.successColor, size: 20);
    }
  }

  /// Indicador (sem toque) do status de um item no modo comanda inteira —
  /// mesmo tamanho/posição do ícone que já existia pros itens "pronto" e
  /// "entregue" no modo item a item, só cobrindo os quatro status.
  Widget _buildItemStatusGlyph(BuildContext context, OrderStatus status) {
    switch (status) {
      case OrderStatus.novo:
        return Icon(Icons.radio_button_unchecked,
            size: 18,
            color: context.colors.textSecondaryColor.withValues(alpha: 0.6));
      case OrderStatus.emPreparo:
        return Icon(Icons.local_fire_department,
            size: 20, color: context.colors.warningColor);
      case OrderStatus.pronto:
      case OrderStatus.entregue:
        return Icon(Icons.check_circle,
            color: context.colors.successColor, size: 20);
    }
  }

  Widget _revertButton(BuildContext context, {required VoidCallback onTap}) {
    return Tooltip(
      message: 'Voltar etapa',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: context.colors.errorColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: context.colors.errorColor.withValues(alpha: 0.4)),
          ),
          child: Icon(Icons.undo, size: 14, color: context.colors.errorColor),
        ),
      ),
    );
  }

  Widget _actionChip(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, OrderStatus status) {
    final color = _getStatusColor(context, status);
    return Container(
      width: 100,
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

/// Lista de itens de um card de pedido. Fica travada (sem rolagem própria)
/// enquanto os itens couberem no espaço do card — assim um arraste em cima
/// dela continua "vazando" pro board por trás (grade ou coluna do kanban),
/// tanto no Windows quanto no Android. Só quando o pedido é grande demais
/// pra caber (detectado pela própria métrica de scroll, não por uma
/// contagem fixa de itens) ela vira rolável e mostra a barra de rolagem —
/// única forma de ver os itens que passam do card sem deixá-lo gigante.
class _OrderItemsList extends StatefulWidget {
  final Order order;
  final Widget Function(BuildContext context, OrderItem item) itemRowBuilder;

  const _OrderItemsList({required this.order, required this.itemRowBuilder});

  @override
  State<_OrderItemsList> createState() => _OrderItemsListState();
}

class _OrderItemsListState extends State<_OrderItemsList> {
  final _controller = ScrollController();
  bool _overflowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void didUpdateWidget(covariant _OrderItemsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.items.length != widget.order.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
    }
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
    final list = ListView.builder(
      controller: _controller,
      physics: _overflowing
          ? const ClampingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: widget.order.items.length,
      itemBuilder: (context, index) =>
          widget.itemRowBuilder(context, widget.order.items[index]),
    );

    if (!_overflowing) return list;

    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: list,
    );
  }
}
