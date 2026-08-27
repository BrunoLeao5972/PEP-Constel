import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intl/intl.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:win32/win32.dart';

import '../core/config/printer_config.dart';
import '../features/orders/domain/entities/order.dart';

/// Nome da coleção usada como fila de impressão remota — prefixo "kds_"
/// de propósito, pra não colidir nem se confundir com nada do schema do
/// PDV (venda.ocupacao etc.), já que essa coleção é só deste app.
const kPrintJobsCollection = 'kds_print_jobs';

// Não documentada nas constantes do pacote win32 — vem direto do winspool.h
// do Windows SDK. Sem pedir esse acesso explicitamente, OpenPrinter abre o
// handle só pra leitura e StartDocPrinter falha com "acesso negado" mais
// adiante, silenciosamente (a chamada só retorna 0, sem lançar exceção).
const int _kPrinterAccessUse = 0x00000008;

/// Resultado de uma tentativa de impressão, com o motivo da falha (quando
/// houver) pra poder mostrar algo além de "não funcionou" pro usuário.
class KdsPrintOutcome {
  final bool success;
  final String? error;
  const KdsPrintOutcome.ok()
      : success = true,
        error = null;
  const KdsPrintOutcome.failure(this.error) : success = false;
}

/// Serviço de impressão de pedidos via ESC/POS — usa a impressora tal como
/// o Windows a conhece (a mesma que aparece em "Impressoras e scanners" e
/// que já imprime a página de teste do próprio Windows), em vez de falar
/// direto com uma porta serial. Quem resolve velocidade/conexão é o driver
/// que o usuário já tem instalado — o app só manda os bytes ESC/POS como um
/// job "RAW" pra fila de impressão. Testado com a Daruma DR700, mas o
/// protocolo ESC/POS é o padrão de fato entre praticamente todas as
/// térmicas de cupom do mercado (Epson, Bematech, Elgin etc.).
class KdsPrinterService {
  /// Nomes de todas as impressoras instaladas no Windows (as mesmas que
  /// aparecem em Configurações → Impressoras e scanners). Usa
  /// PRINTER_INFO_4 (nível 4) porque é o único nível que não exige
  /// privilégios elevados só pra listar nomes.
  List<String> getAvailablePrinters() {
    try {
      return _listWindowsPrinters();
    } catch (_) {
      return const [];
    }
  }

  /// Imprime um pedido. No Windows, manda direto pra impressora configurada
  /// neste PC. Em qualquer outra plataforma (Android/Cozinha em tablet,
  /// sem impressora conectada), [db] é obrigatório: o ticket é enfileirado
  /// no Mongo (mesma base já usada pra sincronizar pedidos) e um PC com
  /// Windows rodando o KDS (ver [PrintJobRelayController]) pega o pedido e
  /// imprime de verdade, escrevendo o resultado de volta na fila.
  Future<KdsPrintOutcome> printOrder(Order order, PrinterConfig config,
      {Db? db}) async {
    final ticket = await buildOrderTicket(order, config.paperWidth.escPosSize);
    if (Platform.isWindows) {
      return _sendToPrinter(config, ticket);
    }
    if (db == null) {
      return const KdsPrintOutcome.failure(
          'Sem conexão com o banco para solicitar a impressão.');
    }
    return _requestRemotePrint(db, ticket);
  }

  Future<KdsPrintOutcome> printTestTicket(PrinterConfig config) async {
    final ticket = await _buildTestTicket(config.paperWidth.escPosSize);
    return _sendToPrinter(config, ticket);
  }

  /// Layout desenhado à mão pelo cliente (num editor de texto comum, daí
  /// medir tudo em colunas de um grid monoespaçado de 48 caracteres — a
  /// largura de uma bobina de 80mm em fonte normal). Em vez de repetir esse
  /// cálculo manualmente (o que só funcionaria pra 80mm), a MESMA estrutura
  /// é montada com `generator.row()`/`PosColumn` — a biblioteca já resolve
  /// a largura de cada coluna a partir do papel de verdade configurado
  /// (`paperSize`), então o layout sai proporcional tanto em 58mm quanto em
  /// 80mm sem precisar de duas versões.
  ///
  /// Sem o `_` (e com [visibleForTesting]): é a única forma de testar o
  /// conteúdo do ticket sem imprimir de verdade — Dart não deixa um teste
  /// em outro arquivo chamar um método privado desta classe.
  @visibleForTesting
  Future<Uint8List> buildOrderTicket(Order order, PaperSize paperSize) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    bytes += _init(generator);

    bytes += generator.hr(ch: '=');
    bytes += generator.text('PEP CONSTEL',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.hr(ch: '=');

    bytes += generator.row([
      PosColumn(
        text: 'PEDIDO: #${order.number}',
        width: 7,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: 'SENHA: ${_sanitizeForPrinter(order.pdvCallerLabel)}',
        width: 5,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);
    bytes +=
        generator.text('HORA: ${DateFormat('HH:mm').format(order.timestamp)}');
    bytes += generator.hr(ch: '-');

    bytes += generator.row([
      PosColumn(text: 'QTD', width: 3, styles: const PosStyles(bold: true)),
      PosColumn(text: 'ITEM', width: 9, styles: const PosStyles(bold: true)),
    ]);
    bytes += generator.hr(ch: '-');

    for (final item in order.items) {
      bytes += generator.row([
        PosColumn(text: '${item.quantity}x', width: 3),
        PosColumn(text: _sanitizeForPrinter(item.name), width: 9),
      ]);
      final observation = item.observation?.trim();
      if (observation != null && observation.isNotEmpty) {
        bytes += generator.text('  Obs: ${_sanitizeForPrinter(observation)}',
            styles: const PosStyles(reverse: true));
      }
    }
    bytes += generator.hr(ch: '-');

    final generalObservation = order.observations?.trim();
    if (generalObservation != null && generalObservation.isNotEmpty) {
      bytes += generator.text('OBSERVAÇÃO GERAL',
          styles: const PosStyles(bold: true));
      bytes += generator.text(_sanitizeForPrinter(generalObservation),
          styles: const PosStyles(reverse: true));
      bytes += generator.hr(ch: '=');
    }

    bytes += generator.text('solucaosistemas.net',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr(ch: '=');

    bytes += generator.feed(2);
    bytes += _cut(generator);
    return Uint8List.fromList(bytes);
  }

  /// `Generator(paperSize, profile)` codifica todo texto em Latin-1 por
  /// padrão, mas nunca diz pra impressora QUAL página de código usar pra
  /// interpretar esses bytes — ela usa a que já vem configurada de fábrica,
  /// e isso varia de marca pra marca (Epson, Elgin, GoldenTec, Daruma...).
  /// Sem fixar isso, os acentos do português só saem certos por sorte,
  /// quando o padrão de fábrica coincidir com Latin-1.
  ///
  /// `CP1252` (Windows-1252) resolve isso pra qualquer impressora ESC/POS
  /// compatível: é praticamente universal (é a página que todo software de
  /// PDV baseado em Windows já assume) e, no intervalo 0xA0-0xFF — onde
  /// ficam á, é, í, ó, ú, â, ê, ô, ã, õ, ç, à — os bytes são IDÊNTICOS aos
  /// de Latin-1. Por isso dá pra travar a impressora em CP1252 sem trocar a
  /// codificação Latin-1 que o `Generator` já usa: as duas concordam
  /// exatamente onde importa (o `_sanitizeForPrinter` já cuida do que não
  /// concorda, tipo aspas curvas, fora dessa faixa).
  List<int> _init(Generator generator) {
    List<int> bytes = [];
    bytes += generator.reset();
    bytes += generator.setGlobalCodeTable('CP1252');
    return bytes;
  }

  /// `generator.cut()` manda o corte no formato `GS V 0` (`0x1D 0x56 0x30`),
  /// o padrão de impressoras Epson mais novas. A Daruma DR700 é da linha
  /// "não fiscal" brasileira e responde ao comando legado `ESC i`
  /// (`0x1B 0x69`) — se ela não reconhece `GS V`, o corte nunca é
  /// executado e (nos testes reais com a impressora) o buffer de texto
  /// também não chega a ser descarregado pro cabeçote térmico: o Windows
  /// confirma que os bytes saíram pra porta, mas nada sai no papel.
  List<int> _cut(Generator generator) => generator.rawBytes([0x1B, 0x69]);

  /// O ESC/POS manda os bytes crus pra impressora (sem UTF-8): o `Generator`
  /// codifica cada texto em Latin-1, que cobre os acentos do português mas
  /// não aspas curvas ("smart quotes"), travessão, reticências ou emoji —
  /// coisas fáceis de vir de um copiar-colar no PDV. Um único caractere fora
  /// dessa faixa faz o `latin1.encode` da biblioteca lançar exceção e
  /// derruba o ticket inteiro (nada chega a ser impresso, sem aviso nenhum,
  /// já que quem imprime só descobre isso tentando com um pedido de
  /// verdade — o teste de conectividade usa um texto fixo que nunca teria
  /// esse problema). Por isso todo texto vindo do pedido passa por aqui
  /// antes de entrar num `generator.text()`/`row()`.
  String _sanitizeForPrinter(String text) {
    const replacements = {
      '’': "'",
      '‘': "'",
      '“': '"',
      '”': '"',
      '–': '-',
      '—': '-',
      '…': '...',
    };
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune <= 0xFF) {
        buffer.writeCharCode(rune);
        continue;
      }
      final replacement = replacements[String.fromCharCode(rune)];
      buffer.write(replacement ?? '?');
    }
    return buffer.toString();
  }

  Future<Uint8List> _buildTestTicket(PaperSize paperSize) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    bytes += _init(generator);
    bytes += generator.text(
      'PEP CONSTEL',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    bytes += generator.text('Teste de impressão',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr(ch: '=');
    bytes += generator.text('Se você está lendo isso,');
    bytes += generator.text('a impressora está configurada');
    bytes += generator.text('corretamente.');
    bytes += generator.hr(ch: '=');
    bytes += generator.text(
      DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.feed(2);
    bytes += _cut(generator);
    return Uint8List.fromList(bytes);
  }

  Future<KdsPrintOutcome> _sendToPrinter(
      PrinterConfig config, Uint8List bytes) async {
    final printerName = config.printerName;
    if (printerName == null || printerName.isEmpty) {
      return const KdsPrintOutcome.failure(
        'Nenhuma impressora configurada. Selecione em Configurações → Impressora.',
      );
    }
    return sendRawBytes(printerName, bytes);
  }

  /// Coloca o ticket na fila de impressão remota e espera (com timeout) até
  /// algum PC com Windows processá-lo — ver [PrintJobRelayController], que
  /// fica de olho nessa mesma coleção.
  Future<KdsPrintOutcome> _requestRemotePrint(Db db, Uint8List bytes) async {
    final collection = db.collection(kPrintJobsCollection);
    final jobId = ObjectId();
    try {
      await collection.insertOne({
        '_id': jobId,
        'bytes': base64Encode(bytes),
        'status': 'pending',
        'createdAt': DateTime.now().toUtc(),
      });
    } catch (e) {
      return KdsPrintOutcome.failure(
          'Não foi possível solicitar a impressão: $e');
    }

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 500));
      Map<String, dynamic>? job;
      try {
        job = await collection.findOne(where.id(jobId));
      } catch (_) {
        continue;
      }
      final status = job?['status'] as String?;
      if (status == 'done') return const KdsPrintOutcome.ok();
      if (status == 'failed') {
        return KdsPrintOutcome.failure(
            job?['error'] as String? ?? 'O PC não conseguiu imprimir.');
      }
    }
    return const KdsPrintOutcome.failure(
      'Nenhum computador com a impressora conectada respondeu a tempo. Verifique se '
      'o KDS está aberto no PC e se a impressora está configurada lá.',
    );
  }

  List<String> _listWindowsPrinters() {
    const flags = PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS;
    const level = 4;
    final pcbNeeded = calloc<Uint32>();
    final pcReturned = calloc<Uint32>();
    try {
      EnumPrinters(flags, nullptr, level, nullptr, 0, pcbNeeded, pcReturned);
      final bufferSize = pcbNeeded.value;
      if (bufferSize == 0) return const [];

      final buffer = calloc<Uint8>(bufferSize);
      try {
        final ok = EnumPrinters(
          flags,
          nullptr,
          level,
          buffer,
          bufferSize,
          pcbNeeded,
          pcReturned,
        );
        if (ok == 0) return const [];

        final count = pcReturned.value;
        final infoSize = sizeOf<PRINTER_INFO_4>();
        final names = <String>[];
        for (var i = 0; i < count; i++) {
          final info =
              Pointer<PRINTER_INFO_4>.fromAddress(buffer.address + i * infoSize)
                  .ref;
          if (info.pPrinterName != nullptr) {
            names.add(info.pPrinterName.toDartString());
          }
        }
        return names;
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(pcbNeeded);
      calloc.free(pcReturned);
    }
  }

  /// Manda [data] direto pra fila de impressão do Windows como um job RAW.
  /// Só funciona no Windows — no relay remoto (ver [PrintJobRelayController])
  /// é sempre chamado de um processo que já é Windows, mas o guard evita um
  /// crash de FFI se algo chamar isso por engano em outra plataforma.
  KdsPrintOutcome sendRawBytes(String printerName, Uint8List data) {
    if (!Platform.isWindows) {
      return const KdsPrintOutcome.failure(
          'Impressão direta disponível apenas no Windows.');
    }
    final phPrinter = calloc<IntPtr>();
    final printerNamePtr = printerName.toNativeUtf16();
    final defaults = calloc<PRINTER_DEFAULTS>();
    final defaultsDataTypePtr = 'RAW'.toNativeUtf16();
    try {
      defaults.ref.pDatatype = defaultsDataTypePtr;
      defaults.ref.pDevMode = nullptr;
      // Sem isso, o handle abre só com acesso padrão (leitura), e
      // StartDocPrinter falha mais adiante sem gerar nenhum erro visível.
      defaults.ref.DesiredAccess = _kPrinterAccessUse;

      if (OpenPrinter(printerNamePtr, phPrinter, defaults) == 0) {
        return KdsPrintOutcome.failure(
          'Não foi possível abrir "$printerName" (${_lastErrorMessage()}). Verifique se '
          'ela está ligada e conectada.',
        );
      }
      final hPrinter = phPrinter.value;

      final docInfo = calloc<DOC_INFO_1>();
      final docNamePtr = 'PEP Constel'.toNativeUtf16();
      final dataTypePtr = 'RAW'.toNativeUtf16();
      try {
        docInfo.ref.pDocName = docNamePtr;
        docInfo.ref.pOutputFile = nullptr;
        docInfo.ref.pDatatype = dataTypePtr;

        final jobId = StartDocPrinter(hPrinter, 1, docInfo);
        if (jobId == 0) {
          return KdsPrintOutcome.failure(
            'Não foi possível iniciar o trabalho de impressão (${_lastErrorMessage()}).',
          );
        }

        try {
          if (StartPagePrinter(hPrinter) == 0) {
            return KdsPrintOutcome.failure(
                'Não foi possível iniciar a página (${_lastErrorMessage()}).');
          }
          try {
            final buffer = calloc<Uint8>(data.length);
            final written = calloc<Uint32>();
            try {
              buffer.asTypedList(data.length).setAll(0, data);
              final ok =
                  WritePrinter(hPrinter, buffer.cast(), data.length, written);
              if (ok == 0) {
                return KdsPrintOutcome.failure(
                    'Falha ao enviar os dados (${_lastErrorMessage()}).');
              }
              return const KdsPrintOutcome.ok();
            } finally {
              calloc.free(buffer);
              calloc.free(written);
            }
          } finally {
            EndPagePrinter(hPrinter);
          }
        } finally {
          EndDocPrinter(hPrinter);
        }
      } finally {
        calloc.free(docInfo);
        calloc.free(docNamePtr);
        calloc.free(dataTypePtr);
      }
    } finally {
      if (phPrinter.value != 0) {
        ClosePrinter(phPrinter.value);
      }
      calloc.free(phPrinter);
      calloc.free(printerNamePtr);
      calloc.free(defaults);
      calloc.free(defaultsDataTypePtr);
    }
  }

  String _lastErrorMessage() => 'código de erro do Windows: ${GetLastError()}';
}
