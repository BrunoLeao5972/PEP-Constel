import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/order.dart';

enum KdsViewMode { list, kanban }

final kdsViewModeProvider =
    StateProvider<KdsViewMode>((ref) => KdsViewMode.list);

/// Filtro de status selecionado nos chips da tela da cozinha. Null significa
/// "Todos" (sem filtro).
final kdsStatusFilterProvider = StateProvider<OrderStatus?>((ref) => null);
