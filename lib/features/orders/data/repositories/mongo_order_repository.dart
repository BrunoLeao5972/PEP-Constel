import 'package:mongo_dart/mongo_dart.dart';
import '../../domain/entities/order.dart';
import '../../domain/repositories/order_repository.dart';

// Mapeamento estimado dos códigos de situação/producaoSituacao usados pelo
// sistema (venda.ocupacao / ocupacaoItens). Os únicos valores observados em
// dados reais até agora foram 20 e 30 — ajustar aqui assim que o time do
// backend confirmar a tabela oficial de códigos.
const Map<int, OrderStatus> _statusByCode = {
  10: OrderStatus.novo,
  20: OrderStatus.emPreparo,
  30: OrderStatus.pronto,
  40: OrderStatus.entregue,
};

const Map<OrderStatus, int> _codeByStatus = {
  OrderStatus.novo: 10,
  OrderStatus.emPreparo: 20,
  OrderStatus.pronto: 30,
  OrderStatus.entregue: 40,
};

// Separador do id composto (docId::comandaCodigo) usado pra identificar uma
// LEVA específica dentro de uma ocupação — nunca aparece nem num UUID nem
// num comandaCodigo, então é seguro pra split.
const _idSeparator = '::';

class MongoOrderRepository implements OrderRepository {
  final Db _db;
  static const _collectionName = 'venda.ocupacao';
  static const _itemsCollectionName = 'recurso.item';
  static const _pollInterval = Duration(seconds: 2);
  // Igual ao de getOrders — o Admin geralmente roda num dispositivo separado
  // da Cozinha, então a atualização otimista local (ver
  // ItemStatusOverridesController) não chega até ele; sem um poll no mesmo
  // ritmo, uma mudança feita na Cozinha demorava até 10s pra aparecer lá.
  static const _historyPollInterval = Duration(seconds: 2);
  // Larga o bastante pra cobrir todas as opções de período do Admin (hoje,
  // últimas 24h, 3 dias, semana, tudo — ver AdminHistoryPeriod), que filtram
  // em cima do que já veio daqui. Ainda é um limite (não "todo o histórico
  // pra sempre"), só generoso o suficiente pra não precisar ficar mudando a
  // consulta toda vez que uma opção de período for ajustada.
  static const _historyWindow = Duration(days: 30);
  static const _imageCacheTtl = Duration(minutes: 5);

  MongoOrderRepository(this._db);

  DbCollection get _collection => _db.collection(_collectionName);
  DbCollection get _itemsCollection => _db.collection(_itemsCollectionName);

  // Cache em memória de item.id -> URL da imagem (recurso.item.imagem). O
  // pedido em si não guarda a imagem (só um snapshot de id/código/nome), e o
  // catálogo tem centenas de produtos que raramente mudam — por isso um
  // cache com TTL em vez de consultar recurso.item a cada poll de 2s.
  Map<String, String> _imageCache = const {};
  DateTime? _imageCacheAt;

  @override
  Stream<List<Order>> getOrders() async* {
    // Mongo local roda standalone (sem replica set), então não há suporte a
    // Change Streams. O "tempo real" aqui é feito via polling.
    while (true) {
      try {
        yield await _fetchOrders();
      } catch (_) {
        // Mantém o stream vivo se uma consulta falhar (ex: instabilidade de rede).
      }
      await Future.delayed(_pollInterval);
    }
  }

  @override
  Stream<List<Order>> getOrderHistory() async* {
    while (true) {
      try {
        yield await _fetchHistory();
      } catch (_) {
        // Mantém o stream vivo se uma consulta falhar (ex: instabilidade de rede).
      }
      await Future.delayed(_historyPollInterval);
    }
  }

  Future<List<Order>> _fetchOrders() async {
    final imageCache = await _ensureImageCache();
    // "produzida: false" (ou ausente) identifica ocupações cuja produção na
    // cozinha ainda não terminou. Não usamos "conclusao: null" para isso:
    // vendas de Balcão fecham a conta (conclusao) no ato do pagamento, antes
    // mesmo de a cozinha começar a preparar — com o filtro por conclusao,
    // pedidos de Balcão sumiam do KDS assim que o pagamento era feito, mesmo
    // com os itens ainda "novo"/"em preparo".
    final docs = await _collection.find(where.ne('produzida', true)).toList();
    final orders = docs.expand((doc) => _docToOrders(doc, imageCache)).toList();
    orders.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return orders;
  }

  Future<List<Order>> _fetchHistory() async {
    final imageCache = await _ensureImageCache();
    // Sem filtro de "produzida" aqui, de propósito: o histórico do Admin
    // precisa mostrar também os pedidos já entregues (que _fetchOrders
    // esconde), só limitado por janela de tempo pra não crescer sem fim.
    final since = DateTime.now().toUtc().subtract(_historyWindow);
    final docs = await _collection.find(where.gte('inicio', since)).toList();
    final orders = docs.expand((doc) => _docToOrders(doc, imageCache)).toList();
    orders.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return orders;
  }

  Future<Map<String, String>> _ensureImageCache() async {
    final now = DateTime.now();
    if (_imageCacheAt != null &&
        now.difference(_imageCacheAt!) < _imageCacheTtl) {
      return _imageCache;
    }
    try {
      final docs =
          await _itemsCollection.find(where.fields(['id', 'imagem'])).toList();
      final cache = <String, String>{};
      for (final doc in docs) {
        final id = doc['id'] as String?;
        final imagem = doc['imagem'] as String?;
        // Alguns produtos legados guardam só o nome do arquivo, sem host.
        // Como não sabemos o bucket de origem desses, tratamos como "sem
        // imagem" em vez de arriscar montar uma URL quebrada.
        if (id != null && imagem != null && imagem.startsWith('http')) {
          cache[id] = imagem;
        }
      }
      _imageCache = cache;
      _imageCacheAt = now;
    } catch (_) {
      // Falha ao atualizar o catálogo não pode derrubar o polling de
      // pedidos: mantém o cache anterior (ou vazio, na primeira falha).
    }
    return _imageCache;
  }

  /// Uma ocupação (mesa/cartão) pode receber vários lançamentos ao longo do
  /// atendimento — bebidas primeiro, depois entrada, depois prato principal
  /// — cada um com seu próprio ocupacaoItens[i].comandaCodigo. Agrupar por
  /// esse código, um Order por grupo, é o que evita misturar uma leva nova
  /// (ainda "novo") com os itens de uma leva anterior já "entregue" da MESMA
  /// mesa num card só — sem isso, o card ficava com status/tempo decorrido
  /// da leva mais antiga mesmo quando um lançamento novo acabou de chegar.
  List<Order> _docToOrders(
      Map<String, dynamic> doc, Map<String, String> imageCache) {
    final itemsRaw = (doc['ocupacaoItens'] as List?) ?? const [];
    final docId = doc['id'] as String? ?? doc['_id'].toString();
    final inicio = doc['inicio'];
    final docTimestamp = inicio is DateTime ? inicio : DateTime.now();
    final edicao = doc['edicao'];
    final updatedAt = edicao is DateTime ? edicao : null;

    final modalidade = doc['modalidade'] as Map<String, dynamic>?;
    final localizador = doc['localizador'] as Map<String, dynamic>?;

    // Regra de negócio: sem localizador, o atendimento é sempre Balcão,
    // independente do que estiver em modalidade.nome.
    final modalityName = localizador == null
        ? 'Balcão'
        : (modalidade?['nome'] as String? ?? 'Balcão');
    final locatorLabel =
        localizador?['codigo'] as String? ?? localizador?['nome'] as String?;

    // Agrupa os itens por comandaCodigo, preservando a ordem de chegada dos
    // grupos (LinkedHashMap) — assim a leva mais antiga continua aparecendo
    // primeiro quando a tela lista os cards.
    final itemsByRound = <String, List<Map<String, dynamic>>>{};
    for (final raw in itemsRaw) {
      final item = raw as Map<String, dynamic>;
      final roundCode = item['comandaCodigo'] as String? ?? 'sem-codigo';
      (itemsByRound[roundCode] ??= []).add(item);
    }
    if (itemsByRound.isEmpty) {
      // Ocupação sem nenhum item ainda — mantém como um card vazio em vez de
      // desaparecer da lista.
      itemsByRound[''] = const [];
    }

    return itemsByRound.entries.map((entry) {
      final roundCode = entry.key;
      final rawItems = entry.value;

      DateTime? earliest;
      final items = rawItems.map((item) {
        final itemInfo = item['item'] as Map<String, dynamic>?;
        final quantidade = item['quantidade'];
        final catalogItemId = itemInfo?['id'] as String?;
        final producaoSituacao = item['producaoSituacao'];
        final producaoCode =
            producaoSituacao is num ? producaoSituacao.toInt() : -1;
        final observacoes = item['observacoes'] as String?;

        final inclusao = item['inclusao'];
        if (inclusao is DateTime &&
            (earliest == null || inclusao.isBefore(earliest!))) {
          earliest = inclusao;
        }

        return OrderItem(
          // id da linha do pedido (ocupacaoItens[i].id) — diferente do id do
          // produto no catálogo (item.item.id), usado só para buscar a imagem.
          id: item['id'] as String? ?? '',
          name: itemInfo?['nome'] as String? ?? 'Item',
          quantity: quantidade is num ? quantidade.toInt() : 1,
          status: _statusByCode[producaoCode] ?? OrderStatus.novo,
          imageUrl: catalogItemId != null ? imageCache[catalogItemId] : null,
          observation: (observacoes != null && observacoes.trim().isNotEmpty)
              ? observacoes
              : null,
        );
      }).toList();

      return Order(
        id: '$docId$_idSeparator$roundCode',
        number: (doc['numero'] as num?)?.toInt() ?? 0,
        items: items,
        observations: doc['observacoes'] as String?,
        // Horário dessa leva específica (menor inclusao entre seus itens),
        // não o início da ocupação inteira — uma mesa aberta há horas não
        // pode fazer uma leva lançada agora já nascer "atrasada".
        timestamp: earliest ?? docTimestamp,
        roundCode: roundCode,
        modalityName: modalityName,
        locatorLabel: locatorLabel,
        pdvSenha: doc['senha'] as String?,
        updatedAt: updatedAt,
      );
    }).toList();
  }

  /// O id do Order é composto (docId::comandaCodigo) — aqui separa de volta
  /// o id da ocupação de verdade no Mongo, que é o que toda escrita usa pra
  /// achar o documento.
  String _docIdFrom(String orderId) => orderId.split(_idSeparator).first;

  String _roundCodeFrom(String orderId) {
    final parts = orderId.split(_idSeparator);
    return parts.length > 1 ? parts.sublist(1).join(_idSeparator) : '';
  }

  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus newStatus) async {
    final code = _codeByStatus[newStatus];
    if (code == null) return;

    final docId = _docIdFrom(orderId);
    final roundCode = _roundCodeFrom(orderId);

    // Só avança os itens DESSA leva (mesmo comandaCodigo) — outras levas da
    // mesma mesa, ainda em preparo, não podem ser tocadas por engano quando
    // essa aqui é entregue.
    final update = modify
        .set('edicao', DateTime.now().toUtc())
        .set(r'ocupacaoItens.$[elem].producaoSituacao', code);

    if (newStatus != OrderStatus.entregue) {
      // Corrigindo uma entrega feita por engano: o documento inteiro não
      // pode continuar marcado como produzido, senão ele some do quadro
      // ativo da Cozinha (que filtra por "produzida") mesmo com essa leva
      // de volta pra "em preparo".
      update.set('produzida', false);
    }

    await _collection.updateOne(
      where.eq('id', docId),
      update,
      arrayFilters: [
        {'elem.comandaCodigo': roundCode},
      ],
    );

    if (newStatus == OrderStatus.entregue) {
      await _markProduzidaIfAllRoundsDone(docId);
    }
  }

  /// "produzida" é um campo do documento inteiro (não por leva) — só marca
  /// true quando TODAS as levas da ocupação já estiverem entregues, senão
  /// uma leva ainda em preparo sumiria do quadro ativo junto com a que
  /// acabou de ser entregue.
  Future<void> _markProduzidaIfAllRoundsDone(String docId) async {
    final doc = await _collection
        .findOne(where.eq('id', docId).fields(['ocupacaoItens']));
    final items = (doc?['ocupacaoItens'] as List?) ?? const [];
    final allDelivered = items.isNotEmpty &&
        items.every((raw) {
          final situacao = (raw as Map)['producaoSituacao'];
          return situacao is num &&
              situacao.toInt() == _codeByStatus[OrderStatus.entregue];
        });
    if (allDelivered) {
      await _collection.updateOne(
          where.eq('id', docId), modify.set('produzida', true));
    }
  }

  @override
  Future<void> updateItemStatus(
      String orderId, String itemId, OrderStatus newStatus) async {
    final code = _codeByStatus[newStatus];
    if (code == null || itemId.isEmpty) return;

    final docId = _docIdFrom(orderId);

    // Avança só o item tocado pela cozinha, via arrayFilters (identifica o
    // elemento de ocupacaoItens pelo próprio id da linha, não pelo id do
    // produto no catálogo). O status do pedido como um todo é derivado no
    // app a partir do status de cada item (ver Order.status).
    final update = modify
        .set(r'ocupacaoItens.$[elem].producaoSituacao', code)
        .set('edicao', DateTime.now().toUtc());

    // Se um administrador reverte um item pra antes de "entregue" (ex:
    // corrigindo um ENTREGAR clicado por engano), o pedido deixa de estar
    // produzido — senão ele continuaria escondido do quadro ativo da Cozinha
    // (que filtra por "produzida") mesmo já não estando mais entregue.
    if (newStatus != OrderStatus.entregue) {
      update.set('produzida', false);
    }

    await _collection.updateOne(
      where.eq('id', docId),
      update,
      arrayFilters: [
        {'elem.id': itemId},
      ],
    );

    if (newStatus == OrderStatus.entregue) {
      await _markProduzidaIfAllRoundsDone(docId);
    }
  }
}
