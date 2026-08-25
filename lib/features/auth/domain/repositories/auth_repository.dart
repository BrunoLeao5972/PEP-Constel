import '../entities/kds_user.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

abstract class AuthRepository {
  Future<KdsUser> login(String credencial, String senha);
}
