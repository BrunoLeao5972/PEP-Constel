import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/config/mongo_config_provider.dart';
import '../../../../core/data/mongo_error.dart';
import '../../../../core/data/mongo_service.dart';
import '../../data/repositories/mongo_auth_repository.dart';
import '../../domain/entities/kds_user.dart';
import '../../domain/repositories/auth_repository.dart';

const _prefSavedCredencial = 'saved_login_credencial';
const _prefSavedSenha = 'saved_login_senha';

/// Lê as credenciais salvas localmente (usuário e senha), se houver.
Future<({String credencial, String senha})?> loadSavedCredentials() async {
  final prefs = await SharedPreferences.getInstance();
  final credencial = prefs.getString(_prefSavedCredencial);
  final senha = prefs.getString(_prefSavedSenha);
  if (credencial == null || senha == null) return null;
  return (credencial: credencial, senha: senha);
}

class AuthController extends StateNotifier<AsyncValue<KdsUser?>> {
  final Ref _ref;

  AuthController(this._ref) : super(const AsyncValue.data(null));

  Future<void> login(String credencial, String senha,
      {bool saveCredentials = false}) async {
    state = const AsyncValue.loading();

    final Db db;
    try {
      db = await _connectedDb();
    } catch (e, stack) {
      // Falhou antes mesmo de chegar a autenticar — não é senha errada, é o
      // servidor configurado que não responde. A LoginPage usa esse tipo
      // pra saber quando deve levar o usuário direto pra Configurações.
      final config = _ref.read(mongoConfigProvider);
      state = AsyncValue.error(
        ServerUnreachableException(
            friendlyMongoError(e, host: config.host, port: config.port)),
        stack,
      );
      return;
    }

    try {
      final repository = MongoAuthRepository(db);
      final user = await repository.login(credencial, senha);
      state = AsyncValue.data(user);

      final prefs = await SharedPreferences.getInstance();
      if (saveCredentials) {
        await prefs.setString(_prefSavedCredencial, credencial);
        await prefs.setString(_prefSavedSenha, senha);
      } else {
        await prefs.remove(_prefSavedCredencial);
        await prefs.remove(_prefSavedSenha);
      }
    } catch (e, stack) {
      state = AsyncValue.error(
          e is AuthException ? e : AuthException(e.toString()), stack);
    }
  }

  /// Garante uma conexão válida com o banco antes do login. Se a última
  /// tentativa não tiver dado certo (rede trocou, servidor fora do ar
  /// etc.), força uma nova tentativa em vez de repetir o erro antigo pra
  /// sempre — o usuário pode ter mudado de rede desde então.
  Future<Db> _connectedDb() {
    if (!_ref.read(mongoDbProvider).hasValue) {
      _ref.invalidate(mongoDbProvider);
    }
    return _ref.read(mongoDbProvider.future);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefSavedCredencial);
    await prefs.remove(_prefSavedSenha);
    state = const AsyncValue.data(null);
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<KdsUser?>>((ref) {
  return AuthController(ref);
});
