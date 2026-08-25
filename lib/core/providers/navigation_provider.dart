import 'package:flutter_riverpod/flutter_riverpod.dart';

final navigationProvider = StateProvider<String>((ref) => 'cozinha');
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);
