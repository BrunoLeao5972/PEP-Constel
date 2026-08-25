import 'dart:async';
import 'dart:io';

/// Erro de CONEXÃO (não chegou a autenticar) — diferente de credencial
/// errada. Usado pra decidir se o login deve levar o usuário direto pra tela
/// de Configurações em vez de só mostrar o erro ali mesmo: errar a senha não
/// deve mandar ninguém pra Configurações, mas não conseguir alcançar o
/// servidor sim.
class ServerUnreachableException implements Exception {
  final String message;
  ServerUnreachableException(this.message);

  @override
  String toString() => message;
}

/// Traduz erros técnicos de conexão com o MongoDB (timeout, recusa de
/// conexão, host inalcançável) numa mensagem que o usuário final consegue
/// entender e agir a partir dela — em vez de expor a exceção crua do
/// Dart/mongo_dart (usada tanto no login quanto no teste de conexão das
/// Configurações, pra não ter dois textos diferentes pro mesmo problema).
String friendlyMongoError(Object error, {String? host, int? port}) {
  final where = (host != null && port != null) ? ' em $host:$port' : '';
  final text = error.toString();

  if (error is TimeoutException || text.contains('TimeoutException')) {
    return 'O servidor$where não respondeu a tempo.\n'
        'Verifique se este dispositivo está na mesma rede Wi-Fi do computador do sistema.';
  }

  // O dispositivo alcançou a máquina, mas nada aceitou a conexão naquela
  // porta — quase sempre é o MongoDB não estar rodando ali, ou estar
  // configurado pra aceitar conexão só do próprio computador
  // (bindIp: 127.0.0.1), não da rede.
  if (_isConnectionRefused(text)) {
    return 'A conexão$where foi recusada.\n'
        'Verifique se o MongoDB está rodando nessa máquina, se está configurado pra aceitar conexões '
        'da rede (não só do próprio computador) e se o firewall libera a porta.';
  }

  if (error is SocketException ||
      text.contains('SocketException') ||
      text.contains('No route to host') ||
      text.contains('Network is unreachable')) {
    return 'Não foi possível alcançar o servidor$where.\n'
        'Verifique se este dispositivo está na mesma rede do computador do sistema.';
  }

  return 'Erro de conexão com o servidor$where: $error';
}

// A mensagem do sistema operacional embutida na exceção vem no idioma do
// aparelho (em português no Windows, por exemplo) — não dá pra confiar só
// na frase em inglês "Connection refused" pra identificar o problema. Já o
// número do errno é estável entre idiomas: 111 (Linux/Android), 61
// (macOS/BSD) e 10061/1225 (Windows) identificam recusa de conexão em
// qualquer idioma do sistema.
const _connectionRefusedErrnos = {111, 61, 10061, 1225};

bool _isConnectionRefused(String text) {
  if (text.contains('Connection refused')) return true;
  final match = RegExp(r'errno\s*=\s*(\d+)').firstMatch(text);
  if (match == null) return false;
  final code = int.tryParse(match.group(1)!);
  return code != null && _connectionRefusedErrnos.contains(code);
}
