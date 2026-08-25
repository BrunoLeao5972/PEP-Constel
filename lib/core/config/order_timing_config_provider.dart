import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'order_timing_config.dart';

const _prefAlertMinutes = 'order_timing_alert_minutes';
const _prefCriticalMinutes = 'order_timing_critical_minutes';

class OrderTimingConfigNotifier extends StateNotifier<OrderTimingConfig> {
  OrderTimingConfigNotifier() : super(const OrderTimingConfig()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = OrderTimingConfig(
      alertMinutes: prefs.getInt(_prefAlertMinutes) ?? state.alertMinutes,
      criticalMinutes:
          prefs.getInt(_prefCriticalMinutes) ?? state.criticalMinutes,
    );
  }

  Future<void> setAlertMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefAlertMinutes, minutes);
    state = state.copyWith(alertMinutes: minutes);
  }

  Future<void> setCriticalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefCriticalMinutes, minutes);
    state = state.copyWith(criticalMinutes: minutes);
  }
}

final orderTimingConfigProvider =
    StateNotifierProvider<OrderTimingConfigNotifier, OrderTimingConfig>((ref) {
  return OrderTimingConfigNotifier();
});
