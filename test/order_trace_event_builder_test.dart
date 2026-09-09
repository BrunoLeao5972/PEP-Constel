import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:kds_constel/features/orders/domain/entities/order.dart';
import 'package:kds_constel/features/orders/domain/services/order_trace_event_builder.dart';

void main() {
  final order = Order(
    id: 'order-1',
    number: 42,
    items: [
      OrderItem(
        id: 'item-1',
        name: 'X-Burguer',
        quantity: 2,
        status: OrderStatus.emPreparo,
        imageUrl: 'https://exemplo.com/x-burguer.png',
        observation: 'sem cebola',
      ),
      OrderItem(
        id: 'item-2',
        name: 'Batata',
        quantity: 1,
        status: OrderStatus.emPreparo,
      ),
    ],
    observations: 'Cliente vai retirar às 13h',
    timestamp: DateTime.utc(2026, 8, 27, 12, 0),
    roundCode: 'r1',
    modalityName: 'Mesa',
    locatorLabel: '05',
    updatedAt: DateTime.utc(2026, 8, 27, 12, 5),
  );

  test('inclui todos os campos do pedido e dos itens', () {
    final event = buildOrderTraceEvent(
      order,
      eventAt: DateTime.utc(2026, 8, 27, 12, 5, 30),
      previousStatus: OrderStatus.novo,
    );

    expect(event['evento'], 'mudanca_status_pedido');
    expect(event['geradoEm'], '2026-08-27T12:05:30.000Z');
    expect(event['statusAnterior'], 'novo');
    expect(event['statusAtual'], 'emPreparo');

    final pedido = event['pedido'] as Map<String, dynamic>;
    expect(pedido['id'], 'order-1');
    expect(pedido['numero'], 42);
    expect(pedido['comandaCodigo'], 'r1');
    expect(pedido['modalidade'], 'Mesa');
    expect(pedido['localizador'], '05');
    expect(pedido['senhaPdv'], isNull);
    expect(pedido['rotuloExibicao'], 'Mesa 05');
    expect(pedido['observacoes'], 'Cliente vai retirar às 13h');
    expect(pedido['status'], 'emPreparo');
    expect(pedido['criadoEm'], '2026-08-27T12:00:00.000Z');
    expect(pedido['atualizadoEm'], '2026-08-27T12:05:00.000Z');

    final itens = pedido['itens'] as List;
    expect(itens, hasLength(2));
    final item1 = itens[0] as Map<String, dynamic>;
    expect(item1['id'], 'item-1');
    expect(item1['nome'], 'X-Burguer');
    expect(item1['quantidade'], 2);
    expect(item1['status'], 'emPreparo');
    expect(item1['imagemUrl'], 'https://exemplo.com/x-burguer.png');
    expect(item1['observacao'], 'sem cebola');
    final item2 = itens[1] as Map<String, dynamic>;
    expect(item2['imagemUrl'], isNull);
    expect(item2['observacao'], isNull);
  });

  test('statusAnterior null quando não há status anterior (pedido novo)', () {
    final event = buildOrderTraceEvent(
      order,
      eventAt: DateTime.utc(2026, 8, 27, 12, 5, 30),
      previousStatus: null,
    );
    expect(event['statusAnterior'], isNull);
  });

  test('o resultado é serializável em JSON sem adaptação nenhuma', () {
    final event = buildOrderTraceEvent(
      order,
      eventAt: DateTime.utc(2026, 8, 27, 12, 5, 30),
      previousStatus: OrderStatus.novo,
    );

    // jsonEncode lança se algum valor não for um tipo JSON nativo (String,
    // num, bool, null, Map, List) — confere isso sem precisar inspecionar
    // cada campo manualmente.
    final encoded = jsonEncode(event);
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    expect(decoded['pedido']['numero'], 42);
  });
}
