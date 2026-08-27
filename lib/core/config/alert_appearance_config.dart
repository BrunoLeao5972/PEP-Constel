/// Como o alerta visual de pedido atrasado (ver `OrderUrgencyShell`) se
/// comporta — separado de [OrderTimingConfig], que decide QUANDO um pedido
/// vira alerta/crítico. Este aqui decide só a APARÊNCIA disso: se o alerta
/// aparece, se ele pisca, com que força de cor e em que velocidade.
class AlertAppearanceConfig {
  /// Chave-mestra: com `false`, nenhum pedido atrasado destaca — nem o card
  /// pisca, nem o texto do tempo decorrido muda de cor. [animationEnabled],
  /// [colorIntensity] e [speedFactor] ficam sem efeito nesse estado.
  final bool enabled;

  /// Com `false`, o card fica com o destaque de cor FIXO no pico (sem
  /// piscar) em vez de animado — para quem prefere um aviso mais discreto,
  /// ou numa tela onde a animação constante pesa (tablet mais fraco).
  final bool animationEnabled;

  /// Multiplicador sobre a mescla de cor no pico do pisca (que por padrão é
  /// 32% no alerta e 55% no crítico). 1.0 = padrão de fábrica; menor
  /// suaviza, maior intensifica. Sempre limitado a no máximo 1.0 de mescla
  /// (cor sólida) na hora de aplicar — ver `OrderUrgencyShell`.
  final double colorIntensity;

  /// Multiplicador sobre a velocidade do pisca. 1.0 = padrão (1000ms no
  /// alerta, 550ms no crítico); 2.0 pisca no dobro da velocidade (metade da
  /// duração), 0.5 pisca na metade da velocidade.
  final double speedFactor;

  static const minColorIntensity = 0.3;
  static const maxColorIntensity = 1.5;
  static const minSpeedFactor = 0.4;
  static const maxSpeedFactor = 2.5;

  const AlertAppearanceConfig({
    this.enabled = true,
    this.animationEnabled = true,
    this.colorIntensity = 1.0,
    this.speedFactor = 1.0,
  });

  AlertAppearanceConfig copyWith({
    bool? enabled,
    bool? animationEnabled,
    double? colorIntensity,
    double? speedFactor,
  }) {
    return AlertAppearanceConfig(
      enabled: enabled ?? this.enabled,
      animationEnabled: animationEnabled ?? this.animationEnabled,
      colorIntensity: colorIntensity ?? this.colorIntensity,
      speedFactor: speedFactor ?? this.speedFactor,
    );
  }
}
