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
import '../theme/settings_tokens.dart';
import '../widgets/customer_facing_theme_section.dart';
import '../widgets/settings_section_card.dart';

class SettingsPage extends ConsumerStatefulWidget {
  /// Quando true, mostra só a conexão com o banco (Host/Porta/Banco) e volta
  /// para a tela anterior ao salvar — usado no fluxo de pré-login.
  final bool connectionOnly;

  const SettingsPage({super.key, this.connectionOnly = false});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
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
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  /// Salva o número inicial do chamador — o único campo digitado da aba
  /// "Modalidades & KDS".
  ///
  /// Antes existia um botão só, no fim da página, salvando este campo E os
  /// tempos de alerta juntos. Com as configurações separadas em abas, um
  /// botão que salva campos de outra aba (que a pessoa nem está vendo) seria
  /// impossível de entender — agora cada aba salva o que mostra.
  Future<void> _saveCallerSettings() async {
    final ok = await _applyStartNumber();
    _showSaveOutcome(ok, invalidFields: const ['número inicial do chamador']);
  }

  /// Salva os dois tempos de alerta da aba "Impressora & Alertas".
  Future<void> _saveTimingSettings() async {
    final invalidFields = <String>[];
    if (!await _applyAlertMinutes()) invalidFields.add('tempo de alerta');
    if (!await _applyCriticalMinutes()) invalidFields.add('tempo crítico');
    _showSaveOutcome(invalidFields.isEmpty, invalidFields: invalidFields);
  }

  void _showSaveOutcome(bool saved, {required List<String> invalidFields}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved
            ? 'Configurações salvas.'
            : 'Valor inválido em: ${invalidFields.join(', ')}. '
                'Ajuste e salve novamente.'),
        backgroundColor:
            saved ? context.colors.successColor : context.colors.errorColor,
      ),
    );
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
    // Os dois controllers abaixo são inicializados mesmo no modo
    // connectionOnly (que nem mostra esses campos): `dispose` descarta todos
    // sem perguntar, e um `late final` nunca inicializado explodiria ali.
    _initCallerControllers(ref.watch(orderCallerConfigProvider));
    _initTimingControllers(ref.watch(orderTimingConfigProvider));

    final tokens = SettingsTokens.of(context);

    return Theme(
      // Um Theme só, na raiz da tela, dá a cara nova a TODO campo, botão,
      // switch e segmented daqui pra dentro — inclusive aos widgets que não
      // sabem que estão em Configurações (impressora, personalização do
      // Painel). É o que impede um campo novo de nascer com o estilo antigo
      // por esquecimento.
      data: tokens.applyTo(Theme.of(context)),
      child: Scaffold(
        backgroundColor: tokens.pageBackground,
        body: widget.connectionOnly
            ? _buildConnectionOnly(context, tokens)
            : _buildTabbedLayout(context, tokens),
      ),
    );
  }

  /// Fluxo de pré-login: só a conexão, em coluna estreita e sem abas — as
  /// outras configurações não fazem sentido antes de existir um banco.
  Widget _buildConnectionOnly(BuildContext context, SettingsTokens tokens) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Conexão com o banco',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Aponte este aparelho para o computador que roda o banco do PDV.',
                style: TextStyle(color: tokens.secondaryText, fontSize: 13),
              ),
              const SizedBox(height: 20),
              _buildStatusBanner(
                  context,
                  _testResult ?? ref.watch(mongoDbProvider),
                  ref.watch(mongoConfigProvider)),
              const SizedBox(height: SettingsTokens.cardSpacing),
              _buildAutoDetectCard(context, tokens),
              const SizedBox(height: SettingsTokens.cardSpacing),
              _buildManualConnectionCard(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabbedLayout(BuildContext context, SettingsTokens tokens) {
    return Column(
      children: [
        _buildHeader(context, tokens),
        Expanded(
          // TabBarView já traz a transição deslizante entre abas (e o gesto
          // de arrastar no tablet) sem nenhum AnimatedSwitcher por fora.
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildScrollableTab(_buildConnectionTab(context, tokens)),
              _buildScrollableTab(_buildKdsTab(context, tokens)),
              _buildScrollableTab(_buildPrinterTab(context, tokens)),
              _buildPanelTab(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, SettingsTokens tokens) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.cardBackground,
        border: Border(bottom: BorderSide(color: tokens.cardBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      child: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: SettingsTokens.maxContentWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configurações',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                'Tudo que este aparelho precisa saber para conversar com o PDV, '
                'com a cozinha e com o cliente.',
                style: TextStyle(color: tokens.secondaryText, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                // Rolável e alinhada à esquerda: no celular os quatro rótulos
                // não cabem lado a lado, e espremê-los cortaria as palavras.
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: tokens.primaryAction,
                indicatorWeight: 2.5,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: context.colors.textColor,
                unselectedLabelColor: tokens.secondaryText,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13.5),
                unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13.5),
                dividerColor: const Color(0x00000000),
                tabs: const [
                  _tabConexao,
                  _tabModalidades,
                  _tabImpressora,
                  _tabPersonalizacao,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableTab(Widget content) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      child: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: SettingsTokens.maxContentWidth),
          child: content,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Aba 1 — Conexão & Banco
  // ---------------------------------------------------------------------

  Widget _buildConnectionTab(BuildContext context, SettingsTokens tokens) {
    final config = ref.watch(mongoConfigProvider);
    final dbStatus = ref.watch(mongoDbProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // O estado da conexão fica fora dos cards e ocupando a largura toda:
        // é o primeiro (às vezes o único) dado que alguém vem procurar aqui.
        _buildStatusBanner(context, _testResult ?? dbStatus, config),
        const SizedBox(height: SettingsTokens.cardSpacing),
        SettingsCardGrid(
          children: [
            _buildAutoDetectCard(context, tokens),
            _buildManualConnectionCard(context),
          ],
        ),
      ],
    );
  }

  Widget _buildAutoDetectCard(BuildContext context, SettingsTokens tokens) {
    return SettingsSectionCard(
      icon: Icons.wifi_find,
      title: 'Detecção automática',
      subtitle: 'Varre a rede local atrás do computador que roda o banco do '
          'PDV. É o caminho normal — só use a configuração manual se o '
          'servidor tiver IP fixo ou a busca não achar nada.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _scanning ? null : () => _discoverServer(),
            icon: _scanning
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: tokens.onPrimaryAction),
                  )
                : const Icon(Icons.wifi_find),
            label: Text(
              _scanning
                  ? 'Procurando na rede... ($_scanChecked/$_scanTotal)'
                  : 'Detectar Servidor na Rede',
            ),
          ),
          if (_scanMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              _scanMessage!,
              style: TextStyle(color: tokens.secondaryText, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildManualConnectionCard(BuildContext context) {
    return SettingsSectionCard(
      icon: Icons.settings_ethernet,
      title: 'Endereço do servidor',
      subtitle: 'Porta e banco já vêm preenchidos com o padrão do APIL; '
          'normalmente só o Host muda de instalação para instalação.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _hostController,
            decoration: const InputDecoration(
              labelText: 'Host',
              hintText: '192.168.0.10',
            ),
          ),
          const SizedBox(height: 14),
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
                padding: const EdgeInsets.only(top: 18),
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
          const SizedBox(height: 14),
          TextField(
            controller: _databaseController,
            enabled: false,
            decoration: const InputDecoration(labelText: 'Banco'),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _testingConnection ? null : _testConnection,
                  child: _testingConnection
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Testar Conexão'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _save,
                  child: const Text('Salvar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Aba 2 — Modalidades & Exibição KDS
  // ---------------------------------------------------------------------

  Widget _buildKdsTab(BuildContext context, SettingsTokens tokens) {
    final modalities = ref.watch(serviceModalitiesConfigProvider);
    final panelDisplay = ref.watch(panelDisplayConfigProvider);
    final callerConfig = ref.watch(orderCallerConfigProvider);

    return SettingsCardGrid(
      children: [
        SettingsSectionCard(
          icon: Icons.storefront_outlined,
          title: 'Modalidades de Atendimento',
          subtitle:
              'Quais formas de atendimento este estabelecimento usa. Desligar '
              'uma some com ela do app inteiro.',
          child: Column(
            children: [
              _buildModalitySwitch(context,
                  label: 'Balcão',
                  value: modalities.balcaoEnabled,
                  onChanged: _setBalcaoEnabled),
              _buildModalitySwitch(context,
                  label: 'Mesa',
                  value: modalities.mesaEnabled,
                  onChanged: _setMesaEnabled),
              _buildModalitySwitch(context,
                  label: 'Cartão',
                  value: modalities.cartaoEnabled,
                  onChanged: _setCartaoEnabled),
            ],
          ),
        ),
        SettingsSectionCard(
          icon: Icons.tv_outlined,
          title: 'Exibição do Painel',
          subtitle: 'Quais modalidades aparecem na tela que o cliente vê. '
              'Independente das habilitadas acima: dá para atender em mesa e '
              'ainda assim não chamar mesa no painel.',
          child: Column(
            children: [
              _buildModalitySwitch(context,
                  label: 'Balcão',
                  value: panelDisplay.showBalcao,
                  onChanged: _setPanelShowBalcao),
              _buildModalitySwitch(context,
                  label: 'Mesa',
                  value: panelDisplay.showMesa,
                  onChanged: _setPanelShowMesa),
              _buildModalitySwitch(context,
                  label: 'Cartão',
                  value: panelDisplay.showCartao,
                  onChanged: _setPanelShowCartao),
            ],
          ),
        ),
        SettingsSectionCard(
          icon: Icons.confirmation_number_outlined,
          title: 'Chamador de Pedidos',
          subtitle: 'De onde sai o número que o cliente vê no painel: o '
              'localizador que o PDV já imprime, ou uma senha própria do KDS.',
          child: _buildCallerControls(context, tokens, callerConfig),
        ),
      ],
    );
  }

  Widget _buildCallerControls(
    BuildContext context,
    SettingsTokens tokens,
    OrderCallerConfig callerConfig,
  ) {
    final kdsNextNumber = ref.watch(kdsNextCallNumberProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          showSelectedIcon: false,
          onSelectionChanged: (selection) => _setCallerSource(selection.first),
        ),
        if (callerConfig.source == CallerNumberingSource.kds) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: tokens.inputFill,
              borderRadius: BorderRadius.circular(SettingsTokens.inputRadius),
              border: Border.all(color: tokens.cardBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.confirmation_number_outlined,
                    size: 18, color: tokens.secondaryText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sequência: ${kdsNextNumber.toString().padLeft(2, '0')}',
                    style: TextStyle(
                        color: tokens.secondaryText,
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
            decoration: const InputDecoration(labelText: 'Começar a partir de'),
          ),
          const SizedBox(height: 6),
          _buildModalitySwitch(
            context,
            label: 'Zerar diariamente',
            hint: 'Recomeça a sequência na virada do dia.',
            value: callerConfig.resetDaily,
            onChanged: _setCallerResetDaily,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _saveCallerSettings,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Salvar numeração'),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Aba 3 — Impressora & Alertas
  // ---------------------------------------------------------------------

  Widget _buildPrinterTab(BuildContext context, SettingsTokens tokens) {
    return SettingsCardGrid(
      children: [
        SettingsSectionCard(
          icon: Icons.print_outlined,
          title: 'Impressora',
          subtitle: Platform.isWindows
              ? 'A mesma lista de "Impressoras e scanners" do Windows — se a '
                  'impressora já imprime a página de teste do Windows, ela '
                  'funciona aqui também.'
              : 'A impressão sai pelo computador com Windows que estiver na '
                  'mesma rede.',
          child: Platform.isWindows
              ? const PrinterSettingsWidget()
              : Text(
                  'Este aparelho não imprime direto: os pedidos de reimpressão '
                  'entram numa fila e são impressos pelo PC com a impressora '
                  'conectada. Configure a impressora naquele computador.',
                  style: TextStyle(color: tokens.secondaryText, fontSize: 13),
                ),
        ),
        SettingsSectionCard(
          icon: Icons.timer_outlined,
          title: 'Alertas de Tempo',
          subtitle: 'Quando um pedido passa desses tempos, o card pisca na '
              'Cozinha para chamar atenção. Hoje é o mesmo limite para '
              'qualquer produto — no futuro isso deve vir por produto.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _alertMinutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tempo de alerta (min)',
                  suffixText: 'min',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _criticalMinutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tempo crítico (min)',
                  suffixText: 'min',
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _saveTimingSettings,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Salvar tempos'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Aba 4 — Personalização do Painel
  // ---------------------------------------------------------------------

  /// Única aba sem scroll por fora: a personalização divide a tela em
  /// controles (que rolam) e preview (que fica parado), e um scroll externo
  /// levaria o preview embora justamente quando a pessoa desce até a cor que
  /// quer mudar.
  Widget _buildPanelTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: SettingsTokens.maxContentWidth),
          child: const SizedBox(
            height: double.infinity,
            child: CustomerFacingThemeSection(),
          ),
        ),
      ),
    );
  }

  Widget _buildModalitySwitch(
    BuildContext context, {
    required String label,
    String? hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final tokens = SettingsTokens.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (hint != null)
                  Text(
                    hint,
                    style:
                        TextStyle(fontSize: 11.5, color: tokens.secondaryText),
                  ),
              ],
            ),
          ),
          // Escala reduzida: o switch do Material 3 em tamanho cheio, seis
          // vezes na mesma tela, vira o elemento mais pesado da interface —
          // e ele é o controle mais simples que existe aqui.
          Transform.scale(
            scale: 0.8,
            alignment: Alignment.centerRight,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
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

/// As quatro abas do topo. Ícone e rótulo lado a lado (o `Tab` padrão empilha
/// os dois e dobra a altura da barra), fora do `build` porque não mudam.
const _tabConexao = Tab(
  height: 46,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.dns_outlined, size: 17),
      SizedBox(width: 8),
      Text('Conexão & Banco'),
    ],
  ),
);

const _tabModalidades = Tab(
  height: 46,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.tune_rounded, size: 17),
      SizedBox(width: 8),
      Text('Modalidades & KDS'),
    ],
  ),
);

const _tabImpressora = Tab(
  height: 46,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.print_outlined, size: 17),
      SizedBox(width: 8),
      Text('Impressora & Alertas'),
    ],
  ),
);

const _tabPersonalizacao = Tab(
  height: 46,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.palette_outlined, size: 17),
      SizedBox(width: 8),
      Text('Personalização do Painel'),
    ],
  ),
);
