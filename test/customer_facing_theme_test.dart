import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kds_constel/core/config/customer_facing_theme_config.dart';
import 'package:kds_constel/core/config/customer_facing_theme_config_provider.dart';
import 'package:kds_constel/core/theme/app_colors.dart';
import 'package:kds_constel/core/theme/app_themes.dart';
import 'package:kds_constel/features/orders/domain/entities/order.dart';
import 'package:kds_constel/features/orders/domain/repositories/order_repository.dart';
import 'package:kds_constel/features/orders/presentation/pages/customer_facing_page.dart';
import 'package:kds_constel/features/orders/presentation/providers/order_provider.dart';
import 'package:kds_constel/features/settings/presentation/widgets/customer_facing_preview_widget.dart';
import 'package:kds_constel/features/settings/presentation/widgets/customer_facing_theme_section.dart';

/// Um pedido pronto (senha 0002) e um em preparo (senha 0003) — o suficiente
/// para o Painel ter conteúdo nas três seções.
class _FakeOrderRepository implements OrderRepository {
  static final _orders = <Order>[
    Order(
      id: 'pronto-1',
      number: 2,
      items: [
        OrderItem(
            id: 'i1',
            name: 'X-Burguer',
            quantity: 1,
            status: OrderStatus.pronto)
      ],
      timestamp: DateTime(2026, 8, 25, 12, 40),
      roundCode: 'r1',
      pdvSenha: '0002',
    ),
    Order(
      id: 'preparo-1',
      number: 3,
      items: [
        OrderItem(
            id: 'i2', name: 'Batata', quantity: 1, status: OrderStatus.novo)
      ],
      timestamp: DateTime(2026, 8, 25, 12, 42),
      roundCode: 'r2',
      pdvSenha: '0003',
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('CustomerFacingThemeConfig', () {
    test('sem personalização, o Painel continua sendo o do tema ativo', () {
      const config = CustomerFacingThemeConfig();

      final dark = config.resolve(AppColors.dark);
      expect(dark.background, const Color(0xFF161821));
      expect(dark.inPreparation, const Color(0xFFFFB300));
      expect(dark.callingNow, const Color(0xFFFDB813));
      expect(dark.readyQueue, const Color(0xFF4CAF50));
      expect(dark.cardBorderRadius, 8.0);

      expect(
          config.resolve(AppColors.light).background, const Color(0xFFF4F5F8));
      expect(config.isDefault, isTrue);
    });

    test('cor escolhida vence o tema; o resto segue automático', () {
      const custom = Color(0xFF00BCD4);
      final config = const CustomerFacingThemeConfig()
          .withColor(CustomerFacingColorSlot.inPreparation, custom);

      final palette = config.resolve(AppColors.dark);
      expect(palette.inPreparation, custom);
      expect(palette.callingNow, const Color(0xFFFDB813));
      expect(palette.background, const Color(0xFF161821));
      expect(config.isDefault, isFalse);
    });

    test('fundo escuro escolhido no tema claro não deixa texto ilegível', () {
      // O app está no claro (texto quase preto), mas o Painel foi configurado
      // com fundo quase preto: os textos automáticos têm que virar os do
      // tema escuro, senão a tela do cliente fica preto no preto.
      final config = const CustomerFacingThemeConfig().withColor(
          CustomerFacingColorSlot.background, const Color(0xFF101014));

      final palette = config.resolve(AppColors.light);
      expect(palette.mutedText, AppColors.dark.textSecondaryColor);
      expect(palette.bodyText, AppColors.dark.textColor);
      expect(palette.cardBackground, AppColors.dark.cardColor);
    });

    test('a borda/o número do card seguem a coluna até serem personalizados',
        () {
      final auto = const CustomerFacingThemeConfig().resolve(AppColors.dark);
      expect(auto.cardTextFor(auto.readyQueue), auto.readyQueue);
      expect(auto.cardBorderFor(auto.readyQueue).a, closeTo(0.35, 0.01));

      const fixed = Color(0xFFFFFFFF);
      final custom = const CustomerFacingThemeConfig()
          .withColor(CustomerFacingColorSlot.cardText, fixed)
          .withColor(CustomerFacingColorSlot.cardBorder, fixed)
          .resolve(AppColors.dark);
      expect(custom.cardTextFor(custom.readyQueue), fixed);
      expect(custom.cardBorderFor(custom.readyQueue), fixed);
    });

    test('ida e volta pelo JSON preserva tudo', () {
      final config = const CustomerFacingThemeConfig()
          .withColor(
              CustomerFacingColorSlot.background, const Color(0xFF101014))
          .withColor(
              CustomerFacingColorSlot.headerText, const Color(0xFFAABBCC))
          .withColor(
              CustomerFacingColorSlot.readyQueue, const Color(0xFF00FF00))
          .withColor(
              CustomerFacingColorSlot.cardBackground, const Color(0x80FFFFFF))
          .withCardBorderRadius(20);

      expect(CustomerFacingThemeConfig.fromJson(config.toJson()), config);
    });

    test('JSON estranho volta pro automático em vez de estourar', () {
      final config = CustomerFacingThemeConfig.fromJson(const <String, dynamic>{
        'backgroundColor': 'azul',
        'headerTextColor': -5,
        'columnHeaderColors': 42,
        'cardTheme': <String, dynamic>{'cardBorderRadius': 'oito'},
      });

      expect(config.isDefault, isTrue);
      expect(
          config.resolve(AppColors.dark).background, const Color(0xFF161821));
    });

    test('raio fora da faixa segura é limitado', () {
      expect(
        const CustomerFacingThemeConfig()
            .withCardBorderRadius(999)
            .cardTheme
            .cardBorderRadius,
        CustomerFacingCardTheme.maxCardBorderRadius,
      );
    });

    test('withColor(null) devolve o campo ao automático', () {
      final config = const CustomerFacingThemeConfig()
          .withColor(
              CustomerFacingColorSlot.callingNow, const Color(0xFF123456))
          .withColor(CustomerFacingColorSlot.callingNow, null);

      expect(config.columnHeaderColors.callingNowColor, isNull);
      expect(config.isDefault, isTrue);
    });
  });

  group('persistência', () {
    test('a cor escolhida sobrevive ao fechar e abrir o app', () async {
      final first = ProviderContainer();
      addTearDown(first.dispose);
      await first.read(customerFacingThemeConfigProvider.notifier).ready;
      await first.read(customerFacingThemeConfigProvider.notifier).setColor(
          CustomerFacingColorSlot.background, const Color(0xFF102030));

      final reopened = ProviderContainer();
      addTearDown(reopened.dispose);
      await reopened.read(customerFacingThemeConfigProvider.notifier).ready;

      expect(reopened.read(customerFacingThemeConfigProvider).backgroundColor,
          const Color(0xFF102030));
    });

    test('Restaurar Padrões limpa o que estava salvo', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier =
          container.read(customerFacingThemeConfigProvider.notifier);
      await notifier.ready;
      await notifier.setColor(
          CustomerFacingColorSlot.headerText, const Color(0xFF102030));
      await notifier.restoreDefaults();

      final reopened = ProviderContainer();
      addTearDown(reopened.dispose);
      await reopened.read(customerFacingThemeConfigProvider.notifier).ready;

      expect(
          reopened.read(customerFacingThemeConfigProvider).isDefault, isTrue);
    });
  });

  testWidgets('preview das Configurações repinta no mesmo frame',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppThemes.dark,
          home: const Scaffold(
            body: Center(
              child: SizedBox(width: 600, child: CustomerFacingPreviewWidget()),
            ),
          ),
        ),
      ),
    );

    // Ícones vetorizados no lugar dos emojis, iguais aos da tela real.
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    expect(find.byIcon(Icons.campaign_rounded), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);

    Color titleColor() =>
        tester.widget<Text>(find.text('EM PREPARO')).style!.color!;
    expect(titleColor(), const Color(0xFFFFB300));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CustomerFacingPreviewWidget)),
      listen: false,
    );
    await container.read(customerFacingThemeConfigProvider.notifier).setColor(
        CustomerFacingColorSlot.inPreparation, const Color(0xFF00BCD4));
    await tester.pump();

    expect(titleColor(), const Color(0xFF00BCD4));
  });

  testWidgets('Painel aplica a personalização e não usa mais emoji',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          orderRepositoryProvider.overrideWithValue(_FakeOrderRepository()),
        ],
        child: MaterialApp(
          theme: AppThemes.dark,
          home: const CustomerFacingPage(),
        ),
      ),
    );
    await tester.pump(); // deixa o stream de pedidos emitir

    expect(find.text('🔥 EM PREPARO'), findsNothing);
    expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    expect(find.text('EM PREPARO'), findsOneWidget);
    expect(find.text('0002'), findsOneWidget); // senha em chamada

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CustomerFacingPage)),
      listen: false,
    );
    await container
        .read(customerFacingThemeConfigProvider.notifier)
        .setColor(CustomerFacingColorSlot.background, const Color(0xFF102030));
    await tester.pump();

    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        const Color(0xFF102030));
  });

  group('ajuste fino RGB', () {
    Future<ProviderContainer> abrirSecao(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1100, 1600);
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

      return ProviderScope.containerOf(
        tester.element(find.byType(CustomerFacingThemeSection)),
        listen: false,
      );
    }

    /// Os quatro sliders do diálogo, na ordem R, G, B, A — `find.byType`
    /// direto pegaria também o slider de raio da borda, que fica na seção.
    Finder canais() => find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Slider),
        );

    testWidgets('slider muda a cor, o HEX e o preview ao mesmo tempo',
        (tester) async {
      final container = await abrirSecao(tester);

      await tester.tap(find.text('Em preparo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajuste fino RGB'));
      await tester.pumpAndSettle();

      // Abre já na cor que o Painel usa hoje nessa coluna.
      expect(find.text('#FFB300'), findsWidgets);

      // Zera o canal G arrastando o slider até a ponta esquerda.
      await tester.drag(canais().at(1), const Offset(-600, 0)); // G
      await tester.pumpAndSettle();

      final cor = container
          .read(customerFacingThemeConfigProvider)
          .columnHeaderColors
          .inPreparationColor;
      expect(cor, isNotNull);
      expect(cor!.redByte, 255);
      expect(cor.greenByte, 0);

      // HEX do diálogo, subtítulo da lista e caixa de texto, os três juntos.
      expect(find.text('#FF0000'), findsWidgets);
      final hexField = tester.widget<TextField>(find.byType(TextField));
      expect(hexField.controller!.text, '#FF0000');
    });

    testWidgets('Cancelar devolve o campo ao estado anterior', (tester) async {
      final container = await abrirSecao(tester);

      await tester.tap(find.text('Em preparo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajuste fino RGB'));
      await tester.pumpAndSettle();

      await tester.drag(canais().first, const Offset(-600, 0)); // R
      await tester.pumpAndSettle();
      expect(
          container.read(customerFacingThemeConfigProvider).isDefault, isFalse);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // Voltou pro estado de antes de abrir — que era "nunca personalizado",
      // e não "a cor que o tema dava".
      expect(
          container.read(customerFacingThemeConfigProvider).isDefault, isTrue);
    });

    testWidgets('não sobrou rótulo legado de "Automático — ..."',
        (tester) async {
      await abrirSecao(tester);

      expect(find.textContaining('Automático —'), findsNothing);
      expect(find.textContaining('cor da própria coluna'), findsNothing);
      // No lugar deles, cada cor mostra o HEX que está valendo.
      expect(find.text('#4CAF50'), findsOneWidget); // Fila de prontos
    });
  });

  group("marca d'água do rodapé", () {
    /// Razão de contraste do WCAG — 4,5:1 é o mínimo para texto normal.
    double contraste(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
    }

    Color tintaSobre(Color fundo) => const CustomerFacingThemeConfig()
        .withColor(CustomerFacingColorSlot.background, fundo)
        .resolve(AppColors.dark)
        .watermarkInk;

    test('sai clara no fundo escuro e escura no fundo claro', () {
      expect(tintaSobre(const Color(0xFF161821)), const Color(0xFFFFFFFF));
      expect(tintaSobre(const Color(0xFF000000)), const Color(0xFFFFFFFF));
      expect(tintaSobre(const Color(0xFFF4F5F8)), const Color(0xFF000000));
      expect(tintaSobre(const Color(0xFFFFFFFF)), const Color(0xFF000000));
    });

    test('continua legível em qualquer fundo, inclusive nos tons médios', () {
      // Varre a escala de cinza inteira: é onde a "cor contrária" ingênua
      // (inverter os canais RGB) falharia — o inverso de #808080 é #7F7F7F.
      for (var tom = 0; tom <= 255; tom += 5) {
        final fundo = Color.fromARGB(255, tom, tom, tom);
        expect(contraste(fundo, tintaSobre(fundo)), greaterThan(4.5),
            reason: 'cinza $tom');
      }

      // E nas cores saturadas que um estabelecimento realmente escolheria.
      for (final fundo in const [
        Color(0xFF6E48AA), // roxo Constel
        Color(0xFFFDB813), // dourado Constel
        Color(0xFF4CAF50),
        Color(0xFFE53935),
        Color(0xFF2196F3),
      ]) {
        expect(contraste(fundo, tintaSobre(fundo)), greaterThan(4.5),
            reason: colorToHex(fundo));
      }
    });

    test('não é personalizável — não existe slot para ela', () {
      expect(
        CustomerFacingColorSlot.values.map((slot) => slot.name),
        isNot(contains('footerText')),
      );
    });

    test('personalização antiga com cor de rodapé é simplesmente ignorada', () {
      // Aparelho que salvou a config quando o rodapé ainda entrava na paleta.
      final config = CustomerFacingThemeConfig.fromJson(const <String, dynamic>{
        'footerTextColor': 0xFF123456,
      });

      expect(config.isDefault, isTrue);
      expect(
          config.resolve(AppColors.dark).watermarkInk, const Color(0xFFFFFFFF));
    });

    testWidgets('no Painel, acompanha a troca de fundo', (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderRepositoryProvider.overrideWithValue(_FakeOrderRepository()),
          ],
          child: MaterialApp(
            theme: AppThemes.dark,
            home: const CustomerFacingPage(),
          ),
        ),
      );
      await tester.pump();

      final assinatura =
          find.text('Solução Sistemas - A sua cozinha ainda mais eficiente');
      Color corDaAssinatura() => tester.widget<Text>(assinatura).style!.color!;

      // Tema escuro (fundo #161821): assinatura clara.
      expect(corDaAssinatura(), const Color(0xFFFFFFFF));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(CustomerFacingPage)),
        listen: false,
      );

      // Fundo branco escolhido pelo estabelecimento: ela inverte sozinha.
      await container.read(customerFacingThemeConfigProvider.notifier).setColor(
          CustomerFacingColorSlot.background, const Color(0xFFFFFFFF));
      await tester.pump();
      expect(corDaAssinatura(), const Color(0xFF000000));
    });
  });
}
