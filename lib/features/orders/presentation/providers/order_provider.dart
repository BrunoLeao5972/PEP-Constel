import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/data/mongo_service.dart';
import '../../domain/entities/order.dart';
import '../../domain/repositories/order_repository.dart';
import '../../domain/services/order_trace_event_builder.dart';
import '../../data/repositories/mongo_order_repository.dart';
import '../../data/services/order_trace_file_sink.dart';

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

OrderItem _withStatus(OrderItem item, OrderStatus status) => OrderItem(
      id: item.id,
      name: item.name,
      quantity: item.quantity,
      status: status,
      imageUrl: item.imageUrl,
      observation: item.observation,
    );

List<Order> _applyOverrides(
    List<Order> orders, Map<String, OrderStatus> overrides) {
  if (overrides.isEmpty) return orders;
  return orders.map((order) {
    var changedAny = false;
    final items = order.items.map((item) {
      final override = overrides[item.id];
      if (override == null || override == item.status) return item;
      changedAny = true;
      return _withStatus(item, override);
    }).toList();
    return changedAny ? order.copyWith(items: items) : order;
  }).toList();
}

/// Pra onde um evento de rastreabilidade vai. Fica isolado num provider —
/// o destino de verdade (gravar numa coleção do Mongo, mandar por HTTP pra
/// retaguarda etc.) ainda não foi decidido com o tech lead, e assim dá pra
/// trocar só este provider (em [main.dart] ou onde a instância de produção
/// for montada) sem tocar em [OrderStatusNotifier]. Síncrono de propósito:
/// a atualização de status do pedido não deve esperar (nem falhar por
/// causa de um evento de auditoria) — se a implementação de verdade for
/// assíncrona (grava no Mongo, chama um endpoint), ela cuida disso sozinha
/// (fire-and-forget) em vez de propagar a Future pra cá.
typedef OrderTraceSink = void Function(Map<String, dynamic> event);

/// Implementação padrão: grava num arquivo local (`order_trace_file_sink.dart`)
/// — funciona rodando o app instalado (release), não só em `flutter run`.
/// `developer.log` sozinho não serviria pra isso: ele só aparece com o VM
/// service anexado (DevTools/`flutter run` em debug), que não existe num
/// `.exe`/`.apk` de produção — por isso ainda manda pra lá também (útil
/// durante o desenvolvimento), mas o arquivo é quem garante que o evento
/// fica visível pra quem só tem o app instalado.
void _logOrderTraceEvent(Map<String, dynamic> event) {
  developer.log(jsonEncode(event), name: 'order_trace');
  unawaited(appendOrderTraceEvent(event));
}

final orderTraceSinkProvider =
    Provider<OrderTraceSink>((ref) => _logOrderTraceEvent);

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
    final beforeOrder = matches.isEmpty ? null : matches.first;
    final itemIds = beforeOrder?.items.map((i) => i.id) ?? const <String>[];
    final overrides = _ref.read(itemStatusOverridesProvider.notifier);
    overrides.setMany(itemIds, newStatus);

    state = const AsyncValue.loading();
    try {
      await _repository.updateOrderStatus(orderId, newStatus);
      state = const AsyncValue.data(null);
      if (beforeOrder != null) {
        final afterOrder = beforeOrder.copyWith(
          items: beforeOrder.items
              .map((item) => _withStatus(item, newStatus))
              .toList(),
        );
        _emitOrderTraceIfStatusChanged(beforeOrder, afterOrder);
      }
    } catch (e, stack) {
      for (final id in itemIds) {
        overrides.clear(id);
      }
      state = AsyncValue.error(e, stack);
    }
  }

  Future<void> updateItemStatus(
      String orderId, String itemId, OrderStatus newStatus) async {
    final knownOrders = _ref.read(ordersStreamProvider).valueOrNull ??
        _ref.read(orderHistoryStreamProvider).valueOrNull;
    final matches =
        knownOrders?.where((o) => o.id == orderId) ?? const <Order>[];
    final beforeOrder = matches.isEmpty ? null : matches.first;

    final overrides = _ref.read(itemStatusOverridesProvider.notifier);
    overrides.set(itemId, newStatus);

    state = const AsyncValue.loading();
    try {
      await _repository.updateItemStatus(orderId, itemId, newStatus);
      state = const AsyncValue.data(null);
      if (beforeOrder != null) {
        final afterOrder = beforeOrder.copyWith(
          items: beforeOrder.items
              .map((item) => item.id == itemId
                  ? _withStatus(item, newStatus)
                  : item)
              .toList(),
        );
        _emitOrderTraceIfStatusChanged(beforeOrder, afterOrder);
      }
    } catch (e, stack) {
      overrides.clear(itemId);
      state = AsyncValue.error(e, stack);
    }
  }

  /// Só emite se [afterOrder] realmente mudou de status AGREGADO em
  /// relação a [beforeOrder] — não a cada clique em item: no modo item a
  /// item, vários toques acontecem sem o pedido como um todo mudar de
  /// etapa (ver [Order.status]), e o pedido do tech lead foi rastrear as
  /// transições do pedido, não cada micro-ação da cozinha.
  void _emitOrderTraceIfStatusChanged(Order beforeOrder, Order afterOrder) {
    final previousStatus = beforeOrder.status;
    if (previousStatus == afterOrder.status) return;
    final event = buildOrderTraceEvent(afterOrder,
        eventAt: DateTime.now(), previousStatus: previousStatus);
    _ref.read(orderTraceSinkProvider)(event);
  }
}

final orderStatusUpdateProvider =
    StateNotifierProvider<OrderStatusNotifier, AsyncValue<void>>((ref) {
  final repository = ref.watch(orderRepositoryProvider);
  return OrderStatusNotifier(repository, ref);
});
