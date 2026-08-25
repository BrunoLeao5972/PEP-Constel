import 'dart:async';
import 'dart:io';
import 'package:mongo_dart/mongo_dart.dart';

/// Uma máquina encontrada na rede local com algo respondendo a conexões
/// MongoDB de verdade na porta indicada.
class DiscoveredServer {
  final String host;
  final int port;

  /// true quando o banco já tem as coleções que o APIL usa (ex:
  /// venda.ocupacao) — ajuda a distinguir "é o servidor certo" de "só tem
  /// algum outro Mongo nessa rede" quando mais de um responde.
  final bool looksLikeApil;

  const DiscoveredServer(
      {required this.host, required this.port, required this.looksLikeApil});
}

/// Varre a rede local (mesmo /24 do dispositivo) procurando por servidores
/// MongoDB alcançáveis na porta indicada.
///
/// Existe pra eliminar a etapa de configurar IP manualmente na instalação:
/// o Mongo do APIL sempre fica na mesma máquina que roda o APIL, então basta
/// perguntar pra cada endereço da rede "você é o Mongo do estabelecimento?"
/// em vez de pedir pro cliente descobrir e digitar o IP certo.
Future<List<DiscoveredServer>> discoverMongoServers({
  required int port,
  required String database,
  void Function(int checked, int total)? onProgress,
}) async {
  final subnetPrefix = await _localSubnetPrefix();
  if (subnetPrefix == null) return const [];

  final candidates = List.generate(254, (i) => '$subnetPrefix.${i + 1}');
  final found = <DiscoveredServer>[];
  var checked = 0;

  // Em lotes, pra não abrir 254 conexões simultâneas de uma vez.
  const batchSize = 32;
  for (var i = 0; i < candidates.length; i += batchSize) {
    final batch = candidates.skip(i).take(batchSize);
    final results =
        await Future.wait(batch.map((ip) => _probe(ip, port, database)));
    for (final result in results) {
      if (result != null) found.add(result);
    }
    checked += batch.length;
    onProgress?.call(checked, candidates.length);
  }

  // Servidores "de verdade" (com as coleções do APIL) primeiro.
  found.sort((a, b) => (b.looksLikeApil ? 1 : 0) - (a.looksLikeApil ? 1 : 0));
  return found;
}

Future<DiscoveredServer?> _probe(String host, int port, String database) async {
  // Primeiro um connect cru e rápido: a grande maioria dos 254 endereços não
  // tem nada escutando nessa porta, então descarta a maioria em ~400ms sem
  // gastar tempo tentando um handshake completo do Mongo.
  Socket? socket;
  try {
    socket = await Socket.connect(host, port,
        timeout: const Duration(milliseconds: 400));
  } catch (_) {
    return null;
  } finally {
    socket?.destroy();
  }

  // A porta respondeu — confirma que é mesmo um MongoDB (e não outra coisa
  // escutando na mesma porta) abrindo de verdade.
  Db? db;
  try {
    db = await Db.create('mongodb://$host:$port/$database');
    await db.open().timeout(const Duration(seconds: 2));
    final collections =
        await db.getCollectionNames().timeout(const Duration(seconds: 2));
    final looksLikeApil = collections.contains('venda.ocupacao');
    return DiscoveredServer(
        host: host, port: port, looksLikeApil: looksLikeApil);
  } catch (_) {
    return null;
  } finally {
    await db?.close();
  }
}

/// Primeiro octeto.octeto.octeto do endereço IPv4 local (ex: "192.168.0"),
/// usado como base pra varrer .1 até .254 da mesma rede.
Future<String?> _localSubnetPrefix() async {
  try {
    final interfaces =
        await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final interface in interfaces) {
      for (final addr in interface.addresses) {
        if (addr.isLoopback) continue;
        final parts = addr.address.split('.');
        if (parts.length == 4) {
          return '${parts[0]}.${parts[1]}.${parts[2]}';
        }
      }
    }
  } catch (_) {
    // Sem interface de rede acessível — quem chama trata lista vazia.
  }
  return null;
}
