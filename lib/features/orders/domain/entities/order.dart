enum OrderStatus { novo, emPreparo, pronto, entregue }

class OrderItem {
  final String id;
  final String name;
  final int quantity;
  final OrderStatus status;

  /// URL da foto do produto (recurso.item.imagem). Null quando o produto não
  /// tem imagem cadastrada no catálogo.
  final String? imageUrl;

  /// Observação lançada nesse item especificamente (ocupacaoItens.observacoes),
  /// ex: "sem cebola" — diferente da observação do pedido como um todo.
  final String? observation;

  OrderItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.status,
    this.imageUrl,
    this.observation,
  });
}

class Order {
  final String id;
  final int number;
  final List<OrderItem> items;
  final String? observations;
  final DateTime timestamp;

  /// Código da leva/comanda (ocupacaoItens.comandaCodigo) que originou esse
  /// card, ex: "0010013". Uma mesa pode receber vários lançamentos ao longo
  /// do atendimento (bebidas, depois entrada, depois prato principal) — cada
  /// lançamento vem com seu próprio comandaCodigo, e cada um vira um Order
  /// separado (ver MongoOrderRepository) pra não misturar uma leva nova com
  /// itens de uma leva anterior já entregue da mesma mesa.
  final String roundCode;

  /// Nome da modalidade de atendimento (ex: "Balcão", "Mesa", "Cartão"),
  /// vindo de venda.ocupacao.modalidade.nome.
  final String modalityName;

  /// Identificador físico dentro da modalidade (ex: "04" para Mesa 04, "501"
  /// para Cartão 501), vindo de venda.ocupacao.localizador.codigo. Null
  /// quando não há localizador (ex: Balcão).
  final String? locatorLabel;

  /// Senha de retirada impressa pelo PDV (venda.ocupacao.senha). Só existe
  /// para Balcão — Mesa e Cartão já são identificados pelo localizador.
  final String? pdvSenha;

  /// Última atualização (venda.ocupacao.edicao) — atualizada pelo próprio
  /// app a cada mudança de status. Usada como aproximação de "quando ficou
  /// pronto/foi entregue" para calcular tempo de preparo no Admin.
  final DateTime? updatedAt;

  Order({
    required this.id,
    required this.number,
    required this.items,
    this.observations,
    required this.timestamp,
    required this.roundCode,
    this.modalityName = 'Balcão',
    this.locatorLabel,
    this.pdvSenha,
    this.updatedAt,
  });

  /// Status agregado do pedido, derivado do status de cada item — a cozinha
  /// agora controla o preparo item a item, então não existe mais um único
  /// campo de status do pedido vindo do banco. "Pronto"/"entregue" exigem
  /// que TODOS os itens tenham chegado lá; "em preparo" já vale assim que
  /// qualquer item começa a ser feito.
  OrderStatus get status {
    if (items.isEmpty) return OrderStatus.novo;
    if (items.every((i) => i.status == OrderStatus.entregue)) {
      return OrderStatus.entregue;
    }
    if (items.every((i) =>
        i.status == OrderStatus.pronto || i.status == OrderStatus.entregue)) {
      return OrderStatus.pronto;
    }
    if (items.any((i) => i.status != OrderStatus.novo)) {
      return OrderStatus.emPreparo;
    }
    return OrderStatus.novo;
  }

  /// Rótulo pronto para exibição, ex: "Mesa 04", "Cartão 501", "Senha 0006".
  /// Sem localizador (Balcão) usa a senha do PDV quando existir; senão cai
  /// para o nome da modalidade puro.
  String get modalityDisplay {
    if (locatorLabel != null) return '$modalityName $locatorLabel';
    if (pdvSenha != null) return 'Senha $pdvSenha';
    return modalityName;
  }

  /// Rótulo do Chamador de Pedidos quando a numeração é controlada pelo PDV
  /// (ver CallerNumberingSource.pdv) — igual a [modalityDisplay], mas sem o
  /// prefixo "Senha": no painel voltado pro cliente mostrar só o código
  /// (ex: "0013") já deixa claro que é a senha, sem repetir a palavra.
  String get pdvCallerLabel {
    if (locatorLabel != null) return '$modalityName $locatorLabel';
    if (pdvSenha != null) return pdvSenha!;
    return modalityName;
  }

  Order copyWith({
    String? id,
    int? number,
    List<OrderItem>? items,
    String? observations,
    DateTime? timestamp,
    String? roundCode,
    String? modalityName,
    String? locatorLabel,
    String? pdvSenha,
    DateTime? updatedAt,
  }) {
    return Order(
      id: id ?? this.id,
      number: number ?? this.number,
      items: items ?? this.items,
      observations: observations ?? this.observations,
      timestamp: timestamp ?? this.timestamp,
      roundCode: roundCode ?? this.roundCode,
      modalityName: modalityName ?? this.modalityName,
      locatorLabel: locatorLabel ?? this.locatorLabel,
      pdvSenha: pdvSenha ?? this.pdvSenha,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
