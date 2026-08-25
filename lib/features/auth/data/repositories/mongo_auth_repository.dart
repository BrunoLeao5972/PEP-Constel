import 'package:bcrypt/bcrypt.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../../domain/entities/kds_user.dart';
import '../../domain/repositories/auth_repository.dart';

class MongoAuthRepository implements AuthRepository {
  final Db _db;

  MongoAuthRepository(this._db);

  DbCollection get _collection => _db.collection('seguranca.usuario');

  @override
  Future<KdsUser> login(String credencial, String senha) async {
    final doc = await _findActiveUserDoc(credencial);

    if (doc == null) {
      throw AuthException('Usuário não encontrado ou inativo.');
    }

    final hash = doc['senha'] as String?;
    if (hash == null || !BCrypt.checkpw(senha, hash)) {
      throw AuthException('Senha incorreta.');
    }

    return _docToUser(doc);
  }

  Future<Map<String, dynamic>?> _findActiveUserDoc(String credencial) {
    return _collection.findOne(
      where.eq('credencial', credencial).eq('situacao', 1).eq('exclusao', null),
    );
  }

  KdsUser _docToUser(Map<String, dynamic> doc) {
    return KdsUser(
      id: doc['id'] as String,
      credencial: doc['credencial'] as String,
      nome: doc['nome'] as String? ?? doc['credencial'] as String,
      administrador: doc['administrador'] as bool? ?? false,
    );
  }
}
