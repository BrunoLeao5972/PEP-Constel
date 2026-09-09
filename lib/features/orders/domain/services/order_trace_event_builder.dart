import '../entities/order.dart';

/// Monta o payload de rastreabilidade de um pedido, pra a retaguarda
/// acompanhar o ciclo de produção completo (não só o status final) — um
/// evento por transição real de status do pedido (novo → em preparo →
/// pronto → entregue), disparado por [OrderStatusNotifier]
/// (order_provider.dart).
///
/// Só monta o `Map` — pra onde esse evento vai (Mongo, HTTP etc.) ainda não
/// foi decidido com o tech lead, então isso fica desacoplado de qualquer
/// destino de propósito.
Map<String, dynamic> buildOrderTraceEvent(
  Order order, {
  required DateTime eventAt,
  required OrderStatus? previousStatus,
}) {
  return {
    'evento': 'mudanca_status_pedido',
    'geradoEm': eventAt.toUtc().toIso8601String(),
    'statusAnterior': previousStatus?.name,
    'statusAtual': order.status.name,
    'pedido': _orderToJson(order),
  };
}

Map<String, dynamic> _orderToJson(Order order) {
  return {
    'id': order.id,
    'numero': order.number,
    'comandaCodigo': order.roundCode,
    'modalidade': order.modalityName,
    'localizador': order.locatorLabel,
    'senhaPdv': order.pdvSenha,
    'rotuloExibicao': order.modalityDisplay,
    'observacoes': order.observations,
    'status': order.status.name,
    'criadoEm': order.timestamp.toUtc().toIso8601String(),
    'atualizadoEm': order.updatedAt?.toUtc().toIso8601String(),
    'itens': order.items.map(_itemToJson).toList(),
  };
}

Map<String, dynamic> _itemToJson(OrderItem item) {
  return {
    'id': item.id,
    'nome': item.name,
    'quantidade': item.quantity,
    'status': item.status.name,
    'imagemUrl': item.imageUrl,
    'observacao': item.observation,
  };
}
