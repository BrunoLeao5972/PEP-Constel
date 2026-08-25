import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../orders/domain/entities/order.dart';

/// Filtro de status selecionado nos chips da página administrativa.
/// Null significa "Todos" (sem filtro).
final adminStatusFilterProvider = StateProvider<OrderStatus?>((ref) => null);

/// Texto de busca do histórico (por nº do pedido, modalidade/senha ou nome
/// de item).
final adminSearchQueryProvider = StateProvider<String>((ref) => '');

/// Período do histórico a exibir — filtrado no app em cima do que o
/// repositório já busca (ver MongoOrderRepository, hoje uma janela larga o
/// bastante pra cobrir todas essas opções).
enum AdminHistoryPeriod {
  today('Hoje'),
  last24h('Últimas 24h'),
  last3Days('Últimos 3 dias'),
  lastWeek('Última semana'),
  all('Tudo');

  final String label;
  const AdminHistoryPeriod(this.label);

  /// Data de corte (itens com timestamp antes disso ficam de fora) — null
  /// significa sem corte ("Tudo").
  DateTime? cutoff() {
    final now = DateTime.now();
    switch (this) {
      case AdminHistoryPeriod.today:
        return DateTime(now.year, now.month, now.day);
      case AdminHistoryPeriod.last24h:
        return now.subtract(const Duration(hours: 24));
      case AdminHistoryPeriod.last3Days:
        return now.subtract(const Duration(days: 3));
      case AdminHistoryPeriod.lastWeek:
        return now.subtract(const Duration(days: 7));
      case AdminHistoryPeriod.all:
        return null;
    }
  }
}

final adminHistoryPeriodProvider =
    StateProvider<AdminHistoryPeriod>((ref) => AdminHistoryPeriod.last24h);

/// Quantas ocorrências mostrar na tela, no máximo — pra listas de histórico
/// grandes não ficarem pesadas nem poluídas.
const adminPageSizeOptions = [10, 20, 30, 40, 50];

final adminPageSizeProvider = StateProvider<int>((ref) => 20);
