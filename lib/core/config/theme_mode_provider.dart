import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefIsLight = 'theme_is_light';

/// Modo claro/escuro do app, persistido no aparelho — a escolha do usuário
/// se mantém entre aberturas, igual à conexão com o servidor.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final isLight = prefs.getBool(_prefIsLight);
    if (isLight != null) {
      state = isLight ? ThemeMode.light : ThemeMode.dark;
    }
  }

  Future<void> toggle() async {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefIsLight, next == ThemeMode.light);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});
