/// Como a Cozinha avança a produção de uma comanda pelas etapas (recebido →
/// em preparo → pronto → entregue): produto a produto, ou a comanda inteira
/// de uma vez em cada etapa.
enum KdsProductionMode {
  /// Comportamento histórico do KDS: cada produto do pedido tem seus
  /// próprios botões e avança sozinho pelas etapas, independente dos
  /// outros itens da mesma comanda. Melhor quando itens da mesma comanda
  /// costumam ficar prontos em momentos bem diferentes (vários postos de
  /// trabalho na cozinha).
  perItem,

  /// Um botão só avança TODOS os itens da comanda de uma vez, em cada
  /// etapa — "Iniciar Comanda", "Finalizar Comanda" e "Entregar" (esta
  /// última já era assim antes, independente do modo). Melhor quando a
  /// cozinha trata o pedido inteiro como uma unidade só.
  wholeOrder,

  /// As duas formas convivem: cada item sempre com seu próprio botão (igual
  /// a [perItem]), e a comanda TAMBÉM ganha um botão de avançar tudo de uma
  /// vez — mas só enquanto todos os itens estiverem exatamente na mesma
  /// etapa. Num estado misturado (ex: um item já iniciado sozinho, os
  /// outros ainda aguardando), o botão de avançar tudo some, e sobram só os
  /// botões de cada item — sem forçar uma escolha de "tudo ou nada".
  mixed,
}

class KdsProductionModeConfig {
  final KdsProductionMode mode;

  const KdsProductionModeConfig({this.mode = KdsProductionMode.perItem});

  KdsProductionModeConfig copyWith({KdsProductionMode? mode}) {
    return KdsProductionModeConfig(mode: mode ?? this.mode);
  }
}
