import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mongo_dart/mongo_dart.dart';
import '../config/mongo_config_provider.dart';

// Sem isso, uma tentativa de conexão pra um IP inalcançável (ex: celular
// trocou de rede e o IP salvo não existe mais nela) pode ficar pendurada por
// minutos no timeout de socket do sistema operacional, travando a tela de
// login. Falha rápido e deixa a UI decidir o que mostrar.
const _connectTimeout = Duration(seconds: 8);

final mongoDbProvider = FutureProvider<Db>((ref) async {
  final config = ref.watch(mongoConfigProvider);
  final db = await Db.create(config.connectionString);
  await db.open().timeout(
        _connectTimeout,
        onTimeout: () => throw TimeoutException(
          'Tempo esgotado ao conectar em ${config.host}:${config.port}',
        ),
      );
  ref.onDispose(() {
    db.close();
  });
  return db;
});
