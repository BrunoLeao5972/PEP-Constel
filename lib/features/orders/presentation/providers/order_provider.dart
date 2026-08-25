import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/data/mongo_service.dart';
import '../../domain/entities/order.dart';
import '../../domain/repositories/order_repository.dart';
import '../../data/repositories/mongo_order_repository.dart';

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  final db = ref.watch(mongoDbProvider).requireValue;
  return MongoOrderRepository(db);
});

final ordersStreamProvider = StreamProvider<List<Order>>((ref) {
  final repository = ref.watch(orderRepositoryProvider);
  return repository.getOrders();
});

final orderHistoryStreamProvider = StreamProvider<List<Order>>((ref) {
  final repository = ref.watch(orderRepositoryProvider);
  return repository.getOrderHistory();
});

/// Overrides otimistas de status por item (chave = OrderItem.id), aplicados
/// por cima do que vem do Mongo. O polling do repositório roda a cada 2s
/// (getOrders) ou 10s (getOrderHistory) — sem isso, tocar em "Iniciar" só
/// refletia na tela no próximo poll, o que parecia lento/sem resposta.
class ItemStatusOverridesController
    extends StateNotifier<Map<String, OrderStatus>> {
  final Ref _ref;

  ItemStatusOverridesController(this._ref) : super(const {}) {
    _ref.listen<AsyncValue<List<Order>>>(ordersStreamProvider,
        (previous, next) {
      next.whenData(_reconcile);
    });
    _ref.listen<AsyncValue<List<Order>>>(orderHistoryStreamProvider,
        (previous, next) {
      next.whenData(_reconcile);
    });
  }

  void set(String itemId, OrderStatus status) {
    if (state[itemId] == status) return;
    state = {...state, itemId: status};
  }

  void setMany(Iterable<String> itemIds, OrderStatus status) {
    final next = {...state};
    for (final id in itemIds) {
      next[id] = status;
    }
    state = next;
  }

  void clear(String itemId) {
    if (!state.containsKey(itemId)) return;
    final next = {...state}..remove(itemId);
    state = next;
  }

  // Assim que o próprio Mongo confirmar (poll bateu com o override), o
  // override deixa de ser necessário — remove pra não mascarar uma mudança
  // real feita por outro caminho depois.
  //
  // Importante: só limpa numa confirmação POSITIVA (status bateu). O item
  // ficar ausente do snapshot NÃO conta como confirmação — ordersStreamProvider
  // filtra pedidos "produzida" (entregues), então um item recém revertido de
  // "entregue" fica ausente de lá até a escrita realmente terminar e o
  // próximo poll pegar o pedido de volta. Tratar ausência como confirmação
  // limpava o override cedo demais e a reversão "voltava sozinha" na tela até
  // o poll (mais lento) do histórico do Admin realmente confirmar.
  void _reconcile(List<Order> orders) {
    if (state.isEmpty) return;
    final realStatusByItemId = <String, OrderStatus>{
      for (final order in orders)
        for (final item in order.items) item.id: item.status,
    };
    final next = {...state};
    var changed = false;
    for (final itemId in state.keys.toList()) {
      if (realStatusByItemId[itemId] == next[itemId]) {
        next.remove(itemId);
        changed = true;
      }
    }
    if (changed) state = next;
  }
}

final itemStatusOverridesProvider = StateNotifierProvider<
    ItemStatusOverridesController, Map<String, OrderStatus>>((ref) {
  return ItemStatusOverridesController(ref);
});

List<Order> _applyOverrides(
    List<Order> orders, Map<String, OrderStatus> overrides) {
  if (overrides.isEmpty) return orders;
  return orders.map((order) {
    var changedAny = false;
    final items = order.items.map((item) {
      final override = overrides[item.id];
      if (override == null || override == item.status) return item;
      changedAny = true;
      return OrderItem(
        id: item.id,
        name: item.name,
        quantity: item.quantity,
        status: override,
        imageUrl: item.imageUrl,
        observation: item.observation,
      );
    }).toList();
    return changedAny ? order.copyWith(items: items) : order;
  }).toList();
}

/// ordersStreamProvider com os overrides otimistas aplicados — usar em vez do
/// original em qualquer tela que exiba status de item (Cozinha/Admin).
final displayOrdersProvider = Provider<AsyncValue<List<Order>>>((ref) {
  final ordersAsync = ref.watch(ordersStreamProvider);
  final overrides = ref.watch(itemStatusOverridesProvider);
  return ordersAsync.whenData((orders) => _applyOverrides(orders, overrides));
});

/// orderHistoryStreamProvider com os overrides otimistas aplicados (mesma
/// razão do displayOrdersProvider, mas pro histórico usado no Admin).
final displayOrderHistoryProvider = Provider<AsyncValue<List<Order>>>((ref) {
  final historyAsync = ref.watch(orderHistoryStreamProvider);
  final overrides = ref.watch(itemStatusOverridesProvider);
  return historyAsync.whenData((orders) => _applyOverrides(orders, overrides));
});

class OrderStatusNotifier extends StateNotifier<AsyncValue<void>> {
  final OrderRepository _repository;
  final Ref _ref;

  OrderStatusNotifier(this._repository, this._ref)
      : super(const AsyncValue.data(null));

  Future<void> updateStatus(String orderId, OrderStatus newStatus) async {
    // Otimista: aplica em todos os itens do pedido já na tela (o repositório
    // também propaga o novo status pra todos os itens de uma vez).
    final knownOrders = _ref.read(ordersStreamProvider).valueOrNull ??
        _ref.read(orderHistoryStreamProvider).valueOrNull;
    final matches =
        knownOrders?.where((o) => o.id == orderId) ?? const <Order>[];
    final itemIds = matches.isEmpty
        ? const <String>[]
        : matches.first.items.map((i) => i.id);
    final overrides = _ref.read(itemStatusOverridesProvider.notifier);
    overrides.setMany(itemIds, newStatus);

    state = const AsyncValue.loading();
    try {
      await _repository.updateOrderStatus(orderId, newStatus);
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      for (final id in itemIds) {
        overrides.clear(id);
      }
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> updateItemStatus(
      String orderId, String itemId, OrderStatus newStatus) async {
    final overrides = _ref.read(itemStatusOverridesProvider.notifier);
    overrides.set(itemId, newStatus);

    state = const AsyncValue.loading();
    try {
      await _repository.updateItemStatus(orderId, itemId, newStatus);
      state = const AsyncValue.data(null);
    } catch (e, stack) {
      overrides.clear(itemId);
      state = AsyncValue.error(e, stack);
    }
  }
}

final orderStatusUpdateProvider =
    StateNotifierProvider<OrderStatusNotifier, AsyncValue<void>>((ref) {
  final repository = ref.watch(orderRepositoryProvider);
  return OrderStatusNotifier(repository, ref);
});
