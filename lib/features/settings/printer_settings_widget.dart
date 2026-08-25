import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/printer_config.dart';
import '../../core/config/printer_config_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../services/kds_printer_service.dart';

/// Seção de configuração da impressora (a mesma lista de "Impressoras e
/// scanners" do Windows) e largura do papel — pensada pra ser embutida na
/// tela de Configurações, não uma página própria. Não existe campo de
/// velocidade/baud rate: quem cuida disso é o driver que o Windows já usa
/// pra imprimir a página de teste da própria impressora.
class PrinterSettingsWidget extends ConsumerStatefulWidget {
  const PrinterSettingsWidget({super.key});

  @override
  ConsumerState<PrinterSettingsWidget> createState() =>
      _PrinterSettingsWidgetState();
}

class _PrinterSettingsWidgetState extends ConsumerState<PrinterSettingsWidget> {
  final _printerService = KdsPrinterService();
  List<String> _availablePrinters = [];
  bool _printersLoaded = false;
  bool _testing = false;

  void _loadPrinters() {
    if (_printersLoaded) return;
    _printersLoaded = true;
    _availablePrinters = _printerService.getAvailablePrinters();
  }

  void _refreshPrinters() {
    setState(() {
      _availablePrinters = _printerService.getAvailablePrinters();
    });
  }

  Future<void> _testPrint(PrinterConfig config) async {
    setState(() => _testing = true);
    final outcome = await _printerService.printTestTicket(config);
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(outcome.success
            ? 'Impressão de teste enviada.'
            : (outcome.error ?? 'Falha ao imprimir.')),
        backgroundColor: outcome.success
            ? context.colors.successColor
            : context.colors.errorColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(printerConfigProvider);
    _loadPrinters();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Impressora',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(
          'A mesma lista de "Impressoras e scanners" do Windows — se a impressora já '
          'imprime a página de teste do Windows normalmente, ela deve funcionar aqui '
          'também.',
          style:
              TextStyle(color: context.colors.textSecondaryColor, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (_availablePrinters.isEmpty)
          Text(
            'Nenhuma impressora encontrada no Windows.',
            style: TextStyle(color: context.colors.textSecondaryColor),
          )
        else
          Row(
            children: [
              Expanded(
                child: _buildDropdown<String>(
                  value: _availablePrinters.contains(config.printerName)
                      ? config.printerName
                      : null,
                  hint: 'Selecione uma impressora',
                  items: _availablePrinters,
                  labelOf: (name) => name,
                  onChanged: (name) {
                    if (name != null) {
                      ref
                          .read(printerConfigProvider.notifier)
                          .setPrinterName(name);
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Atualizar lista',
                onPressed: _refreshPrinters,
              ),
            ],
          ),
        const SizedBox(height: 12),
        SegmentedButton<PrinterPaperWidth>(
          segments: const [
            ButtonSegment(value: PrinterPaperWidth.mm58, label: Text('58mm')),
            ButtonSegment(value: PrinterPaperWidth.mm80, label: Text('80mm')),
          ],
          selected: {config.paperWidth},
          onSelectionChanged: (selection) => ref
              .read(printerConfigProvider.notifier)
              .setPaperWidth(selection.first),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _testing ? null : () => _testPrint(config),
            icon: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined),
            label: const Text('Testar Impressão'),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required T? value,
    String? hint,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: context.colors.backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: hint == null ? null : Text(hint),
          isExpanded: true,
          items: [
            for (final item in items)
              DropdownMenuItem(
                  value: item,
                  child: Text(labelOf(item), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
