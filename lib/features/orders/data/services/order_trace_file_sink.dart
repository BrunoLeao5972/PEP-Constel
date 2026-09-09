import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

const _encoder = JsonEncoder.withIndent('  ');

/// Onde o log de rastreabilidade dos pedidos fica — dentro de "Documentos"
/// (não em AppData/dados do app) de propósito: é a pasta que qualquer
/// pessoa acha pelo Explorer sem precisar saber onde o Flutter guarda
/// dados de app, já que por ora este arquivo é o único jeito de ver os
/// eventos rodando o app instalado (fora do modo debug, `developer.log`
/// não vai pra lugar nenhum visível — não existe VM service anexado).
///
/// No Android, `getApplicationDocumentsDirectory()` aponta pro
/// armazenamento privado do app (não dá pra abrir por um gerenciador de
/// arquivos comum sem root/ADB) — esperado, já que a Cozinha em tablet só
/// exibe o painel, quem imprime/gerencia pedido é o PC com Windows.
Future<File> orderTraceLogFile() async {
  final documentsDir = await getApplicationDocumentsDirectory();
  final dir = Directory(
      '${documentsDir.path}${Platform.pathSeparator}PEP Constel');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return File('${dir.path}${Platform.pathSeparator}order_trace.json');
}

/// Serializa as chamadas a [appendOrderTraceEvent] entre si. O arquivo é um
/// ARRAY json de verdade (não JSONL) pra abrir legível num visualizador
/// comum — e isso exige ler o array inteiro, acrescentar e regravar por
/// completo a cada evento, ao contrário de um append puro. Duas mudanças
/// de status quase simultâneas (ex: um "avançar comanda inteira" que
/// dispara vários itens de uma vez) vão gerar duas chamadas concorrentes;
/// sem essa fila, a segunda leitura aconteceria antes da primeira escrita
/// terminar e o evento mais antigo se perderia. Encadear numa Future só
/// garante que cada gravação espera a anterior de verdade acabar.
Future<void> _writeQueue = Future<void>.value();

/// Acrescenta [event] ao array json do arquivo de log, reescrevendo-o
/// inteiro e formatado (indentação de 2 espaços) — o mesmo formato que um
/// `jsonDecode` de qualquer visualizador de JSON entende de primeira.
///
/// Best-effort: uma falha aqui (disco cheio, sem permissão, arquivo
/// corrompido por fora etc.) não deve derrubar nada — quando isto é
/// chamado, a atualização de status do pedido já terminou com sucesso.
Future<void> appendOrderTraceEvent(Map<String, dynamic> event) {
  final result = _writeQueue.then((_) => _appendLocked(event)).catchError(
    (_) {
      // Intencional: ver o comentário acima.
    },
  );
  _writeQueue = result;
  return result;
}

Future<void> _appendLocked(Map<String, dynamic> event) async {
  final file = await orderTraceLogFile();
  final events = await _readExistingEvents(file);
  events.add(event);
  await file.writeAsString(_encoder.convert(events), flush: true);
}

/// Lê o array já gravado — devolve uma lista vazia (não lança) se o
/// arquivo ainda não existe, está vazio, ou (arquivo editado à mão, versão
/// antiga em JSONL etc.) não é um array json válido: um log corrompido não
/// deve impedir novos eventos de serem registrados.
Future<List<dynamic>> _readExistingEvents(File file) async {
  if (!await file.exists()) return [];
  final raw = await file.readAsString();
  if (raw.trim().isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded : [];
  } catch (_) {
    return [];
  }
}
