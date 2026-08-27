import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'alert_appearance_config.dart';

const _prefEnabled = 'alert_visual_enabled';
const _prefAnimationEnabled = 'alert_animation_enabled';
const _prefColorIntensity = 'alert_color_intensity';
const _prefSpeedFactor = 'alert_speed_factor';

class AlertAppearanceConfigNotifier
    extends StateNotifier<AlertAppearanceConfig> {
  AlertAppearanceConfigNotifier() : super(const AlertAppearanceConfig()) {
    ready = _load();
  }

  /// Resolve quando a config salva já foi lida para a memória — mesmo
  /// padrão de `MongoConfigNotifier.ready`, útil sobretudo em teste (aqui
  /// não há tela que dependa de esperar por isso: a UI já nasce no padrão de
  /// fábrica e re-renderiza sozinha assim que a leitura termina).
  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AlertAppearanceConfig(
      enabled: prefs.getBool(_prefEnabled) ?? state.enabled,
      animationEnabled:
          prefs.getBool(_prefAnimationEnabled) ?? state.animationEnabled,
      colorIntensity:
          prefs.getDouble(_prefColorIntensity) ?? state.colorIntensity,
      speedFactor: prefs.getDouble(_prefSpeedFactor) ?? state.speedFactor,
    );
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, value);
    state = state.copyWith(enabled: value);
  }

  Future<void> setAnimationEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAnimationEnabled, value);
    state = state.copyWith(animationEnabled: value);
  }

  /// Aplica a intensidade na hora (o preview do pisca reage ao slider sem
  /// esperar o disco) e grava em seguida — sem o adiamento que a
  /// personalização de cores do Painel usa, porque aqui não há centenas de
  /// pedidos piscando um `jsonEncode` a cada tick: é só um double.
  Future<void> setColorIntensity(double value) async {
    final clamped = value.clamp(
      AlertAppearanceConfig.minColorIntensity,
      AlertAppearanceConfig.maxColorIntensity,
    );
    state = state.copyWith(colorIntensity: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefColorIntensity, clamped);
  }

  Future<void> setSpeedFactor(double value) async {
    final clamped = value.clamp(
      AlertAppearanceConfig.minSpeedFactor,
      AlertAppearanceConfig.maxSpeedFactor,
    );
    state = state.copyWith(speedFactor: clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefSpeedFactor, clamped);
  }
}

final alertAppearanceConfigProvider =
    StateNotifierProvider<AlertAppearanceConfigNotifier, AlertAppearanceConfig>(
        (ref) {
  return AlertAppearanceConfigNotifier();
});
