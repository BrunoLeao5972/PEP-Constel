import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'service_modalities_config.dart';

const _prefBalcaoEnabled = 'modality_balcao_enabled';
const _prefMesaEnabled = 'modality_mesa_enabled';
const _prefCartaoEnabled = 'modality_cartao_enabled';

class ServiceModalitiesConfigNotifier
    extends StateNotifier<ServiceModalitiesConfig> {
  ServiceModalitiesConfigNotifier() : super(const ServiceModalitiesConfig()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ServiceModalitiesConfig(
      balcaoEnabled: prefs.getBool(_prefBalcaoEnabled) ?? state.balcaoEnabled,
      mesaEnabled: prefs.getBool(_prefMesaEnabled) ?? state.mesaEnabled,
      cartaoEnabled: prefs.getBool(_prefCartaoEnabled) ?? state.cartaoEnabled,
    );
  }

  Future<void> setBalcaoEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBalcaoEnabled, value);
    state = state.copyWith(balcaoEnabled: value);
  }

  Future<void> setMesaEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefMesaEnabled, value);
    state = state.copyWith(mesaEnabled: value);
  }

  Future<void> setCartaoEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefCartaoEnabled, value);
    state = state.copyWith(cartaoEnabled: value);
  }
}

final serviceModalitiesConfigProvider = StateNotifierProvider<
    ServiceModalitiesConfigNotifier, ServiceModalitiesConfig>((ref) {
  return ServiceModalitiesConfigNotifier();
});
