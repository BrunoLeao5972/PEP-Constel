import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kds_constel/features/orders/domain/entities/order.dart';
import 'package:kds_constel/features/orders/domain/repositories/order_repository.dart';
import 'package:kds_constel/features/orders/presentation/providers/order_provider.dart';

/// Repositório fake com dois itens em "novo" — o bastante pra provar que um
/// avanço item a item que NÃO muda a etapa agregada do pedido não dispara
/// evento, enquanto um que muda dispara.
class _FakeOrderRepository implements OrderRepository {
  static final _orders = <Order>[
    Order(
      id: 'order-1',
      number: 7,
      items: [
        OrderItem(
            id: 'item-1', name: 'X-Burguer', quantity: 1, status: OrderStatus.novo),
        OrderItem(
            id: 'item-2', name: 'Batata', quantity: 1, status: OrderStatus.novo),
      ],
      timestamp: DateTime(2026, 8, 26, 12),
      roundCode: 'r1',
      modalityName: 'Mesa',
      locatorLabel: '05',
    ),
  ];

  @override
  Stream<List<Order>> getOrders() => Stream.value(_orders);

  @override
  Stream<List<Order>> getOrderHistory() => Stream.value(const []);

  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus newStatus) async {}

  @override
  Future<void> updateItemStatus(
      String orderId, String itemId, OrderStatus newStatus) async {}
}

void main() {
  Future<ProviderContainer> makeContainer(
      List<Map<String, dynamic>> captured) async {
    final container = ProviderContainer(overrides: [
      orderRepositoryProvider.overrideWithValue(_FakeOrderRepository()),
      orderTraceSinkProvider.overrideWithValue(captured.add),
    ]);
    // ordersStreamProvider é lido de forma síncrona (valueOrNull) dentro do
    // notifier — sem esperar o primeiro valor aqui, "beforeOrder" viria
    // sempre null e nenhum teste destes exercitaria o caminho real.
    await container.read(ordersStreamProvider.future);
    return container;
  }

  test(
      'iniciar um item sozinho (pedido continua "novo" enquanto o outro '
      'item não começa) NÃO dispara evento — não é uma transição do '
      'pedido como um todo', () async {
    final captured = <Map<String, dynamic>>[];
    final container = await makeContainer(captured);
    addTearDown(container.dispose);

    // Isso não acontece nunca sozinho na prática (iniciar um item já muda
    // o agregado de novo->emPreparo), mas serve pra provar que a checagem
    // é sobre o AGREGADO, não sobre "algum item mudou": um item indo de
    // novo pra novo (no-op) não deveria dar em nada.
    await container
        .read(orderStatusUpdateProvider.notifier)
        .updateItemStatus('order-1', 'item-1', OrderStatus.novo);

    expect(captured, isEmpty);
  });

  test(
      'iniciar o primeiro item muda o pedido de novo pra em preparo — '
      'dispara evento com statusAnterior=novo e statusAtual=emPreparo',
      () async {
    final captured = <Map<String, dynamic>>[];
    final container = await makeContainer(captured);
    addTearDown(container.dispose);

    await container
        .read(orderStatusUpdateProvider.notifier)
        .updateItemStatus('order-1', 'item-1', OrderStatus.emPreparo);

    expect(captured, hasLength(1));
    expect(captured.single['statusAnterior'], 'novo');
    expect(captured.single['statusAtual'], 'emPreparo');
    final itens = captured.single['pedido']['itens'] as List;
    // O item que mudou já aparece com o novo status no evento — é o
    // "depois" da transição, não o "antes".
    final item1 = itens.firstWhere((i) => i['id'] == 'item-1');
    expect(item1['status'], 'emPreparo');
  });

  test(
      'avançar a comanda inteira (bulk) dispara um único evento novo -> '
      'em preparo, não um por item', () async {
    final captured = <Map<String, dynamic>>[];
    final container = await makeContainer(captured);
    addTearDown(container.dispose);

    await container
        .read(orderStatusUpdateProvider.notifier)
        .updateStatus('order-1', OrderStatus.emPreparo);

    expect(captured, hasLength(1));
    expect(captured.single['statusAnterior'], 'novo');
    expect(captured.single['statusAtual'], 'emPreparo');
  });

  test('pedido desconhecido (não está no snapshot atual) não derruba nada',
      () async {
    final captured = <Map<String, dynamic>>[];
    final container = await makeContainer(captured);
    addTearDown(container.dispose);

    await container
        .read(orderStatusUpdateProvider.notifier)
        .updateStatus('order-inexistente', OrderStatus.emPreparo);

    expect(captured, isEmpty);
  });
}
