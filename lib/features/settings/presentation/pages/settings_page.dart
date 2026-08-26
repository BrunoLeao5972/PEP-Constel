import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mongo_dart/mongo_dart.dart' show Db;
import '../../../../core/config/mongo_config.dart';
import '../../../../core/config/mongo_config_provider.dart';
import '../../../../core/config/order_caller_config.dart';
import '../../../../core/config/order_caller_config_provider.dart';
import '../../../../core/config/order_timing_config.dart';
import '../../../../core/config/order_timing_config_provider.dart';
import '../../../../core/config/panel_display_config_provider.dart';
import '../../../../core/config/service_modalities_config_provider.dart';
import '../../../../core/data/mongo_discovery.dart';
import '../../../../core/data/mongo_error.dart';
import '../../../../core/data/mongo_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../orders/presentation/providers/order_caller_provider.dart';
import '../../printer_settings_widget.dart';
import '../widgets/customer_facing_theme_section.dart';

class SettingsPage extends ConsumerStatefulWidget {
  /// Quando true, mostra só a conexão com o banco (Host/Porta/Banco) e volta
  /// para a tela anterior ao salvar — usado no fluxo de pré-login.
  final bool connectionOnly;

  const SettingsPage({super.key, this.connectionOnly = false});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _databaseController;
  late final TextEditingController _startNumberController;
  late final TextEditingController _alertMinutesController;
  late final TextEditingController _criticalMinutesController;
  bool _initialized = false;
  bool _callerInitialized = false;
  bool _timingInitialized = false;
  bool _portEditable = false;
  bool _testingConnection = false;
  AsyncValue<void>? _testResult;

  bool _scanning = false;
  int _scanChecked = 0;
  int _scanTotal = 0;
  String? _scanMessage;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _databaseController.dispose();
    _startNumberController.dispose();
    _alertMinutesController.dispose();
    _criticalMinutesController.dispose();
    super.dispose();
  }

  void _initControllers(MongoConfig config) {
    if (_initialized) return;
    _hostController = TextEditingController(text: config.host);
    _portController = TextEditingController(text: config.port.toString());
    _databaseController = TextEditingController(text: config.database);
    _initialized = true;

    // Host ainda no padrão de fábrica = ninguém configurou nada nesse
    // aparelho ainda. Dispara a busca sozinha, sem exigir nem um toque do
    // cliente — é exatamente a instalação "abriu o app e já funcionou".
    if (config.host == const MongoConfig().host) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _discoverServer(silent: true));
    }
  }

  Future<void> _discoverServer({bool silent = false}) async {
    final port = int.tryParse(_portController.text.trim()) ?? 27017;
    final database = _databaseController.text.trim();

    setState(() {
      _scanning = true;
      _scanChecked = 0;
      _scanTotal = 0;
      _scanMessage = null;
    });

    final results = await discoverMongoServers(
      port: port,
      database: database,
      onProgress: (checked, total) {
        if (!mounted) return;
        setState(() {
          _scanChecked = checked;
          _scanTotal = total;
        });
      },
    );

    if (!mounted) return;
    setState(() => _scanning = false);

    if (results.isEmpty) {
      setState(() {
        _scanMessage = silent
            ? null // busca automática silenciosa: se não achou, só deixa o campo de Host em branco pro cliente configurar manualmente, sem assustar com um erro na primeira tela.
            : 'Nenhum servidor encontrado nessa rede. Verifique se o computador com o MongoDB '
                'está ligado e conectado à mesma rede Wi-Fi, ou digite o endereço manualmente abaixo.';
      });
      return;
    }

    if (results.length == 1) {
      await _applyDiscovered(results.first);
      return;
    }

    // Mais de um servidor Mongo na rede (ex: duas máquinas de teste) — deixa
    // o usuário escolher em vez de adivinhar.
    if (!mounted) return;
    final chosen = await showDialog<DiscoveredServer>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: dialogContext.colors.cardColor,
        title: const Text('Mais de um servidor encontrado'),
        children: [
          for (final server in results)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(server),
              child: Row(
                children: [
                  Icon(
                    server.looksLikeApil
                        ? Icons.check_circle
                        : Icons.dns_outlined,
                    size: 18,
                    color: server.looksLikeApil
                        ? dialogContext.colors.successColor
                        : dialogContext.colors.textSecondaryColor,
                  ),
                  const SizedBox(width: 10),
                  Text(server.host),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen != null) {
      await _applyDiscovered(chosen);
    }
  }

  Future<void> _applyDiscovered(DiscoveredServer server) async {
    _hostController.text = server.host;
    _portController.text = server.port.toString();
    await _persistConfig(
        host: server.host, port: server.port, showSnackbar: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Servidor encontrado em ${server.host} — conectado automaticamente.'),
        backgroundColor: context.colors.successColor,
      ),
    );

    if (widget.connectionOnly) {
      // Dá um tempo pro usuário ler a mensagem antes de voltar sozinho pro
      // login — sem isso a tela troca rápido demais e parece que não
      // aconteceu nada.
      await Future.delayed(const Duration(milliseconds: 1100));
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  void _initCallerControllers(OrderCallerConfig config) {
    if (_callerInitialized) return;
    _startNumberController =
        TextEditingController(text: config.startNumber.toString());
    _callerInitialized = true;
  }

  void _initTimingControllers(OrderTimingConfig config) {
    if (_timingInitialized) return;
    _alertMinutesController =
        TextEditingController(text: config.alertMinutes.toString());
    _criticalMinutesController =
        TextEditingController(text: config.criticalMinutes.toString());
    _timingInitialized = true;
  }

  Future<void> _setBalcaoEnabled(bool value) {
    return ref
        .read(serviceModalitiesConfigProvider.notifier)
        .setBalcaoEnabled(value);
  }

  Future<void> _setMesaEnabled(bool value) {
    return ref
        .read(serviceModalitiesConfigProvider.notifier)
        .setMesaEnabled(value);
  }

  Future<void> _setCartaoEnabled(bool value) {
    return ref
        .read(serviceModalitiesConfigProvider.notifier)
        .setCartaoEnabled(value);
  }

  Future<void> _setPanelShowBalcao(bool value) {
    return ref.read(panelDisplayConfigProvider.notifier).setShowBalcao(value);
  }

  Future<void> _setPanelShowMesa(bool value) {
    return ref.read(panelDisplayConfigProvider.notifier).setShowMesa(value);
  }

  Future<void> _setPanelShowCartao(bool value) {
    return ref.read(panelDisplayConfigProvider.notifier).setShowCartao(value);
  }

  Future<void> _setCallerSource(CallerNumberingSource source) {
    return ref.read(orderCallerConfigProvider.notifier).setSource(source);
  }

  Future<void> _setCallerResetDaily(bool value) {
    return ref.read(orderCallerConfigProvider.notifier).setResetDaily(value);
  }

  void _resetSequenceNow() {
    ref.read(orderCallLabelsProvider.notifier).resetSequenceNow();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Sequência do KDS zerada.'),
        backgroundColor: context.colors.successColor,
      ),
    );
  }

  // As três validações abaixo retornam sucesso/falha em vez de mostrar sua
  // própria SnackBar — quem informa o resultado ao usuário é sempre
  // _saveKdsSettings, que roda todas de uma vez a partir do botão único de
  // salvar (ver build()).
  Future<bool> _applyStartNumber() async {
    final value = int.tryParse(_startNumberController.text.trim());
    if (value == null || value < 1) {
      _startNumberController.text =
          ref.read(orderCallerConfigProvider).startNumber.toString();
      return false;
    }
    await ref.read(orderCallerConfigProvider.notifier).setStartNumber(value);
    return true;
  }

  Future<bool> _applyAlertMinutes() async {
    final timing = ref.read(orderTimingConfigProvider);
    final value = int.tryParse(_alertMinutesController.text.trim());
    if (value == null || value < 1 || value >= timing.criticalMinutes) {
      _alertMinutesController.text = timing.alertMinutes.toString();
      return false;
    }
    await ref.read(orderTimingConfigProvider.notifier).setAlertMinutes(value);
    return true;
  }

  Future<bool> _applyCriticalMinutes() async {
    final timing = ref.read(orderTimingConfigProvider);
    final value = int.tryParse(_criticalMinutesController.text.trim());
    if (value == null || value <= timing.alertMinutes) {
      _criticalMinutesController.text = timing.criticalMinutes.toString();
      return false;
    }
    await ref
        .read(orderTimingConfigProvider.notifier)
        .setCriticalMinutes(value);
    return true;
  }

  /// Botão único que salva as configurações do KDS que antes tinham um
  /// "check" próprio (número inicial do chamador, tempo de alerta e tempo
  /// crítico) — não mexe na conexão com o banco, que continua com seu
  /// próprio botão "Salvar".
  Future<void> _saveKdsSettings() async {
    final invalidFields = <String>[];

    if (ref.read(orderCallerConfigProvider).source ==
        CallerNumberingSource.kds) {
      if (!await _applyStartNumber()) {
        invalidFields.add('número inicial do chamador');
      }
    }
    if (!await _applyAlertMinutes()) invalidFields.add('tempo de alerta');
    if (!await _applyCriticalMinutes()) invalidFields.add('tempo crítico');

    if (!mounted) return;
    if (invalidFields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Configurações do KDS salvas.'),
          backgroundColor: context.colors.successColor,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Valor inválido em: ${invalidFields.join(', ')}. Ajuste e salve novamente.'),
          backgroundColor: context.colors.errorColor,
        ),
      );
    }
  }

  Future<void> _persistConfig(
      {String? host, int? port, bool showSnackbar = true}) async {
    final resolvedPort =
        port ?? int.tryParse(_portController.text.trim()) ?? 27017;
    await ref.read(mongoConfigProvider.notifier).update(
          host: host ?? _hostController.text.trim(),
          port: resolvedPort,
          database: _databaseController.text.trim(),
        );
    ref.invalidate(mongoDbProvider);
    if (!mounted) return;
    setState(() => _testResult = null);
    if (showSnackbar) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Configuração salva. Reconectando ao banco local...')),
      );
    }
  }

  Future<void> _save() async {
    await _persistConfig();
    if (!mounted) return;
    if (widget.connectionOnly) {
      Navigator.of(context).pop();
    }
  }

  void _unlockPortEditing() {
    setState(() => _portEditable = true);
  }

  Future<void> _testConnection() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 27017;
    final database = _databaseController.text.trim();

    setState(() {
      _testingConnection = true;
      _testResult = const AsyncValue.loading();
    });
    Db? db;
    try {
      db = await Db.create('mongodb://$host:$port/$database');
      await db.open().timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() => _testResult = const AsyncValue.data(null));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Conexão bem-sucedida!'),
          backgroundColor: context.colors.successColor,
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      // Guarda o erro cru: _buildStatusBanner é quem traduz, pra ter só um
      // lugar fazendo essa tradução (esse mesmo banner também é usado com o
      // erro de mongoDbProvider, que também vem cru).
      setState(() => _testResult = AsyncValue.error(e, st));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyMongoError(e, host: host, port: port)),
          backgroundColor: context.colors.errorColor,
        ),
      );
    } finally {
      await db?.close();
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(mongoConfigProvider);
    _initControllers(config);
    final dbStatus = ref.watch(mongoDbProvider);
    final modalities = ref.watch(serviceModalitiesConfigProvider);
    final callerConfig = ref.watch(orderCallerConfigProvider);
    final panelDisplay = ref.watch(panelDisplayConfigProvider);
    final timingConfig = ref.watch(orderTimingConfigProvider);
    final kdsNextNumber = ref.watch(kdsNextCallNumberProvider);
    _initCallerControllers(callerConfig);
    _initTimingControllers(timingConfig);

    return Scaffold(
      backgroundColor: context.colors.backgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Configurações',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Conexão com o banco local do estabelecimento',
                    style: TextStyle(color: context.colors.textSecondaryColor),
                  ),
                  const SizedBox(height: 24),
                  _buildStatusBanner(context, _testResult ?? dbStatus, config),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _scanning ? null : () => _discoverServer(),
                      icon: _scanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.wifi_find),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _scanning
                              ? 'Procurando na rede... ($_scanChecked/$_scanTotal)'
                              : 'Detectar Servidor na Rede',
                        ),
                      ),
                    ),
                  ),
                  if (_scanMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _scanMessage!,
                      style: TextStyle(
                          color: context.colors.textSecondaryColor,
                          fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                          child: Divider(color: context.colors.borderColor)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'ou configure manualmente',
                          style: TextStyle(
                              color: context.colors.textSecondaryColor,
                              fontSize: 12),
                        ),
                      ),
                      Expanded(
                          child: Divider(color: context.colors.borderColor)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _hostController,
                    decoration: const InputDecoration(labelText: 'Host'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _portController,
                          enabled: _portEditable,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Porta'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: IconButton(
                          icon: Icon(
                              _portEditable
                                  ? Icons.lock_open_outlined
                                  : Icons.edit_outlined,
                              size: 18),
                          tooltip: 'Liberar edição',
                          onPressed: _portEditable ? null : _unlockPortEditing,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _databaseController,
                    enabled: false,
                    decoration: const InputDecoration(labelText: 'Banco'),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _testingConnection ? null : _testConnection,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: _testingConnection
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('Testar Conexão'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _save,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('Salvar'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!widget.connectionOnly) ...[
                    const SizedBox(height: 40),
                    Divider(color: context.colors.borderColor),
                    const SizedBox(height: 24),
                    const Text(
                      'Modalidades de Atendimento',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _buildModalitySwitch(
                      context,
                      label: 'Balcão',
                      value: modalities.balcaoEnabled,
                      onChanged: _setBalcaoEnabled,
                    ),
                    _buildModalitySwitch(
                      context,
                      label: 'Mesa',
                      value: modalities.mesaEnabled,
                      onChanged: _setMesaEnabled,
                    ),
                    _buildModalitySwitch(
                      context,
                      label: 'Cartão',
                      value: modalities.cartaoEnabled,
                      onChanged: _setCartaoEnabled,
                    ),
                    const SizedBox(height: 40),
                    Divider(color: context.colors.borderColor),
                    const SizedBox(height: 24),
                    const Text(
                      'Exibição do Painel',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _buildModalitySwitch(
                      context,
                      label: 'Balcão',
                      value: panelDisplay.showBalcao,
                      onChanged: _setPanelShowBalcao,
                    ),
                    _buildModalitySwitch(
                      context,
                      label: 'Mesa',
                      value: panelDisplay.showMesa,
                      onChanged: _setPanelShowMesa,
                    ),
                    _buildModalitySwitch(
                      context,
                      label: 'Cartão',
                      value: panelDisplay.showCartao,
                      onChanged: _setPanelShowCartao,
                    ),
                    const SizedBox(height: 40),
                    Divider(color: context.colors.borderColor),
                    const SizedBox(height: 24),
                    const Text(
                      'Chamador de Pedidos',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<CallerNumberingSource>(
                      segments: const [
                        ButtonSegment(
                          value: CallerNumberingSource.pdv,
                          label: Text('Numeração do PDV'),
                        ),
                        ButtonSegment(
                          value: CallerNumberingSource.kds,
                          label: Text('KDS controla'),
                        ),
                      ],
                      selected: {callerConfig.source},
                      onSelectionChanged: (selection) =>
                          _setCallerSource(selection.first),
                    ),
                    if (callerConfig.source == CallerNumberingSource.kds) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: context.colors.backgroundColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: context.colors.borderColor),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.confirmation_number_outlined,
                                size: 18,
                                color: context.colors.textSecondaryColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Sequência: ${kdsNextNumber.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                    color: context.colors.textSecondaryColor,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _resetSequenceNow,
                              icon: const Icon(Icons.restart_alt, size: 18),
                              label: const Text('Zerar Agora'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _startNumberController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Começar a partir de'),
                      ),
                      const SizedBox(height: 8),
                      _buildModalitySwitch(
                        context,
                        label: 'Zerar diariamente',
                        value: callerConfig.resetDaily,
                        onChanged: _setCallerResetDaily,
                      ),
                    ],
                    if (Platform.isWindows) ...[
                      const SizedBox(height: 40),
                      Divider(color: context.colors.borderColor),
                      const SizedBox(height: 24),
                      const PrinterSettingsWidget(),
                    ],
                    const SizedBox(height: 40),
                    Divider(color: context.colors.borderColor),
                    const SizedBox(height: 24),
                    const Text(
                      'Alertas de Tempo',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Quando um pedido passa desses tempos, o card pisca na Cozinha pra '
                      'chamar atenção. Hoje é o mesmo limite pra qualquer produto — no futuro '
                      'isso deve vir por produto.',
                      style: TextStyle(
                          color: context.colors.textSecondaryColor,
                          fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _alertMinutesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Tempo de alerta (min)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _criticalMinutesController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Tempo crítico (min)'),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saveKdsSettings,
                        icon: const Icon(Icons.save_outlined),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Salvar'),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!widget.connectionOnly) ...[
              const SizedBox(height: 40),
              // Fora da coluna de 480 px de propósito: esta seção mostra os
              // controles e o preview do Painel lado a lado, e nessa largura
              // eles não caberiam juntos.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1060),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(color: context.colors.borderColor),
                    const SizedBox(height: 24),
                    const CustomerFacingThemeSection(),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModalitySwitch(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeColor: context.colors.accentColor,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildStatusBanner(
      BuildContext context, AsyncValue<Object?> dbStatus, MongoConfig config) {
    late final Color color;
    late final IconData icon;
    late final String text;

    dbStatus.when(
      data: (_) {
        color = context.colors.successColor;
        icon = Icons.check_circle;
        text = 'Conectado ao banco local';
      },
      loading: () {
        color = context.colors.warningColor;
        icon = Icons.sync;
        text = 'Conectando...';
      },
      error: (err, _) {
        color = context.colors.errorColor;
        icon = Icons.error;
        text = friendlyMongoError(err, host: config.host, port: config.port);
      },
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}
