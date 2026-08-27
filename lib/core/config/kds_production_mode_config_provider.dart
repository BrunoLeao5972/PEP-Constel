import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'kds_production_mode_config.dart';

const _prefMode = 'kds_production_mode';

class KdsProductionModeConfigNotifier
    extends StateNotifier<KdsProductionModeConfig> {
  KdsProductionModeConfigNotifier() : super(const KdsProductionModeConfig()) {
    ready = _load();
  }

  /// Mesmo padrão de `MongoConfigNotifier.ready`: resolve quando o modo
  /// salvo já foi lido pra memória.
  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_prefMode);
    // Nada salvo (ou um nome que não bate com nenhum valor conhecido —
    // ex: um enum salvo por uma versão futura do app): mantém o que já
    // estava em `state` (o padrão de fábrica), em vez de reafirmar
    // `perItem` incondicionalmente — mesmo cuidado dos outros notifiers de
    // config (`OrderCallerConfigNotifier` etc.). Sem isso, um `state`
    // aplicado por fora entre a construção e o fim deste `await` (como um
    // override de teste) seria sobrescrito de volta ao padrão assim que a
    // leitura terminasse.
    if (name == null) return;
    for (final mode in KdsProductionMode.values) {
      if (mode.name == name) {
        state = KdsProductionModeConfig(mode: mode);
        return;
      }
    }
  }

  Future<void> setMode(KdsProductionMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefMode, mode.name);
    state = state.copyWith(mode: mode);
  }
}

final kdsProductionModeConfigProvider = StateNotifierProvider<
    KdsProductionModeConfigNotifier, KdsProductionModeConfig>((ref) {
  return KdsProductionModeConfigNotifier();
});
