import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'customer_facing_theme_config.dart';

/// Uma chave só, com o JSON inteiro da personalização — e não uma chave por
/// cor. São nove cores + o raio da borda; com chave separada, acrescentar um
/// campo novo no futuro significaria mexer em quatro lugares (constante,
/// leitura, escrita, reset) e conviver com aparelhos onde metade das chaves
/// existe e a outra metade não.
const _prefCustomerFacingTheme = 'customer_facing_theme';

/// Personalização do Painel Chamador (cores, ícones e cards), persistida no
/// aparelho — igual no Windows e no Android.
///
/// O estado é atualizado **antes** de gravar no disco de propósito: é o que
/// faz o preview das Configurações e o próprio Painel mudarem no mesmo frame
/// do toque, sem esperar o `SharedPreferences`. Se a gravação falhar, a cor
/// escolhida continua valendo nesta sessão (e o app avisa no log) em vez de
/// voltar sozinha na cara do usuário.
class CustomerFacingThemeConfigNotifier
    extends StateNotifier<CustomerFacingThemeConfig> {
  CustomerFacingThemeConfigNotifier()
      : super(const CustomerFacingThemeConfig()) {
    ready = _load();
  }

  /// Resolve quando a personalização salva já foi lida para a memória. O
  /// construtor não pode ser `async`, então quem precisa ter certeza de estar
  /// olhando a configuração real (e não o padrão de fábrica) espera por isto
  /// — mesmo padrão de `MongoConfigNotifier.ready`.
  late final Future<void> ready;

  /// Gravação adiada de um valor que ainda está sendo arrastado (ver
  /// [setColorLive]).
  Timer? _pendingWrite;

  @override
  void dispose() {
    // Se a tela foi fechada no meio de um arrasto, grava o que já estava no
    // estado em vez de simplesmente descartar o timer — o usuário viu a cor
    // aplicada, ela não pode sumir por causa de quando ele saiu da tela.
    if (_pendingWrite != null) {
      _pendingWrite!.cancel();
      _pendingWrite = null;
      unawaited(_write(state));
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefCustomerFacingTheme);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;

      state = CustomerFacingThemeConfig.fromJson(decoded);
    } catch (error) {
      // JSON corrompido, chave gravada por outra versão do app, prefs
      // indisponível: o Painel é a tela que o CLIENTE vê, então ela nunca
      // pode deixar de abrir por causa de uma cor salva errada — fica no
      // padrão do tema, que é sempre legível.
      debugPrint('[PainelChamador] personalização ignorada: $error');
    }
  }

  /// Aplica [color] em [slot]. `null` devolve aquele campo para o padrão do
  /// tema.
  Future<void> setColor(CustomerFacingColorSlot slot, Color? color) {
    return _persist(state.withColor(slot, color));
  }

  /// Versão de [setColor] para valor que está mudando continuamente — os
  /// sliders R/G/B/A do ajuste fino disparam a cada pixel de arrasto.
  ///
  /// A cor entra no estado **na hora** (o preview e o Painel têm que
  /// acompanhar o dedo), mas a gravação em disco é adiada: sem isso, um
  /// arrasto de ponta a ponta viraria centenas de `jsonEncode` +
  /// `SharedPreferences.setString` em sequência, que é exatamente o tipo de
  /// trabalho que engasga o arrasto num tablet Android. Quem solta o slider
  /// chama [setColor] e grava na hora; o timer aqui é só a rede de segurança
  /// para um arrasto que termine sem esse aviso.
  void setColorLive(CustomerFacingColorSlot slot, Color? color) {
    final next = state.withColor(slot, color);
    if (next == state) return;
    state = next;

    _pendingWrite?.cancel();
    _pendingWrite = Timer(const Duration(milliseconds: 400), () {
      _pendingWrite = null;
      _write(state);
    });
  }

  Future<void> setCardBorderRadius(double radius) {
    return _persist(state.withCardBorderRadius(radius));
  }

  /// Volta tudo ao padrão de fábrica — apaga a chave em vez de gravar um
  /// JSON "vazio", para o aparelho ficar exatamente como antes de alguém
  /// personalizar qualquer coisa.
  Future<void> restoreDefaults() {
    return _persist(const CustomerFacingThemeConfig());
  }

  Future<void> _persist(CustomerFacingThemeConfig config) async {
    if (config != state) state = config;

    // Uma gravação imediata torna sem efeito a que estava agendada — e a
    // gravação acontece mesmo quando o estado já era esse, porque é
    // exatamente o caso de soltar o slider no fim de um arrasto: o valor já
    // está na tela, só falta ele chegar ao disco.
    _pendingWrite?.cancel();
    _pendingWrite = null;
    await _write(config);
  }

  Future<void> _write(CustomerFacingThemeConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (config.isDefault) {
        await prefs.remove(_prefCustomerFacingTheme);
      } else {
        await prefs.setString(
            _prefCustomerFacingTheme, jsonEncode(config.toJson()));
      }
    } catch (error) {
      debugPrint('[PainelChamador] não foi possível salvar a cor: $error');
    }
  }
}

/// Quem desenha o Painel lê este provider e chama
/// [CustomerFacingThemeConfig.resolve] com a paleta do tema ativo
/// (`context.colors`) — nunca lê `context.colors` direto para uma cor
/// personalizável, senão o preview das Configurações e a tela real divergem.
final customerFacingThemeConfigProvider = StateNotifierProvider<
    CustomerFacingThemeConfigNotifier, CustomerFacingThemeConfig>((ref) {
  return CustomerFacingThemeConfigNotifier();
});
