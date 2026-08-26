import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mongo_dart/mongo_dart.dart' show Db;

import 'package:kds_constel/core/data/mongo_service.dart';
import 'package:kds_constel/core/theme/app_themes.dart';
import 'package:kds_constel/features/auth/domain/entities/kds_user.dart';
import 'package:kds_constel/features/auth/presentation/providers/auth_provider.dart';
import 'package:kds_constel/features/orders/domain/entities/order.dart';
import 'package:kds_constel/features/orders/domain/repositories/order_repository.dart';
import 'package:kds_constel/features/orders/presentation/providers/order_provider.dart';
import 'package:kds_constel/main.dart';

class _TestOrderRepository implements OrderRepository {
  @override
  Stream<List<Order>> getOrders() => Stream.value(const []);

  @override
  Stream<List<Order>> getOrderHistory() => Stream.value(const []);

  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus newStatus) async {}

  @override
  Future<void> updateItemStatus(
      String orderId, String itemId, OrderStatus newStatus) async {}
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(Ref ref, KdsUser user) : super(ref) {
    state = AsyncValue.data(user);
  }
}

void main() {
  testWidgets('renders KDS shell for a logged-in user',
      (WidgetTester tester) async {
    await initializeDateFormatting('pt_BR');
    tester.view.physicalSize = const Size(2400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderRepositoryProvider.overrideWithValue(_TestOrderRepository()),
          // A aba Configurações observa mongoDbProvider direto (fora do
          // OrderRepository, que já foi trocado acima) — sem isso, o teste
          // dispara uma tentativa de conexão real com o Mongo e deixa um
          // Timer pendente (o timeout de conexão) quando a árvore de widgets
          // é descartada no fim do teste.
          mongoDbProvider.overrideWith((ref) => Completer<Db>().future),
          authControllerProvider.overrideWith(
            (ref) => _FakeAuthController(
              ref,
              KdsUser(
                  id: '1',
                  credencial: 'teste',
                  nome: 'Teste',
                  administrador: false),
            ),
          ),
        ],
        child: MaterialApp(theme: AppThemes.dark, home: const MainScaffold()),
      ),
    );
    await tester.pump();

    expect(find.text('Cozinha'), findsWidgets);
    expect(find.text('Nenhuma demanda pendente!'), findsOneWidget);
    expect(find.text('Teste'), findsOneWidget);
  });
}
