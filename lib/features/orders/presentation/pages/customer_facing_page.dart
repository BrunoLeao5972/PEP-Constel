import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/order_provider.dart';
import '../providers/order_caller_provider.dart';
import '../../domain/entities/order.dart';
import '../../../../core/config/panel_display_config_provider.dart';
import '../../../../core/theme/app_colors.dart';
import 'package:intl/intl.dart';

class CustomerFacingPage extends ConsumerWidget {
  const CustomerFacingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersStreamProvider);
    final callLabels = ref.watch(orderCallLabelsProvider);
    final panelDisplay = ref.watch(panelDisplayConfigProvider);

    return Scaffold(
      backgroundColor: context.colors.backgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 28),
          Text(
            'ACOMPANHE SEU PEDIDO',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: context.colors.accentColor,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('HH:mm').format(DateTime.now()),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 20, color: context.colors.textSecondaryColor),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ordersAsync.when(
              data: (allOrders) {
                final orders = allOrders
                    .where((o) => panelDisplay.isVisible(o.modalityName))
                    .toList();

                final preparing = orders
                    .where((o) =>
                        o.status == OrderStatus.emPreparo ||
                        o.status == OrderStatus.novo)
                    .toList()
                  ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

                final ready = orders
                    .where((o) => o.status == OrderStatus.pronto)
                    .toList()
                  ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

                final currentCalled = ready.isNotEmpty ? ready.first : null;
                final readyQueue =
                    ready.length > 1 ? ready.sublist(1) : <Order>[];

                return Row(
                  children: [
                    _buildPreparingColumn(context, preparing, callLabels),
                    Container(width: 1, color: context.colors.borderColor),
                    _buildCurrentCallColumn(context, currentCalled, callLabels),
                    Container(width: 1, color: context.colors.borderColor),
                    _buildReadyQueueColumn(context, readyQueue, callLabels),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Erro: $err')),
            ),
          ),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildPreparingColumn(BuildContext context, List<Order> orders,
      Map<String, String> callLabels) {
    return Expanded(
      flex: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '🔥 EM PREPARO',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: context.colors.warningColor,
              ),
            ),
          ),
          Expanded(
            child: orders.isEmpty
                ? Center(
                    child: Text(
                      'Nenhum pedido em preparo',
                      style: TextStyle(
                          color: context.colors.textSecondaryColor,
                          fontSize: 16),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount =
                          (constraints.maxWidth / 190).floor().clamp(2, 5);

                      return GridView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: 3.4,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          return _buildSmallOrderCard(
                            context,
                            order: orders[index],
                            color: context.colors.warningColor,
                            label: callLabels[orders[index].id] ??
                                orders[index].pdvCallerLabel,
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentCallColumn(BuildContext context, Order? currentCalled,
      Map<String, String> callLabels) {
    return Expanded(
      flex: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '📢 CHAMANDO AGORA',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: context.colors.accentColor,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: currentCalled == null
                  ? const _EmptyPanelState(
                      message: 'Nenhum pedido\nsendo chamado',
                    )
                  : Container(
                      width: 238,
                      height: 224,
                      decoration: BoxDecoration(
                        color: context.colors.cardColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: context.colors.accentColor
                              .withValues(alpha: 1.20),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: context.colors.accentColor
                                .withValues(alpha: 0.18),
                            blurRadius: 14,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'PEDIDO',
                            style: TextStyle(
                              color: context.colors.textSecondaryColor,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                callLabels[currentCalled.id] ??
                                    currentCalled.pdvCallerLabel,
                                style: TextStyle(
                                  color: context.colors.accentColor,
                                  fontSize: 73,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Pronto para retirada',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.colors.textColor
                                  .withValues(alpha: 0.85),
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadyQueueColumn(BuildContext context, List<Order> orders,
      Map<String, String> callLabels) {
    return Expanded(
      flex: 3, // igual ao Em Preparo — garante centralização do card do meio
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              '🔔 FILA DE PRONTOS',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: context.colors.successColor,
              ),
            ),
          ),
          Expanded(
            child: orders.isEmpty
                ? const _EmptyPanelState(
                    message: 'Sem pedidos aguardando retirada',
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount =
                          (constraints.maxWidth / 170).floor().clamp(2, 4);

                      return GridView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: 3.2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                        ),
                        itemCount: orders.length,
                        itemBuilder: (context, index) {
                          return _buildSmallOrderCard(
                            context,
                            order: orders[index],
                            color: context.colors.successColor,
                            label: callLabels[orders[index].id] ??
                                orders[index].pdvCallerLabel,
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallOrderCard(
    BuildContext context, {
    required Order order,
    required Color color,
    required String label,
  }) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: context.colors.cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.6),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(
        'Solução Sistemas - A sua cozinha ainda mais eficiente',
        textAlign: TextAlign.center,
        style:
            TextStyle(color: context.colors.textSecondaryColor, fontSize: 13),
      ),
    );
  }
}

class _EmptyPanelState extends StatelessWidget {
  final String message;

  const _EmptyPanelState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: TextStyle(
          color: context.colors.textSecondaryColor,
          fontSize: 16,
        ),
      ),
    );
  }
}
