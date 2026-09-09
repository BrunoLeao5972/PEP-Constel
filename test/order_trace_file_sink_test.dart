import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:kds_constel/features/orders/data/services/order_trace_file_sink.dart';

/// `getApplicationDocumentsDirectory()` fala com o SO por um platform
/// channel — não existe de verdade rodando `flutter test`. Substituir a
/// implementação por uma que devolve uma pasta temporária real (criada e
/// limpa a cada teste) deixa o resto do código (criar a pasta "PEP
/// Constel", ler/regravar o arquivo) exercitando I/O de arquivo de
/// verdade, só sem depender da plataforma.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('order_trace_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('o arquivo fica dentro de uma pasta "PEP Constel", em .json', () async {
    final file = await orderTraceLogFile();
    expect(file.path, contains('PEP Constel'));
    expect(file.path, endsWith('order_trace.json'));
  });

  test('grava como um array json de verdade, formatado com indentação',
      () async {
    await appendOrderTraceEvent({'evento': 'a', 'numero': 1});

    final file = await orderTraceLogFile();
    final raw = await file.readAsString();

    expect(jsonDecode(raw), [
      {'evento': 'a', 'numero': 1}
    ]);
    // Formatado (indentado), não compacto numa linha só — é o ponto do
    // pedido: abrir no Bloco de Notas e já dar pra ler. 4 espaços porque o
    // objeto está aninhado dentro do array (2 do array + 2 do objeto).
    expect(raw, contains('\n    "evento": "a"'));
  });

  test('cada chamada acrescenta ao array — não sobrescreve as anteriores',
      () async {
    await appendOrderTraceEvent({'evento': 'a', 'numero': 1});
    await appendOrderTraceEvent({'evento': 'b', 'numero': 2});

    final file = await orderTraceLogFile();
    final decoded = jsonDecode(await file.readAsString()) as List;

    expect(decoded, [
      {'evento': 'a', 'numero': 1},
      {'evento': 'b', 'numero': 2},
    ]);
  });

  test('chamadas concorrentes não se atropelam (a fila serializa as '
      'gravações)', () async {
    // Sem a fila de escrita, as duas chamadas leriam o array "vazio" ao
    // mesmo tempo e cada uma regravaria por cima da outra — só um dos
    // dois eventos sobreviveria.
    await Future.wait([
      appendOrderTraceEvent({'evento': 'a'}),
      appendOrderTraceEvent({'evento': 'b'}),
      appendOrderTraceEvent({'evento': 'c'}),
    ]);

    final file = await orderTraceLogFile();
    final decoded = jsonDecode(await file.readAsString()) as List;
    expect(decoded, hasLength(3));
  });

  test('funciona mesmo se a pasta ainda não existir', () async {
    final expectedDir =
        Directory('${tempDir.path}${Platform.pathSeparator}PEP Constel');
    expect(expectedDir.existsSync(), isFalse);

    await appendOrderTraceEvent({'evento': 'a'});

    expect(expectedDir.existsSync(), isTrue);
  });

  test('arquivo corrompido (ou no formato antigo, JSONL) não trava — '
      'recomeça do zero em vez de lançar', () async {
    final file = await orderTraceLogFile();
    await file.writeAsString('{"evento": "linha solta, não é um array}\n');

    await appendOrderTraceEvent({'evento': 'novo'});

    final decoded = jsonDecode(await file.readAsString()) as List;
    expect(decoded, [
      {'evento': 'novo'}
    ]);
  });
}
