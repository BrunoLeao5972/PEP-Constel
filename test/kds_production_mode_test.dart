import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kds_constel/core/config/kds_production_mode_config.dart';
import 'package:kds_constel/core/config/kds_production_mode_config_provider.dart';
import 'package:kds_constel/core/theme/app_themes.dart';
import 'package:kds_constel/core/widgets/order_urgency_shell.dart'
    show kOrderCardRadius;
import 'package:kds_constel/features/auth/domain/entities/kds_user.dart';
import 'package:kds_constel/features/auth/presentation/providers/auth_provider.dart';
import 'package:kds_constel/features/orders/domain/entities/order.dart';
import 'package:kds_constel/features/orders/domain/repositories/order_repository.dart';
import 'package:kds_constel/features/orders/presentation/pages/kds_page.dart';
import 'package:kds_constel/features/orders/presentation/providers/order_provider.dart';

/// Um pedido com dois itens, ambos recebidos ("novo") — o bastante pra
/// exercitar o card inteiro (Iniciar/Finalizar/Entregar) e os dois modos de
/// produção.
class _FakeOrderRepository implements OrderRepository {
  static final _orders = <Order>[
    Order(
      id: 'order-1',
      number: 7,
      items: [
        OrderItem(
            id: 'item-1',
            name: 'X-Burguer',
            quantity: 1,
            status: OrderStatus.novo),
        OrderItem(
            id: 'item-2',
            name: 'Batata',
            quantity: 1,
            status: OrderStatus.novo),
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

/// Dois pedidos independentes, cada um com um item "novo" — pra provar que
/// a escolha de modo feita numa comanda não vaza pra outra.
class _TwoOrdersRepository implements OrderRepository {
  static final _orders = <Order>[
    Order(
      id: 'order-a',
      number: 1,
      items: [
        OrderItem(
            id: 'a-1',
            name: 'X-Burguer',
            quantity: 1,
            status: OrderStatus.novo),
      ],
      timestamp: DateTime(2026, 8, 26, 12),
      roundCode: 'ra',
      modalityName: 'Mesa',
      locatorLabel: '01',
    ),
    Order(
      id: 'order-b',
      number: 2,
      items: [
        OrderItem(
            id: 'b-1', name: 'Suco', quantity: 1, status: OrderStatus.novo),
      ],
      timestamp: DateTime(2026, 8, 26, 12, 5),
      roundCode: 'rb',
      modalityName: 'Mesa',
      locatorLabel: '02',
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

class _FakeAuthController extends AuthController {
  _FakeAuthController(Ref ref, KdsUser user) : super(ref) {
    state = AsyncValue.data(user);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('KdsProductionModeConfig', () {
    test('padrão de fábrica é item a item (comportamento histórico)', () {
      const config = KdsProductionModeConfig();
      expect(config.mode, KdsProductionMode.perItem);
    });

    test('copyWith troca só o modo', () {
      const config = KdsProductionModeConfig();
      final next = config.copyWith(mode: KdsProductionMode.wholeOrder);
      expect(next.mode, KdsProductionMode.wholeOrder);
    });
  });

  group('persistência', () {
    test('o modo escolhido sobrevive ao fechar e abrir o app', () async {
      final first = ProviderContainer();
      addTearDown(first.dispose);
      await first.read(kdsProductionModeConfigProvider.notifier).ready;
      await first
          .read(kdsProductionModeConfigProvider.notifier)
          .setMode(KdsProductionMode.wholeOrder);

      final reopened = ProviderContainer();
      addTearDown(reopened.dispose);
      await reopened.read(kdsProductionModeConfigProvider.notifier).ready;

      expect(reopened.read(kdsProductionModeConfigProvider).mode,
          KdsProductionMode.wholeOrder);
    });

    test('o modo misto também sobrevive ao fechar e abrir o app', () async {
      // A leitura salva deixou de ser um ternário binário (perItem/
      // wholeOrder) e virou uma busca no enum inteiro — este teste cobre
      // especificamente o terceiro valor, que o ternário antigo não sabia
      // reconhecer.
      final first = ProviderContainer();
      addTearDown(first.dispose);
      await first.read(kdsProductionModeConfigProvider.notifier).ready;
      await first
          .read(kdsProductionModeConfigProvider.notifier)
          .setMode(KdsProductionMode.mixed);

      final reopened = ProviderContainer();
      addTearDown(reopened.dispose);
      await reopened.read(kdsProductionModeConfigProvider.notifier).ready;

      expect(reopened.read(kdsProductionModeConfigProvider).mode,
          KdsProductionMode.mixed);
    });
  });

  group('Cozinha — item a item (padrão)', () {
    Future<ProviderContainer> pumpKds(WidgetTester tester,
        {bool isAdmin = false}) async {
      // Largura folgada: abaixo de 700px a própria Cozinha já estoura a
      // barra de busca/filtros (bug pré-existente, alheio a este recurso) —
      // mesma largura que o widget_test.dart já usa pra montar o app inteiro.
      tester.view.physicalSize = const Size(2400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: [
        orderRepositoryProvider.overrideWithValue(_FakeOrderRepository()),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            KdsUser(
                id: '1', credencial: 'op', nome: 'Op', administrador: isAdmin),
          ),
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppThemes.dark, home: const KDSPage()),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('cada item tem seu próprio botão Iniciar', (tester) async {
      await pumpKds(tester);

      expect(find.text('Iniciar'), findsNWidgets(2));
      // Nenhuma ação de comanda inteira nesse modo.
      expect(find.textContaining('PREPARO'), findsNothing);
    });

    testWidgets(
        'iniciar um item não mexe no outro, e só quando TODOS chegam a '
        'pronto aparece ENTREGAR', (tester) async {
      final container = await pumpKds(tester);

      await tester.tap(find.text('Iniciar').first);
      await tester.pump();

      // Um item avançou, o outro continua em "Iniciar".
      expect(find.text('Iniciar'), findsOneWidget);
      expect(find.text('Finalizar'), findsOneWidget);
      expect(find.text('ENTREGAR'), findsNothing);

      await tester.tap(find.text('Iniciar').first);
      await tester.tap(find.text('Finalizar').first);
      await tester.pump();
      await tester.tap(find.text('Finalizar').first);
      await tester.pump();

      // Os dois chegaram a "pronto": agora sim a barra de entregar aparece.
      expect(find.text('ENTREGAR'), findsOneWidget);

      await tester.tap(find.text('ENTREGAR'));
      await tester.pump();

      final order = container
          .read(displayOrdersProvider)
          .value!
          .firstWhere((o) => o.id == 'order-1');
      expect(order.status, OrderStatus.entregue);
    });
  });

  group('Cozinha — comanda inteira', () {
    Future<ProviderContainer> pumpKds(WidgetTester tester,
        {bool isAdmin = false}) async {
      tester.view.physicalSize = const Size(2400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: [
        orderRepositoryProvider.overrideWithValue(_FakeOrderRepository()),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            KdsUser(
                id: '1', credencial: 'op', nome: 'Op', administrador: isAdmin),
          ),
        ),
        kdsProductionModeConfigProvider.overrideWith(
          (ref) => KdsProductionModeConfigNotifier()
            ..state = const KdsProductionModeConfig(
                mode: KdsProductionMode.wholeOrder),
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppThemes.dark, home: const KDSPage()),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets('itens não têm botão — só um indicador, sem toque',
        (tester) async {
      await pumpKds(tester);

      expect(find.text('Iniciar'), findsNothing);
      expect(find.text('Finalizar'), findsNothing);
      // Os dois itens "novo" mostram o mesmo glifo neutro.
      expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
    });

    testWidgets(
        'INICIAR PREPARO avança os dois itens juntos, e a barra vira '
        'FINALIZAR PREPARO', (tester) async {
      final container = await pumpKds(tester);

      expect(find.text('INICIAR PREPARO'), findsOneWidget);
      await tester.tap(find.text('INICIAR PREPARO'));
      await tester.pump();

      expect(find.text('FINALIZAR PREPARO'), findsOneWidget);
      expect(find.byIcon(Icons.local_fire_department), findsNWidgets(2));

      final order = container
          .read(displayOrdersProvider)
          .value!
          .firstWhere((o) => o.id == 'order-1');
      // Os DOIS itens avançaram numa tacada só — não só o primeiro.
      expect(
          order.items.every((i) => i.status == OrderStatus.emPreparo), isTrue);
    });

    testWidgets(
        'sequência completa até ENTREGAR, cada etapa avançando a comanda '
        'inteira', (tester) async {
      final container = await pumpKds(tester);

      await tester.tap(find.text('INICIAR PREPARO'));
      await tester.pump();
      await tester.tap(find.text('FINALIZAR PREPARO'));
      await tester.pump();

      expect(find.text('ENTREGAR'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(2));

      await tester.tap(find.text('ENTREGAR'));
      await tester.pump();

      final order = container
          .read(displayOrdersProvider)
          .value!
          .firstWhere((o) => o.id == 'order-1');
      expect(order.status, OrderStatus.entregue);
      // Terminal: nenhuma das três ações continua na tela.
      expect(find.text('INICIAR PREPARO'), findsNothing);
      expect(find.text('FINALIZAR PREPARO'), findsNothing);
      expect(find.text('ENTREGAR'), findsNothing);
    });

    testWidgets('administrador pode voltar a comanda inteira uma etapa',
        (tester) async {
      final container = await pumpKds(tester, isAdmin: true);

      await tester.tap(find.text('INICIAR PREPARO'));
      await tester.pump();
      expect(find.text('FINALIZAR PREPARO'), findsOneWidget);

      await tester.tap(find.byTooltip('Voltar etapa'));
      await tester.pump();

      expect(find.text('INICIAR PREPARO'), findsOneWidget);
      final order = container
          .read(displayOrdersProvider)
          .value!
          .firstWhere((o) => o.id == 'order-1');
      expect(order.items.every((i) => i.status == OrderStatus.novo), isTrue);
    });

    testWidgets('sem ser administrador, não há botão de voltar etapa',
        (tester) async {
      await pumpKds(tester, isAdmin: false);

      await tester.tap(find.text('INICIAR PREPARO'));
      await tester.pump();

      expect(find.byTooltip('Voltar etapa'), findsNothing);
    });
  });

  group('Cozinha — modo misto', () {
    Future<ProviderContainer> pumpKds(WidgetTester tester,
        {bool isAdmin = false}) async {
      tester.view.physicalSize = const Size(2400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: [
        orderRepositoryProvider.overrideWithValue(_FakeOrderRepository()),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            KdsUser(
                id: '1', credencial: 'op', nome: 'Op', administrador: isAdmin),
          ),
        ),
        kdsProductionModeConfigProvider.overrideWith(
          (ref) => KdsProductionModeConfigNotifier()
            ..state =
                const KdsProductionModeConfig(mode: KdsProductionMode.mixed),
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppThemes.dark, home: const KDSPage()),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets(
        'cada item tem seu próprio botão, e a barra em massa também '
        'aparece quando os dois estão na mesma etapa', (tester) async {
      await pumpKds(tester);

      // As duas formas convivem desde o início — nenhuma escolha prévia.
      expect(find.text('Iniciar'), findsNWidgets(2));
      expect(find.text('INICIAR PREPARO'), findsOneWidget);
    });

    testWidgets(
        'iniciar um item sozinho esconde a barra em massa, mas o outro '
        'item continua avançável pelo próprio chip', (tester) async {
      final container = await pumpKds(tester);

      await tester.tap(find.text('Iniciar').first);
      await tester.pump();

      // Estado misturado (1 emPreparo + 1 novo): a barra em massa some,
      // mas o item que falta continua com seu próprio botão.
      expect(find.text('INICIAR PREPARO'), findsNothing);
      expect(find.text('FINALIZAR PREPARO'), findsNothing);
      expect(find.text('Iniciar'), findsOneWidget);
      expect(find.text('Finalizar'), findsOneWidget);

      // Avançando o item que faltava, os dois realinham em emPreparo — a
      // barra em massa reaparece, agora como "FINALIZAR PREPARO".
      await tester.tap(find.text('Iniciar').first);
      await tester.pump();

      expect(find.text('FINALIZAR PREPARO'), findsOneWidget);
      final order = container
          .read(displayOrdersProvider)
          .value!
          .firstWhere((o) => o.id == 'order-1');
      expect(
          order.items.every((i) => i.status == OrderStatus.emPreparo), isTrue);
    });

    testWidgets(
        'administrador reverte um item de pronto pra em preparo: a barra '
        'ENTREGAR some, mas os chips por item continuam funcionando',
        (tester) async {
      await pumpKds(tester, isAdmin: true);

      // Leva os dois itens até "pronto" pelos próprios chips (sem usar a
      // barra em massa, pra provar que ela não é o único caminho). Um
      // `pump()` entre cada toque é obrigatório aqui: sem ele, o finder
      // ainda vê a árvore antiga e "Iniciar".first acerta o MESMO item das
      // duas vezes, em vez de um item de cada vez.
      await tester.tap(find.text('Iniciar').first);
      await tester.pump();
      await tester.tap(find.text('Iniciar').first);
      await tester.pump();
      await tester.tap(find.text('Finalizar').first);
      await tester.pump();
      await tester.tap(find.text('Finalizar').first);
      await tester.pump();

      expect(find.text('ENTREGAR'), findsOneWidget);

      // Admin reverte só UM item de volta pra "em preparo" — o outro
      // continua "pronto".
      await tester.tap(find.byTooltip('Voltar etapa').first);
      await tester.pump();

      // Estado misturado de novo (1 emPreparo + 1 pronto): a barra em
      // massa some, e o item revertido volta a mostrar "Finalizar".
      expect(find.text('ENTREGAR'), findsNothing);
      expect(find.text('FINALIZAR PREPARO'), findsNothing);
      expect(find.text('Finalizar'), findsOneWidget);
    });

    testWidgets('sem ser administrador, não há botão de voltar etapa',
        (tester) async {
      await pumpKds(tester, isAdmin: false);

      await tester.tap(find.text('Iniciar').first);
      await tester.pump();
      await tester.tap(find.text('Iniciar').first);
      await tester.pump();

      expect(find.byTooltip('Voltar etapa'), findsNothing);
    });
  });

  // O alternador por comanda (um ícone por card, ciclando entre os modos)
  // existiu por um tempo e foi removido: na prática incomodava mais do que
  // ajudava. O modo agora é só o que está configurado globalmente — sem
  // exceção por comanda —, e este grupo confere isso com duas comandas
  // simultâneas em tela.
  group('Cozinha — modo é sempre o configurado globalmente', () {
    Future<ProviderContainer> pumpTwoOrders(
      WidgetTester tester, {
      KdsProductionMode mode = KdsProductionMode.perItem,
    }) async {
      tester.view.physicalSize = const Size(2400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: [
        orderRepositoryProvider.overrideWithValue(_TwoOrdersRepository()),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            KdsUser(
                id: '1', credencial: 'op', nome: 'Op', administrador: false),
          ),
        ),
        kdsProductionModeConfigProvider.overrideWith(
          (ref) => KdsProductionModeConfigNotifier()
            ..state = KdsProductionModeConfig(mode: mode),
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppThemes.dark, home: const KDSPage()),
        ),
      );
      await tester.pump();
      return container;
    }

    testWidgets(
        'duas comandas simultâneas seguem o mesmo modo global — item a '
        'item por padrão', (tester) async {
      await pumpTwoOrders(tester);

      expect(find.text('Iniciar'), findsNWidgets(2));
      expect(find.textContaining('PREPARO'), findsNothing);
    });

    testWidgets(
        'mudar o modo global pra comanda inteira afeta as duas comandas '
        'juntas — não há mais como uma ficar diferente da outra',
        (tester) async {
      await pumpTwoOrders(tester, mode: KdsProductionMode.wholeOrder);

      expect(find.text('Iniciar'), findsNothing);
      expect(find.text('INICIAR PREPARO'), findsNWidgets(2));
    });
  });

  group('cantos arredondados do rodapé do card', () {
    Future<ProviderContainer> pumpWholeOrder(WidgetTester tester,
        {required bool isAdmin}) async {
      tester.view.physicalSize = const Size(2400, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: [
        orderRepositoryProvider.overrideWithValue(_FakeOrderRepository()),
        authControllerProvider.overrideWith(
          (ref) => _FakeAuthController(
            ref,
            KdsUser(
                id: '1', credencial: 'op', nome: 'Op', administrador: isAdmin),
          ),
        ),
        kdsProductionModeConfigProvider.overrideWith(
          (ref) => KdsProductionModeConfigNotifier()
            ..state = const KdsProductionModeConfig(
                mode: KdsProductionMode.wholeOrder),
        ),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppThemes.dark, home: const KDSPage()),
        ),
      );
      await tester.pump();
      return container;
    }

    /// A barra colorida ("INICIAR PREPARO"/"FINALIZAR PREPARO"/"ENTREGAR")
    /// é um InkWell com um Container dentro — o Container carrega a
    /// BoxDecoration com o borderRadius que queremos conferir.
    BorderRadius radiusOfBar(WidgetTester tester, String label) {
      final container = tester.widget<Container>(
        find.descendant(
          of: find.ancestor(
              of: find.text(label), matching: find.byType(InkWell)),
          matching: find.byType(Container),
        ),
      );
      return (container.decoration as BoxDecoration).borderRadius
          as BorderRadius;
    }

    testWidgets(
        'sozinha (sem botão de voltar), a barra arredonda os dois cantos '
        'de baixo', (tester) async {
      await pumpWholeOrder(tester, isAdmin: false);

      final radius = radiusOfBar(tester, 'INICIAR PREPARO');
      expect(radius.bottomLeft, const Radius.circular(kOrderCardRadius));
      expect(radius.bottomRight, const Radius.circular(kOrderCardRadius));
      expect(radius.topLeft, Radius.zero);
      expect(radius.topRight, Radius.zero);
    });

    testWidgets(
        'com o botão de voltar ao lado, cada um arredonda só o canto que '
        'toca o card — a barra à direita, o botão à esquerda', (tester) async {
      await pumpWholeOrder(tester, isAdmin: true);
      await tester.tap(find.text('INICIAR PREPARO'));
      await tester.pump();

      // A barra ("FINALIZAR PREPARO") só arredonda o canto direito — o
      // esquerdo agora encosta no botão de voltar, não no card.
      final barRadius = radiusOfBar(tester, 'FINALIZAR PREPARO');
      expect(barRadius.bottomRight, const Radius.circular(kOrderCardRadius));
      expect(barRadius.bottomLeft, Radius.zero);

      // O botão de voltar só arredonda o canto esquerdo (o que ele ocupa
      // no card) — o direito encosta na barra.
      final revertButton = tester.widget<Container>(
        find.descendant(
          of: find.byTooltip('Voltar etapa'),
          matching: find.byType(Container),
        ),
      );
      final revertRadius = (revertButton.decoration as BoxDecoration)
          .borderRadius as BorderRadius;
      expect(revertRadius.bottomLeft, const Radius.circular(kOrderCardRadius));
      expect(revertRadius.bottomRight, Radius.zero);
      expect(revertRadius.topLeft, Radius.zero);
    });
  });
}
