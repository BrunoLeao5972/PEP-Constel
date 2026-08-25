import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

/// Largura do rolo de papel da impressora térmica — controla quantos
/// caracteres cabem por linha nos separadores e na quebra de texto do
/// ticket. 58mm e 80mm são os dois padrões de mercado.
enum PrinterPaperWidth {
  mm58(PaperSize.mm58),
  mm80(PaperSize.mm80);

  final PaperSize escPosSize;
  const PrinterPaperWidth(this.escPosSize);
}

class PrinterConfig {
  /// Nome da impressora exatamente como o Windows a identifica (o mesmo
  /// nome que aparece em "Impressoras e scanners") — não uma porta COM: a
  /// velocidade/conexão fica por conta do driver que o Windows já usa pra
  /// imprimir a página de teste, o app não precisa (nem deve) configurar
  /// isso de novo. Null = nenhuma configurada ainda.
  final String? printerName;
  final PrinterPaperWidth paperWidth;

  const PrinterConfig({
    this.printerName,
    this.paperWidth = PrinterPaperWidth.mm80,
  });

  PrinterConfig copyWith({
    String? printerName,
    PrinterPaperWidth? paperWidth,
  }) {
    return PrinterConfig(
      printerName: printerName ?? this.printerName,
      paperWidth: paperWidth ?? this.paperWidth,
    );
  }
}
