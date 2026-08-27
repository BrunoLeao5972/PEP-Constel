import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kds_constel/core/config/alert_appearance_config.dart';
import 'package:kds_constel/core/config/alert_appearance_config_provider.dart';
import 'package:kds_constel/core/theme/app_colors.dart';
import 'package:kds_constel/core/theme/app_themes.dart';
import 'package:kds_constel/core/widgets/order_urgency_shell.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AlertAppearanceConfig', () {
    test('padrão de fábrica reproduz o comportamento antigo (tudo em 1.0)', () {
      const config = AlertAppearanceConfig();
      expect(config.enabled, isTrue);
      expect(config.animationEnabled, isTrue);
      expect(config.colorIntensity, 1.0);
      expect(config.speedFactor, 1.0);
    });

    test('copyWith troca só o campo pedido', () {
      const config = AlertAppearanceConfig();
      final next = config.copyWith(enabled: false);
      expect(next.enabled, isFalse);
      expect(next.animationEnabled, isTrue);
      expect(next.colorIntensity, 1.0);
    });
  });

  group('persistência', () {
    test('intensidade e velocidade sobrevivem ao fechar e abrir o app',
        () async {
      final first = ProviderContainer();
      addTearDown(first.dispose);
      await first
          .read(alertAppearanceConfigProvider.notifier)
          .setEnabled(false);
      await first
          .read(alertAppearanceConfigProvider.notifier)
          .setAnimationEnabled(false);
      await first
          .read(alertAppearanceConfigProvider.notifier)
          .setColorIntensity(0.6);
      await first
          .read(alertAppearanceConfigProvider.notifier)
          .setSpeedFactor(2.0);

      // Novo container == novo processo lendo o SharedPreferences do zero.
      final reopened = ProviderContainer();
      addTearDown(reopened.dispose);
      await reopened.read(alertAppearanceConfigProvider.notifier).ready;

      final state = reopened.read(alertAppearanceConfigProvider);
      expect(state.enabled, isFalse);
      expect(state.animationEnabled, isFalse);
      expect(state.colorIntensity, 0.6);
      expect(state.speedFactor, 2.0);
    });

    test('intensidade e velocidade são limitadas à faixa segura', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(alertAppearanceConfigProvider.notifier);

      await notifier.setColorIntensity(99);
      expect(container.read(alertAppearanceConfigProvider).colorIntensity,
          AlertAppearanceConfig.maxColorIntensity);

      await notifier.setColorIntensity(-5);
      expect(container.read(alertAppearanceConfigProvider).colorIntensity,
          AlertAppearanceConfig.minColorIntensity);

      await notifier.setSpeedFactor(99);
      expect(container.read(alertAppearanceConfigProvider).speedFactor,
          AlertAppearanceConfig.maxSpeedFactor);

      await notifier.setSpeedFactor(-5);
      expect(container.read(alertAppearanceConfigProvider).speedFactor,
          AlertAppearanceConfig.minSpeedFactor);
    });
  });

  group('OrderUrgencyShell', () {
    Future<void> pumpShell(
      WidgetTester tester, {
      required OrderUrgency urgency,
      required List<Override> overrides,
    }) {
      return tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            theme: AppThemes.dark,
            home: Scaffold(
              body: OrderUrgencyShell(
                urgency: urgency,
                child: const SizedBox(width: 80, height: 40),
              ),
            ),
          ),
        ),
      );
    }

    Finder shellContainer() => find.descendant(
          of: find.byType(OrderUrgencyShell),
          matching: find.byType(Container),
        );

    Finder shellAnimatedBuilder() => find.descendant(
          of: find.byType(OrderUrgencyShell),
          matching: find.byType(AnimatedBuilder),
        );

    BoxDecoration decorationOf(WidgetTester tester) =>
        tester.widget<Container>(shellContainer()).decoration as BoxDecoration;

    testWidgets('urgência normal nunca destaca, mesmo com alertas ligados',
        (tester) async {
      await pumpShell(
        tester,
        urgency: OrderUrgency.normal,
        overrides: [], // config padrão: enabled = true
      );
      await tester.pump();

      final border = decorationOf(tester).border as Border;
      expect(border.top.width, 1);
      expect(shellAnimatedBuilder(), findsNothing);
    });

    testWidgets('alerta desligado: card fica neutro mesmo em pedido crítico',
        (tester) async {
      await pumpShell(
        tester,
        urgency: OrderUrgency.critical,
        overrides: [
          alertAppearanceConfigProvider.overrideWith(
            (ref) => AlertAppearanceConfigNotifier()
              ..state = const AlertAppearanceConfig(enabled: false),
          ),
        ],
      );
      await tester.pump();

      final decoration = decorationOf(tester);
      expect(decoration.border, isA<Border>());
      final border = decoration.border as Border;
      // Borda "neutra" (1px, cor de borda do tema) — não a borda de 2px
      // vermelha que o crítico usaria com alertas ligados.
      expect(border.top.width, 1);
      expect(shellAnimatedBuilder(), findsNothing);
    });

    testWidgets(
        'animação desligada: destaque fica fixo no pico, sem AnimatedBuilder',
        (tester) async {
      await pumpShell(
        tester,
        urgency: OrderUrgency.alert,
        overrides: [
          alertAppearanceConfigProvider.overrideWith(
            (ref) => AlertAppearanceConfigNotifier()
              ..state = const AlertAppearanceConfig(animationEnabled: false),
          ),
        ],
      );
      await tester.pump();

      expect(shellAnimatedBuilder(), findsNothing);
      final decoration = decorationOf(tester);
      final border = decoration.border as Border;
      expect(border.top.width, 2); // destaque de urgência ligado, só sem piscar
    });

    /// Reproduz, aqui no teste, a MESMA conta que `OrderUrgencyShell` faz
    /// pra chegar na cor de pico (fundo do tema escuro mesclado com o
    /// amarelo do alerta) — assim a asserção confere o valor exato, não só
    /// "ficou mais claro ou mais escuro".
    Color expectedPeakColor(double colorIntensity) {
      const baseMaxBlend = 0.32; // urgência "alerta"
      final maxBlend = (baseMaxBlend * colorIntensity).clamp(0.0, 1.0);
      return Color.lerp(
          AppColors.dark.backgroundColor, AppStatusColors.warning, maxBlend)!;
    }

    // Um `testWidgets` por intensidade: cada um pumpa a própria árvore uma
    // única vez. Duas chamadas a `pumpWidget` NO MESMO teste, mesmo com
    // `ProviderScope`s e overrides diferentes, deixaram o Flutter reconciliar
    // o card com o container antigo em vez de recriar do zero — a segunda
    // cor não aparecia. Testes separados evitam essa ambiguidade de todo.
    testWidgets('intensidade baixa produz a mescla de cor esperada',
        (tester) async {
      await pumpShell(
        tester,
        urgency: OrderUrgency.alert,
        overrides: [
          alertAppearanceConfigProvider.overrideWith(
            (ref) => AlertAppearanceConfigNotifier()
              ..state = const AlertAppearanceConfig(
                  animationEnabled: false, colorIntensity: 0.3),
          ),
        ],
      );
      await tester.pump();

      expect(decorationOf(tester).color, expectedPeakColor(0.3));
    });

    testWidgets('intensidade alta produz a mescla de cor esperada',
        (tester) async {
      await pumpShell(
        tester,
        urgency: OrderUrgency.alert,
        overrides: [
          alertAppearanceConfigProvider.overrideWith(
            (ref) => AlertAppearanceConfigNotifier()
              ..state = const AlertAppearanceConfig(
                  animationEnabled: false, colorIntensity: 1.5),
          ),
        ],
      );
      await tester.pump();

      final peak = expectedPeakColor(1.5);
      expect(decorationOf(tester).color, peak);
      // E, por construção da fórmula, mais intensidade == mais próximo do
      // amarelo puro == luminância maior que a intensidade baixa.
      expect(peak.computeLuminance(),
          greaterThan(expectedPeakColor(0.3).computeLuminance()));
    });

    testWidgets('velocidade maior encurta a duração do pisca', (tester) async {
      await pumpShell(
        tester,
        urgency: OrderUrgency.alert,
        overrides: [
          alertAppearanceConfigProvider.overrideWith(
            (ref) => AlertAppearanceConfigNotifier()
              ..state = const AlertAppearanceConfig(speedFactor: 2.0),
          ),
        ],
      );
      await tester.pump();

      final controller = tester
          .widget<AnimatedBuilder>(shellAnimatedBuilder())
          .animation as AnimationController;
      // Base do alerta é 1000ms; com speedFactor 2.0 deve virar 500ms.
      expect(controller.duration, const Duration(milliseconds: 500));
    });
  });
}
