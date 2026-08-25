import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mongo_dart/mongo_dart.dart';

import '../core/config/printer_config_provider.dart';
import '../core/data/mongo_service.dart';
import 'kds_printer_service.dart';

const _pollInterval = Duration(seconds: 2);

/// Idade a partir da qual um pedido de impressão já resolvido (feito ou
/// falho) é descartado da fila — evita que ela cresça pra sempre. Pedidos
/// ainda "pending" nunca são apagados por aqui, só quando processados.
const _resolvedJobMaxAge = Duration(hours: 6);

/// Roda só no Windows (é quem tem a impressora conectada): fica de olho na
/// fila de impressão remota no Mongo — pedidos vindos de um tablet Android
/// (Cozinha/Admin), que não tem impressora — e imprime localmente assim que
/// aparece um pendente, escrevendo o resultado de volta pro tablet ver.
///
/// Não faz nada em quem não é Windows: cada dispositivo roda sua própria
/// instância do app, mas só a que estiver com a impressora de fato ligada
/// deve processar a fila.
class PrintJobRelayController extends StateNotifier<int> {
  final Ref _ref;
  final _printer = KdsPrinterService();
  Timer? _timer;
  bool _processing = false;

  PrintJobRelayController(this._ref) : super(0) {
    if (Platform.isWindows) {
      _timer = Timer.periodic(_pollInterval, (_) => _processPending());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _processPending() async {
    if (_processing) return;
    _processing = true;
    try {
      final db = await _ref.read(mongoDbProvider.future);
      final collection = db.collection(kPrintJobsCollection);

      final pending =
          await collection.find(where.eq('status', 'pending')).toList();
      for (final job in pending) {
        await _processJob(collection, job);
      }

      final cutoff = DateTime.now().toUtc().subtract(_resolvedJobMaxAge);
      await collection.deleteMany(
        where.oneFrom('status', ['done', 'failed']).lt('createdAt', cutoff),
      );
    } catch (_) {
      // Mantém o watcher vivo mesmo se uma consulta falhar (ex: instabilidade
      // de rede) — a próxima rodada do timer tenta de novo.
    } finally {
      _processing = false;
    }
  }

  Future<void> _processJob(
      DbCollection collection, Map<String, dynamic> job) async {
    final jobId = job['_id'] as ObjectId;
    final printerName = _ref.read(printerConfigProvider).printerName;
    if (printerName == null || printerName.isEmpty) {
      await collection.updateOne(
        where.id(jobId),
        modify
            .set('status', 'failed')
            .set('error', 'Nenhuma impressora configurada neste PC.'),
      );
      return;
    }

    try {
      final bytes = base64Decode(job['bytes'] as String);
      final outcome = _printer.sendRawBytes(printerName, bytes);
      await collection.updateOne(
        where.id(jobId),
        modify
            .set('status', outcome.success ? 'done' : 'failed')
            .set('error', outcome.error),
      );
    } catch (e) {
      await collection.updateOne(
        where.id(jobId),
        modify.set('status', 'failed').set('error', e.toString()),
      );
    }
  }
}

final printJobRelayProvider =
    StateNotifierProvider<PrintJobRelayController, int>((ref) {
  return PrintJobRelayController(ref);
});
