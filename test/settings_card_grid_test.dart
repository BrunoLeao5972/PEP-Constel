import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kds_constel/features/settings/presentation/widgets/settings_section_card.dart';

/// Cobre o motivo direto do ajuste: cards com conteúdo de tamanhos bem
/// diferentes (aqui, dois `SizedBox` com alturas diferentes no lugar de
/// cards de verdade — o que importa é só a altura) precisam sair
/// renderizados com a MESMA altura quando dividem uma linha da grade.
void main() {
  Future<Size> sizeOf(WidgetTester tester, Key key) async {
    final box = tester.renderObject<RenderBox>(find.byKey(key));
    return box.size;
  }

  testWidgets('dois cards na mesma linha saem com a mesma altura (desktop)',
      (tester) async {
    const shortKey = Key('short');
    const tallKey = Key('tall');

    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsCardGrid(
            children: [
              Container(key: shortKey, color: Colors.red, height: 40),
              Container(key: tallKey, color: Colors.blue, height: 220),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final shortHeight = (await sizeOf(tester, shortKey)).height;
    final tallHeight = (await sizeOf(tester, tallKey)).height;

    // O card baixo foi esticado até a altura do alto — não o contrário
    // (o alto nunca pode ser espremido, senão corta conteúdo).
    expect(shortHeight, tallHeight);
    expect(tallHeight, 220);
  });

  testWidgets('card sozinho numa linha ímpar ocupa a linha inteira',
      (tester) async {
    const aKey = Key('a');
    const bKey = Key('b');
    const soloKey = Key('solo');

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsCardGrid(
            children: [
              Container(key: aKey, color: Colors.red, height: 60),
              Container(key: bKey, color: Colors.blue, height: 60),
              Container(key: soloKey, color: Colors.green, height: 60),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final gridWidth = tester.getSize(find.byType(SettingsCardGrid)).width;
    final columnWidth = (await sizeOf(tester, aKey)).width;
    final soloWidth = (await sizeOf(tester, soloKey)).width;

    // O terceiro card (sobrando, sem par) preenche a largura da grade
    // inteira — não fica preso numa única coluna com um vão vazio do lado.
    expect(soloWidth, gridWidth);
    expect(soloWidth, greaterThan(columnWidth * 1.5));
  });

  testWidgets('em telas estreitas vira uma coluna única (sem pareamento)',
      (tester) async {
    const shortKey = Key('short-narrow');
    const tallKey = Key('tall-narrow');

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsCardGrid(
            children: [
              Container(key: shortKey, color: Colors.red, height: 40),
              Container(key: tallKey, color: Colors.blue, height: 220),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // Empilhados, cada card mantém a própria altura natural — só o
    // pareamento lado a lado (desktop) que precisa igualar.
    expect((await sizeOf(tester, shortKey)).height, 40);
    expect((await sizeOf(tester, tallKey)).height, 220);
  });
}
