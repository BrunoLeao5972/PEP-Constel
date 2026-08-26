import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kds_constel/core/config/customer_facing_theme_config_provider.dart';
import 'package:kds_constel/core/theme/app_themes.dart';
import 'package:kds_constel/features/orders/domain/entities/order.dart';
import 'package:kds_constel/features/orders/domain/repositories/order_repository.dart';
import 'package:kds_constel/features/orders/presentation/pages/customer_facing_page.dart';
import 'package:kds_constel/features/orders/presentation/providers/order_provider.dart';
import 'package:kds_constel/features/settings/presentation/widgets/customer_facing_theme_section.dart';

/// Painel e Configurações rodam em TV, notebook, tablet e celular, no Windows
/// e no Android — estes testes varrem as resoluções em que isso acontece de
/// verdade e falham se qualquer uma estourar o layout (`RenderFlex
/// overflowed`), que é o jeito mais comum de quebrar uma tela responsiva sem
/// ninguém perceber até ela estar pendurada na parede do salão.
class _FakeOrderRepository implements OrderRepository {
  static final _orders = <Order>[
    for (var i = 0; i < 9; i++)
      Order(
        id: 'preparo-$i',
        number: i,
        items: [
          OrderItem(id: 'a$i', name: 'X', quantity: 1, status: OrderStatus.novo)
        ],
        timestamp: DateTime(2026, 8, 25, 12, i),
        roundCode: 'r$i',
        modalityName: 'Mesa',
        locatorLabel: '0$i',
      ),
    for (var i = 0; i < 6; i++)
      Order(
        id: 'pronto-$i',
        number: 100 + i,
        items: [
          OrderItem(
              id: 'b$i', name: 'Y', quantity: 1, status: OrderStatus.pronto)
        ],
        timestamp: DateTime(2026, 8, 25, 13, i),
        roundCode: 'p$i',
        pdvSenha: '000$i',
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const sizes = <Size>[
    Size(3840, 2160),
    Size(1920, 1080),
    Size(1366, 768),
    Size(1280, 800),
    Size(1024, 768),
    Size(800, 600),
    Size(768, 1024), // tablet em pé
    Size(600, 960),
    Size(412, 915), // celular
    Size(360, 640),
  ];

  for (final size in sizes) {
    testWidgets('Painel sem overflow em ${size.width}x${size.height}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      for (final theme in [AppThemes.dark, AppThemes.light]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              orderRepositoryProvider.overrideWithValue(_FakeOrderRepository()),
            ],
            child: MaterialApp(theme: theme, home: const CustomerFacingPage()),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'tema ${theme.brightness} em $size');
      }
    });
  }

  for (final width in <double>[1060, 900, 820, 700, 480, 360]) {
    testWidgets('Configurações sem overflow com $width de largura',
        (tester) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppThemes.dark,
            home: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: CustomerFacingThemeSection(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'fechado, $width');

      // Abre um editor de cor (o painel de presets + campo hexadecimal).
      await tester.ensureVisible(find.text('Fundo da tela'));
      await tester.tap(find.text('Fundo da tela'));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'editor aberto, $width');
      expect(find.text('PRESETS DA MARCA'), findsOneWidget);

      // Escolhe um preset e confere que o preview acompanha.
      await tester.ensureVisible(find.byTooltip('Roxo Constel (#6E48AA)'));
      await tester.tap(find.byTooltip('Roxo Constel (#6E48AA)'));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'preset aplicado, $width');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CustomerFacingThemeSection)),
        listen: false,
      );
      expect(container.read(customerFacingThemeConfigProvider).backgroundColor,
          const Color(0xFF6E48AA));

      // O ajuste fino RGB abre e cabe na largura disponível.
      await tester.ensureVisible(find.text('Ajuste fino RGB'));
      await tester.tap(find.text('Ajuste fino RGB'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'diálogo RGB, $width');
      expect(find.byType(Slider), findsNWidgets(5)); // R, G, B, A + raio
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'RGB cancelado, $width');

      // Restaurar padrões volta tudo.
      await tester.ensureVisible(find.text('Restaurar Padrões'));
      await tester.tap(find.text('Restaurar Padrões'));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'restaurado, $width');
      expect(
          container.read(customerFacingThemeConfigProvider).isDefault, isTrue);
    });
  }
}
