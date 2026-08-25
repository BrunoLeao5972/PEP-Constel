import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'panel_display_config.dart';

const _prefShowBalcao = 'panel_show_balcao';
const _prefShowMesa = 'panel_show_mesa';
const _prefShowCartao = 'panel_show_cartao';

class PanelDisplayConfigNotifier extends StateNotifier<PanelDisplayConfig> {
  PanelDisplayConfigNotifier() : super(const PanelDisplayConfig()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = PanelDisplayConfig(
      showBalcao: prefs.getBool(_prefShowBalcao) ?? state.showBalcao,
      showMesa: prefs.getBool(_prefShowMesa) ?? state.showMesa,
      showCartao: prefs.getBool(_prefShowCartao) ?? state.showCartao,
    );
  }

  Future<void> setShowBalcao(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefShowBalcao, value);
    state = state.copyWith(showBalcao: value);
  }

  Future<void> setShowMesa(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefShowMesa, value);
    state = state.copyWith(showMesa: value);
  }

  Future<void> setShowCartao(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefShowCartao, value);
    state = state.copyWith(showCartao: value);
  }
}

final panelDisplayConfigProvider =
    StateNotifierProvider<PanelDisplayConfigNotifier, PanelDisplayConfig>(
        (ref) {
  return PanelDisplayConfigNotifier();
});
