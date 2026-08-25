import '../entities/order.dart';

abstract class OrderRepository {
  Stream<List<Order>> getOrders();

  /// Pedidos das últimas 24h, incluindo os já entregues — ao contrário de
  /// [getOrders] (só ativos), serve pro histórico/dashboard do Admin.
  Stream<List<Order>> getOrderHistory();

  Future<void> updateOrderStatus(String orderId, OrderStatus newStatus);
  Future<void> updateItemStatus(
      String orderId, String itemId, OrderStatus newStatus);
}
