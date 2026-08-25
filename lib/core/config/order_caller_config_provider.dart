import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'order_caller_config.dart';

const _prefSource = 'caller_numbering_source';
const _prefResetDaily = 'caller_reset_daily';
const _prefStartNumber = 'caller_start_number';

class OrderCallerConfigNotifier extends StateNotifier<OrderCallerConfig> {
  OrderCallerConfigNotifier() : super(const OrderCallerConfig()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final sourceName = prefs.getString(_prefSource);
    state = OrderCallerConfig(
      source: sourceName == CallerNumberingSource.kds.name
          ? CallerNumberingSource.kds
          : CallerNumberingSource.pdv,
      resetDaily: prefs.getBool(_prefResetDaily) ?? state.resetDaily,
      startNumber: prefs.getInt(_prefStartNumber) ?? state.startNumber,
    );
  }

  Future<void> setSource(CallerNumberingSource source) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefSource, source.name);
    state = state.copyWith(source: source);
  }

  Future<void> setResetDaily(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefResetDaily, value);
    state = state.copyWith(resetDaily: value);
  }

  Future<void> setStartNumber(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefStartNumber, value);
    state = state.copyWith(startNumber: value);
  }
}

final orderCallerConfigProvider =
    StateNotifierProvider<OrderCallerConfigNotifier, OrderCallerConfig>((ref) {
  return OrderCallerConfigNotifier();
});
