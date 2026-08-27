import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kds_constel/features/orders/domain/entities/order.dart';
import 'package:kds_constel/services/kds_printer_service.dart';

/// O ticket é uma sequência de bytes ESC/POS: comandos de controle
/// intercalados com o texto em si, sem modificação. Decodificar tudo como
/// UTF-8 tolerando bytes inválidos (os comandos de controle) preserva os
/// trechos de texto de verdade intactos — o bastante para conferir que o
/// conteúdo esperado está lá (e o que não devia, não está), sem precisar
/// interpretar o protocolo ESC/POS inteiro.
String _decode(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);

/// Confere se [needle] aparece em sequência dentro de [haystack] — usado
/// pra achar comandos ESC/POS crus (bytes de controle, não texto) no meio
/// do ticket, coisa que `_decode` não preserva de forma confiável.
bool _containsBytes(List<int> haystack, List<int> needle) {
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    if (haystack.sublist(i, i + needle.length).equals(needle)) return true;
  }
  return false;
}

extension on List<int> {
  bool equals(List<int> other) {
    if (length != other.length) return false;
    for (var i = 0; i < length; i++) {
      if (this[i] != other[i]) return false;
    }
    return true;
  }
}

void main() {
  // CapabilityProfile.load() carrega um asset (capabilities.json) via
  // rootBundle — precisa do binding do Flutter inicializado, mesmo este
  // teste não montando nenhum widget.
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = KdsPrinterService();

  final order = Order(
    id: 'order-1',
    number: 10014,
    items: [
      OrderItem(
        id: 'item-1',
        name: 'Burger Texas Triplo',
        quantity: 1,
        status: OrderStatus.pronto,
      ),
      OrderItem(
        id: 'item-2',
        name: 'São Geraldo',
        quantity: 1,
        status: OrderStatus.pronto,
      ),
    ],
    timestamp: DateTime(2026, 8, 27, 19, 52),
    roundCode: 'r1',
    pdvSenha: '0014',
  );

  test(
      'traz cabeçalho, pedido/senha, hora, itens e rodapé — sem menção a '
      'reimpressão', () async {
    final bytes = await service.buildOrderTicket(order, PaperSize.mm80);
    final text = _decode(bytes);

    expect(text, contains('PEP CONSTEL'));
    expect(text, contains('PEDIDO: #10014'));
    expect(text, contains('SENHA: 0014'));
    expect(text, contains('HORA: 19:52'));
    expect(text, contains('QTD'));
    expect(text, contains('ITEM'));
    expect(text, contains('1x'));
    expect(text, contains('Burger Texas Triplo'));
    // Só a parte sem acento: a impressora usa a página de código dela (não
    // UTF-8) pros caracteres acentuados, então o "ã" sai como outro byte —
    // correto pra impressora de verdade, mas o decode ingênuo deste teste
    // (só pra conferir que o texto está no lugar certo) não reproduz esse
    // byte de volta pro caractere original.
    expect(text, contains('Geraldo'));
    expect(text, contains('solucaosistemas.net'));

    // O botão que imprime isso não se chama mais "Reimprimir" — o ticket
    // também não deve carregar mais essa marca.
    expect(text, isNot(contains('REIMPRESSÃO')));
    expect(text, isNot(contains('Reimpresso')));
  });

  test(
      'mesa/cartão (sem senha do PDV) mostra o localizador no lugar da '
      'senha', () async {
    final mesaOrder = Order(
      id: 'order-2',
      number: 20,
      items: [
        OrderItem(
            id: 'item-3', name: 'Suco', quantity: 2, status: OrderStatus.pronto)
      ],
      timestamp: DateTime(2026, 8, 27, 12, 0),
      roundCode: 'r2',
      modalityName: 'Mesa',
      locatorLabel: '04',
    );

    final bytes = await service.buildOrderTicket(mesaOrder, PaperSize.mm80);
    final text = _decode(bytes);

    expect(text, contains('PEDIDO: #20'));
    expect(text, contains('SENHA: Mesa 04'));
    expect(text, contains('2x'));
  });

  test('observação do item e observação geral do pedido continuam saindo',
      () async {
    final orderWithObservations = Order(
      id: 'order-3',
      number: 5,
      items: [
        OrderItem(
          id: 'item-4',
          name: 'X-Burguer',
          quantity: 1,
          status: OrderStatus.pronto,
          observation: 'sem cebola',
        ),
      ],
      timestamp: DateTime(2026, 8, 27, 12, 0),
      roundCode: 'r3',
      pdvSenha: '0005',
      observations: 'Cliente vai retirar às 13h',
    );

    final bytes =
        await service.buildOrderTicket(orderWithObservations, PaperSize.mm80);
    final text = _decode(bytes);

    expect(text, contains('sem cebola'));
    // "OBSERVA..." e não a palavra acentuada inteira, pelo mesmo motivo do
    // teste anterior (página de código da impressora, não UTF-8).
    expect(text, contains('OBSERVA'));
    expect(text, contains('GERAL'));
    expect(text, contains('Cliente vai retirar'));
  });

  test(
      'funciona igual numa bobina de 58mm (colunas proporcionais, não '
      'fixas em 80mm)', () async {
    final bytes = await service.buildOrderTicket(order, PaperSize.mm58);
    final text = _decode(bytes);

    expect(text, contains('PEDIDO: #10014'));
    expect(text, contains('SENHA: 0014'));
    expect(text, contains('Burger Texas Triplo'));
  });

  test(
      'nome de item com aspas curvas/travessão (comum em texto colado no '
      'PDV) não derruba a impressão', () async {
    final orderWithSmartPunctuation = Order(
      id: 'order-4',
      number: 7,
      items: [
        OrderItem(
          id: 'item-5',
          // aspas curvas + travessão + reticências — fora da faixa Latin-1
          // que o ESC/POS usa; antes do saneamento, isso lançava uma
          // exceção no meio da geração do ticket e nada era impresso.
          name: '“X-Bacon” especial — sem cebola…',
          quantity: 1,
          status: OrderStatus.pronto,
        ),
      ],
      timestamp: DateTime(2026, 8, 27, 12, 0),
      roundCode: 'r4',
      pdvSenha: '0007',
    );

    final bytes = await service.buildOrderTicket(
        orderWithSmartPunctuation, PaperSize.mm80);
    final text = _decode(bytes);

    expect(text, contains('X-Bacon'));
    expect(text, contains('especial'));
    expect(text, contains('sem cebola'));
  });

  test(
      'fixa a página de código CP1252 — sem isso, os acentos dependem do '
      'padrão de fábrica de cada marca de impressora (varia entre Epson, '
      'Elgin, GoldenTec, Daruma...)', () async {
    final bytes = await service.buildOrderTicket(order, PaperSize.mm80);

    // ESC t 16 — "ESC t" seleciona a página de código, 16 é o id de CP1252
    // nesse profile (capabilities.json). CP1252 é compatível byte-a-byte
    // com o Latin-1 que o Generator já usa pra codificar o texto, então
    // travar nela funciona em qualquer impressora ESC/POS sem depender do
    // que cada marca configura de fábrica.
    expect(_containsBytes(bytes, [0x1B, 0x74, 16]), isTrue);
  });

  test(
      'corta o papel com o comando legado ESC i, não GS V — a DR700 (e '
      'outras não-fiscais brasileiras) não reconhece GS V e nunca chega a '
      'descarregar o buffer de texto pro cabeçote', () async {
    final bytes = await service.buildOrderTicket(order, PaperSize.mm80);

    expect(_containsBytes(bytes, [0x1B, 0x69]), isTrue);
    expect(_containsBytes(bytes, [0x1D, 0x56]), isFalse);
  });
}
