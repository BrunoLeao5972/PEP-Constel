import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/data/mongo_error.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../settings/presentation/pages/settings_page.dart';
import '../../domain/entities/kds_user.dart';
import '../providers/auth_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _credencialController = TextEditingController();
  final _senhaController = TextEditingController();
  final _credencialFocusNode = FocusNode();
  final _senhaFocusNode = FocusNode();
  // Sem isso, clicar no ícone de mostrar/ocultar senha rouba o foco do campo
  // (no desktop, clicar com o mouse em qualquer botão focável já move o
  // foco do teclado pra ele) — quem continuasse digitando depois de clicar
  // no ícone via mouse tinha as teclas "engolidas" pelo botão, parecendo
  // que o teclado travou.
  final _obscureButtonFocusNode =
      FocusNode(canRequestFocus: false, skipTraversal: true);
  bool _obscure = true;
  bool _saveCredentials = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    // DIAG temporário — remover depois de descobrir a causa do bug de teclado.
    _credencialFocusNode.addListener(() {
      debugPrint('[DIAG] usuario focus: ${_credencialFocusNode.hasFocus}');
    });
    _senhaFocusNode.addListener(() {
      debugPrint('[DIAG] senha focus: ${_senhaFocusNode.hasFocus}');
    });
  }

  Future<void> _loadSavedCredentials() async {
    final saved = await loadSavedCredentials();
    if (saved == null || !mounted) return;
    // Se o usuário já começou a digitar antes dessa leitura assíncrona
    // terminar, não sobrescreve o que ele já digitou.
    if (_credencialController.text.isNotEmpty ||
        _senhaController.text.isNotEmpty) {
      return;
    }
    setState(() {
      _credencialController.text = saved.credencial;
      _senhaController.text = saved.senha;
      _saveCredentials = true;
    });
  }

  @override
  void dispose() {
    _credencialController.dispose();
    _senhaController.dispose();
    _credencialFocusNode.dispose();
    _senhaFocusNode.dispose();
    _obscureButtonFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final credencial = _credencialController.text.trim();
    final senha = _senhaController.text;
    if (credencial.isEmpty || senha.isEmpty) return;
    ref.read(authControllerProvider.notifier).login(
          credencial,
          senha,
          saveCredentials: _saveCredentials,
        );
  }

  void _goToConnectionSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => const SettingsPage(connectionOnly: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Falha de CONEXÃO (servidor configurado não responde) leva direto pra
    // Configurações, sem exigir que o usuário perceba o erro e ache o botão
    // sozinho — senha errada continua só mostrando o erro aqui embaixo.
    ref.listen<AsyncValue<KdsUser?>>(authControllerProvider, (previous, next) {
      if (next.error is ServerUnreachableException) {
        _goToConnectionSettings();
      }
    });

    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      backgroundColor: context.colors.backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome,
                      color: context.colors.accentColor, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'PEP Constel',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 28,
                        color: context.colors.textColor),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _credencialController,
                    focusNode: _credencialFocusNode,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Usuário',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    onChanged: (v) =>
                        debugPrint('[DIAG] usuario onChanged: "$v"'),
                    onSubmitted: (_) => _senhaFocusNode.requestFocus(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _senhaController,
                    focusNode: _senhaFocusNode,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        focusNode: _obscureButtonFocusNode,
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onChanged: (v) =>
                        debugPrint('[DIAG] senha onChanged: "$v"'),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: _saveCredentials,
                        onChanged: (value) =>
                            setState(() => _saveCredentials = value ?? false),
                      ),
                      GestureDetector(
                        onTap: () => setState(
                            () => _saveCredentials = !_saveCredentials),
                        child: Text('Salvar dados de login',
                            style: TextStyle(
                                color: context.colors.textSecondaryColor)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (authState.hasError)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        authState.error.toString(),
                        style: TextStyle(color: context.colors.errorColor),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Entrar'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _goToConnectionSettings,
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text('Configurar Conexão'),
                      style: TextButton.styleFrom(
                          foregroundColor: context.colors.textSecondaryColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
