/// Fonte do número/rótulo exibido pelo chamador de pedidos (tela do cliente).
enum CallerNumberingSource {
  /// Usa os dados que já vêm do PDV: modalidade + localizador
  /// (ex: "Cartão 501", "Mesa 01").
  pdv,

  /// O KDS gera sua própria senha sequencial, independente do banco.
  kds,
}

class OrderCallerConfig {
  final CallerNumberingSource source;

  /// Só relevante quando source == kds: zera a sequência a cada novo dia.
  final bool resetDaily;

  /// Só relevante quando source == kds: número a partir do qual a sequência
  /// começa a contar (na primeira vez e a cada reinício diário).
  final int startNumber;

  const OrderCallerConfig({
    this.source = CallerNumberingSource.pdv,
    this.resetDaily = true,
    this.startNumber = 1,
  });

  OrderCallerConfig copyWith({
    CallerNumberingSource? source,
    bool? resetDaily,
    int? startNumber,
  }) {
    return OrderCallerConfig(
      source: source ?? this.source,
      resetDaily: resetDaily ?? this.resetDaily,
      startNumber: startNumber ?? this.startNumber,
    );
  }
}
