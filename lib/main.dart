import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_themes.dart';
import 'core/config/theme_mode_provider.dart';
import 'core/config/mongo_config_provider.dart';
import 'core/widgets/top_navigation_bar.dart';
import 'core/providers/navigation_provider.dart';
import 'features/orders/presentation/pages/kds_page.dart';
import 'features/admin/presentation/pages/admin_page.dart';
import 'features/orders/presentation/pages/customer_facing_page.dart';
import 'features/settings/presentation/pages/settings_page.dart';
import 'features/auth/presentation/pages/login_page.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'services/print_job_relay_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_BR');

  // Carrega o host/porta salvos ANTES de abrir a primeira tela. O
  // construtor de MongoConfigNotifier não pode ser async, então sem essa
  // espera aqui o primeiríssimo login do app (antes de alguém ter aberto
  // Configurações) podia ler a config ainda no valor padrão (127.0.0.1) e
  // ficar "preso" tentando conectar nele até o timeout, em vez de usar o IP
  // realmente salvo — corrigir isso pelo botão Salvar de Configurações
  // funcionava por coincidência, já que essa tela força o estado certo.
  final container = ProviderContainer();
  await container.read(mongoConfigProvider.notifier).ready;

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const KDSApp(),
    ),
  );
}

class KDSApp extends ConsumerWidget {
  const KDSApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'PEP Constel',
      debugShowCheckedModeBanner: false,
      theme: AppThemes.light,
      darkTheme: AppThemes.dark,
      themeMode: themeMode,
      // MaterialApp já anima a troca de tema sozinho (AnimatedTheme interno,
      // ligado por padrão) — não precisa de nenhum wrapper manual aqui.
      home: const AuthGate(),
    );
  }
}

/// Não tenta restaurar sessão nenhuma na abertura do app — sempre começa
/// deslogado, exigindo login manual. Isso evita qualquer tentativa de
/// conexão automática (e possível travamento) antes do usuário sequer ver a
/// tela; a conexão só é mesmo tentada quando o usuário aperta "Entrar" (ver
/// AuthController.login).
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // valueOrNull (e não .value): um estado de erro no login não pode
    // "vazar" e derrubar este widget com a tela vermelha do Flutter.
    final user = ref.watch(authControllerProvider).valueOrNull;
    if (user == null) {
      return const LoginPage();
    }
    return const MainScaffold();
  }
}

class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  bool _isEdgeHovered = false;
  bool _isSidebarHovered = false;

  bool get _isAutoSidebarVisible => _isEdgeHovered || _isSidebarHovered;

  void _setEdgeHovered(bool value) {
    if (_isEdgeHovered == value) {
      return;
    }
    setState(() {
      _isEdgeHovered = value;
    });
  }

  void _setSidebarHovered(bool value) {
    if (_isSidebarHovered == value) {
      return;
    }
    setState(() {
      _isSidebarHovered = value;
    });
  }

  Widget _buildMainContent(String activeTab) {
    return SafeArea(
      child: IndexedStack(
        index: _tabToIndex(activeTab),
        children: const [
          AdminPage(),
          KDSPage(),
          CustomerFacingPage(),
          SettingsPage(),
        ],
      ),
    );
  }

  static const _narrowBreakpoint = 600.0;

  void _handleTabChanged(String tab) {
    ref.read(navigationProvider.notifier).state = tab;
    if (tab != 'painel') {
      _setEdgeHovered(false);
      _setSidebarHovered(false);
    }
  }

  String _tabTitle(String tab) {
    switch (tab) {
      case 'admin':
        return 'Administrativo';
      case 'cozinha':
        return 'Cozinha';
      case 'painel':
        return 'Painel';
      case 'config':
        return 'Configurações';
      default:
        return 'PEP Constel';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Mantém vivo o processador da fila de impressão remota (pedidos de
    // impressão vindos de tablets Android sem impressora conectada) — só
    // faz alguma coisa no Windows, mas precisa estar sempre "escutando"
    // enquanto o app estiver aberto, não só quando alguém abre uma tela
    // específica.
    ref.watch(printJobRelayProvider);

    final activeTab = ref.watch(navigationProvider);
    final isSidebarCollapsed = ref.watch(sidebarCollapsedProvider);
    final isPainelTab = activeTab == 'painel';
    final sidebarWidth = isSidebarCollapsed ? 88.0 : 290.0;
    final currentUser = ref.watch(authControllerProvider).valueOrNull;
    final isNarrow = MediaQuery.of(context).size.width < _narrowBreakpoint;

    // Em telas estreitas (celular), a barra lateral fixa não cabe: vira uma
    // gaveta (Drawer) aberta pelo AppBar, em vez de ficar sempre visível.
    if (isNarrow) {
      return Scaffold(
        backgroundColor: context.colors.backgroundColor,
        appBar: AppBar(
          title: Text(_tabTitle(activeTab)),
        ),
        drawer: Drawer(
          width: 290,
          backgroundColor: context.colors.cardColor,
          child: TopNavigationBar(
            activeTab: activeTab,
            onTabChanged: (tab) {
              _handleTabChanged(tab);
              Navigator.of(context).pop();
            },
            isCollapsed: false,
            onToggleCollapse: () => Navigator.of(context).pop(),
            userName: currentUser?.nome ?? '',
            onLogout: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ),
        body: _buildMainContent(activeTab),
      );
    }

    final sidebar = TopNavigationBar(
      activeTab: activeTab,
      onTabChanged: _handleTabChanged,
      isCollapsed: isSidebarCollapsed,
      onToggleCollapse: () {
        ref.read(sidebarCollapsedProvider.notifier).state = !isSidebarCollapsed;
      },
      userName: currentUser?.nome ?? '',
      onLogout: () => ref.read(authControllerProvider.notifier).logout(),
    );

    if (!isPainelTab) {
      return Scaffold(
        body: Row(
          children: [
            sidebar,
            Expanded(child: _buildMainContent(activeTab)),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _buildMainContent(activeTab)),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 14,
            child: MouseRegion(
              onEnter: (_) => _setEdgeHovered(true),
              onExit: (_) => _setEdgeHovered(false),
              child: const SizedBox.expand(),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: _isAutoSidebarVisible ? 0 : -sidebarWidth,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              onEnter: (_) => _setSidebarHovered(true),
              onExit: (_) => _setSidebarHovered(false),
              child: SizedBox(
                width: sidebarWidth,
                child: IgnorePointer(
                  ignoring: !_isAutoSidebarVisible,
                  child: sidebar,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _tabToIndex(String tab) {
    switch (tab) {
      case 'admin':
        return 0;
      case 'cozinha':
        return 1;
      case 'painel':
        return 2;
      case 'config':
        return 3;
      default:
        return 1;
    }
  }
}
