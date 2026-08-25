/// Limites de tempo (em minutos) usados pra alertar a cozinha sobre pedidos
/// demorando. Hoje são globais (o mesmo limite pra qualquer produto); a
/// ideia é no futuro vir por produto (tempo de preparo específico de cada
/// item vindo do APIL) — esses dois campos são o degrau inicial disso.
class OrderTimingConfig {
  final int alertMinutes;
  final int criticalMinutes;

  const OrderTimingConfig({
    this.alertMinutes = 15,
    this.criticalMinutes = 25,
  });

  OrderTimingConfig copyWith({int? alertMinutes, int? criticalMinutes}) {
    return OrderTimingConfig(
      alertMinutes: alertMinutes ?? this.alertMinutes,
      criticalMinutes: criticalMinutes ?? this.criticalMinutes,
    );
  }
}
