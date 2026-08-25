import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mongo_config.dart';

const _prefHost = 'mongo_host';
const _prefPort = 'mongo_port';
const _prefDatabase = 'mongo_database';

class MongoConfigNotifier extends StateNotifier<MongoConfig> {
  MongoConfigNotifier() : super(const MongoConfig()) {
    ready = _load();
  }

  /// Resolve assim que a config salva (se houver) já foi carregada pro
  /// estado em memória. O main() espera por isso antes de abrir a primeira
  /// tela — sem essa espera, o primeiríssimo login do app (antes de alguém
  /// nunca ter aberto Configurações) podia disparar a conexão usando o host
  /// padrão (127.0.0.1) em vez do IP salvo, porque esse construtor não pode
  /// ser async e `state` só é atualizado quando o SharedPreferences.getInstance()
  /// (assíncrono) termina — ficava "preso" até o timeout de 8s achando que o
  /// servidor salvo não respondia.
  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = MongoConfig(
      host: prefs.getString(_prefHost) ?? state.host,
      port: prefs.getInt(_prefPort) ?? state.port,
      database: prefs.getString(_prefDatabase) ?? state.database,
    );
  }

  Future<void> update(
      {required String host,
      required int port,
      required String database}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefHost, host);
    await prefs.setInt(_prefPort, port);
    await prefs.setString(_prefDatabase, database);
    state = MongoConfig(host: host, port: port, database: database);
  }
}

final mongoConfigProvider =
    StateNotifierProvider<MongoConfigNotifier, MongoConfig>((ref) {
  return MongoConfigNotifier();
});
