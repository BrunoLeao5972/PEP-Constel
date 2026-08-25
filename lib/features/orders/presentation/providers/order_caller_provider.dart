import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/order_caller_config.dart';
import '../../../../core/config/order_caller_config_provider.dart';
import '../../domain/entities/order.dart';
import 'order_provider.dart';

const _prefNextNumber = 'caller_next_number';
const _prefResetDate = 'caller_reset_date';

/// Mantém, por pedido, o rótulo que o chamador de pedidos deve exibir.
///
/// Em modo PDV usa o que já vem do banco (modalidade + localizador). Em modo
/// KDS, atribui uma senha sequencial própria (a partir do número configurado
/// em Configurações) na primeira vez que vê cada pedido, e mantém esse número
/// fixo enquanto o pedido estiver ativo — mesmo que outros pedidos sejam
/// concluídos e saiam da lista.
class OrderCallLabelsController extends StateNotifier<Map<String, String>> {
  final Ref _ref;
  final Map<String, int> _ticketNumbers = {};
  late int _nextNumber;
  int _configuredStartNumber;
  String? _resetDateKey;
  Timer? _dailyResetTimer;

  OrderCallLabelsController(this._ref)
      : _configuredStartNumber =
            _ref.read(orderCallerConfigProvider).startNumber,
        super({}) {
    _nextNumber = _configuredStartNumber;
    _loadPersisted();
    _ref.listen<AsyncValue<List<Order>>>(ordersStreamProvider,
        (previous, next) {
      next.whenData(_onOrders);
    }, fireImmediately: true);

    // A virada do dia só era conferida quando o stream de pedidos emitia
    // (a cada poll) — de madrugada, com o restaurante fechado e sem pedidos
    // ativos, isso ainda acontece (o poll roda mesmo com lista vazia), mas
    // esse timer garante a checagem de qualquer forma, sem depender de
    // nenhum efeito colateral do stream. Sempre usa o relógio LOCAL do
    // computador (DateTime.now()) — nunca um horário vindo de pedidos/APIL,
    // que fica em outro fuso (direto da AWS).
    _dailyResetTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _maybeResetForNewDay(_ref.read(orderCallerConfigProvider).resetDaily);
    });
  }

  @override
  void dispose() {
    _dailyResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    _resetDateKey = prefs.getString(_prefResetDate);
    final saved = prefs.getInt(_prefNextNumber);
    if (saved != null) {
      _nextNumber = saved;
    }
    _publishNextNumber();
  }

  void _onOrders(List<Order> orders) {
    final config = _ref.read(orderCallerConfigProvider);

    if (config.source == CallerNumberingSource.pdv) {
      state = {for (final order in orders) order.id: order.pdvCallerLabel};
      return;
    }

    _syncStartNumberChange(config.startNumber);
    _maybeResetForNewDay(config.resetDaily);

    final updated = <String, String>{};
    for (final order in orders) {
      final number = _ticketNumbers[order.id] ?? _assignNumber(order.id);
      updated[order.id] = number.toString().padLeft(2, '0');
    }
    state = updated;
    _publishNextNumber();
  }

  // Expõe o próximo número à parte do mapa de rótulos (que é por pedido) pra
  // Configurações poder mostrar, em tempo real, em que número o contador do
  // modo KDS está — sem isso o operador só descobria abrindo o Chamador.
  void _publishNextNumber() {
    final notifier = _ref.read(kdsNextCallNumberProvider.notifier);
    if (notifier.state != _nextNumber) {
      notifier.state = _nextNumber;
    }
  }

  // Se o usuário mudou o número inicial em Configurações, reinicia a
  // sequência a partir dele (os pedidos já em tela recebem senha nova).
  void _syncStartNumberChange(int startNumber) {
    if (_configuredStartNumber == startNumber) return;
    _configuredStartNumber = startNumber;
    _nextNumber = startNumber;
    _ticketNumbers.clear();
    _persist();
  }

  int _assignNumber(String orderId) {
    final number = _nextNumber++;
    _ticketNumbers[orderId] = number;
    _persist();
    return number;
  }

  void _maybeResetForNewDay(bool resetDaily) {
    if (!resetDaily) return;
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (_resetDateKey != todayKey) {
      _resetDateKey = todayKey;
      _nextNumber = _configuredStartNumber;
      _ticketNumbers.clear();
      _persist(resetDate: todayKey);
      _publishNextNumber();
    }
  }

  /// Zera a sequência do modo KDS imediatamente — chamado pelo botão "Zerar
  /// Sequência Agora" em Configurações, independente do reset automático
  /// diário (que só vira à meia-noite do relógio do computador).
  ///
  /// De propósito, NÃO limpa [_ticketNumbers]: isso faria qualquer pedido
  /// ainda ativo na cozinha "esquecer" a senha que já tinha e ganhar uma
  /// nova no próximo poll — na prática, o número recém-zerado era
  /// imediatamente consumido por um pedido já em andamento, e a tela de
  /// Configurações mostrava o contador "pulando" pra 2 sozinho segundos
  /// depois do clique. Só o contador (pra pedidos futuros) é reiniciado;
  /// pedidos já ativos mantêm a senha que o cliente já recebeu.
  void resetSequenceNow() {
    _nextNumber = _configuredStartNumber;
    _resetDateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _persist(resetDate: _resetDateKey);
    _publishNextNumber();
  }

  Future<void> _persist({String? resetDate}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefNextNumber, _nextNumber);
    if (resetDate != null) {
      await prefs.setString(_prefResetDate, resetDate);
    }
  }
}

final orderCallLabelsProvider =
    StateNotifierProvider<OrderCallLabelsController, Map<String, String>>(
        (ref) {
  return OrderCallLabelsController(ref);
});

/// Próximo número que o modo KDS vai atribuir — mantido por
/// [OrderCallLabelsController], exposto à parte pra Configurações poder
/// mostrar "em que pedido o contador está" sem precisar do mapa de rótulos
/// (que é por pedido, não um contador global).
final kdsNextCallNumberProvider = StateProvider<int>((ref) => 1);
