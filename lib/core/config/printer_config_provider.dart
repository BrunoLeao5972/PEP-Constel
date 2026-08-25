import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'printer_config.dart';

const _prefPrinterName = 'printer_name';
const _prefPaperWidth = 'printer_paper_width';

class PrinterConfigNotifier extends StateNotifier<PrinterConfig> {
  PrinterConfigNotifier() : super(const PrinterConfig()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final paperWidthName = prefs.getString(_prefPaperWidth);
    state = PrinterConfig(
      printerName: prefs.getString(_prefPrinterName) ?? state.printerName,
      paperWidth: PrinterPaperWidth.values.firstWhere(
        (w) => w.name == paperWidthName,
        orElse: () => state.paperWidth,
      ),
    );
  }

  Future<void> setPrinterName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPrinterName, name);
    state = state.copyWith(printerName: name);
  }

  Future<void> setPaperWidth(PrinterPaperWidth width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPaperWidth, width.name);
    state = state.copyWith(paperWidth: width);
  }
}

final printerConfigProvider =
    StateNotifierProvider<PrinterConfigNotifier, PrinterConfig>((ref) {
  return PrinterConfigNotifier();
});
