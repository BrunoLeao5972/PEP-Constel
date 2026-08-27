import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_colors.dart';
import '../config/order_timing_config.dart';
import '../config/alert_appearance_config.dart';
import '../config/alert_appearance_config_provider.dart';
import '../../features/orders/domain/entities/order.dart';

enum OrderUrgency { normal, alert, critical }

/// Nível de urgência do pedido a partir dos limites configurados em
/// Configurações → Alertas de Tempo. Pedido já entregue nunca alerta.
OrderUrgency orderUrgencyFor(
    Order order, int elapsedMinutes, OrderTimingConfig timing) {
  if (order.status == OrderStatus.entregue) return OrderUrgency.normal;
  if (elapsedMinutes >= timing.criticalMinutes) return OrderUrgency.critical;
  if (elapsedMinutes >= timing.alertMinutes) return OrderUrgency.alert;
  return OrderUrgency.normal;
}

/// Cor a usar em ícones/texto (ex: o tempo decorrido) que devem refletir a
/// urgência sem piscar — só o preenchimento do card (via [OrderUrgencyShell])
/// pisca.
///
/// [alertsEnabled] é a chave-mestra de Configurações → Alertas de Tempo →
/// Aparência dos Alertas: com ela desligada, nada no app sinaliza atraso por
/// cor, nem aqui nem no card — não faria sentido desligar "os alertas" e o
/// tempo decorrido continuar pintado de vermelho.
Color orderUrgencyColor(BuildContext context, OrderUrgency urgency,
    {required bool alertsEnabled}) {
  if (!alertsEnabled) return context.colors.textSecondaryColor;
  return switch (urgency) {
    OrderUrgency.critical => context.colors.errorColor,
    OrderUrgency.alert => context.colors.warningColor,
    OrderUrgency.normal => context.colors.textSecondaryColor,
  };
}

/// Moldura do card de pedido — o conteúdo (child) é montado uma única vez e
/// não é reconstruído a cada tick da animação (o AnimatedBuilder cuida
/// disso). Fica parada em pedidos normais; quando o pedido cruza o tempo de
/// alerta ou crítico, o CARD INTEIRO destaca em amarelo ou vermelho pra
/// chamar atenção — o crítico é mais forte e mais rápido que o alerta. Usado
/// tanto na Cozinha quanto no Administrativo, pra quem estiver de olho no
/// dashboard também perceber pedidos ativos ficando atrasados.
///
/// Tudo isso é regulável em Configurações → Alertas de Tempo → Aparência dos
/// Alertas ([AlertAppearanceConfig]): dá pra desligar o alerta inteiro, só a
/// animação (o destaque de cor fica fixo no pico em vez de piscar), ou
/// ajustar a intensidade da cor e a velocidade do pisca.
class OrderUrgencyShell extends ConsumerStatefulWidget {
  final OrderUrgency urgency;
  final Widget child;

  const OrderUrgencyShell(
      {super.key, required this.urgency, required this.child});

  @override
  ConsumerState<OrderUrgencyShell> createState() => _OrderUrgencyShellState();
}

class _OrderUrgencyShellState extends ConsumerState<OrderUrgencyShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Se, da última vez que sincronizamos, o controller devia estar rodando.
  /// Comparado a cada `build` pra só chamar `repeat`/`stop` quando esse
  /// estado realmente muda — não a cada rebuild, e não só quando
  /// `widget.urgency` muda: a config de aparência (Configurações) também
  /// pode ligar/desligar o pisca sem a urgência do pedido mudar.
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Ajusta o controller pro estado que este build pede, mexendo o mínimo
  /// possível: `duration` sempre atualiza (barato, e some sozinho no
  /// próximo ciclo do pisca — ver nota abaixo), mas `repeat()`/`stop()` só
  /// quando `animating` muda de valor. Chamar `repeat()` de novo a cada
  /// build reiniciaria a fase do pisca (um "pulo" visual) toda vez que
  /// qualquer outra coisa no card mudasse.
  void _syncController({required bool animating, required Duration duration}) {
    _controller.duration = duration;

    if (animating == _isAnimating) {
      // Duration mudou (ex: slider de velocidade arrastado) enquanto já
      // estava piscando: o ciclo em andamento termina no ritmo antigo — o
      // `repeat()` só relê `duration` quando inicia o próximo ciclo — e o
      // próximo já sai no ritmo novo. Reiniciar aqui pra valer na hora
      // causaria o mesmo pulo visual que estamos evitando.
      return;
    }
    _isAnimating = animating;
    if (animating) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final appearance = ref.watch(alertAppearanceConfigProvider);
    final urgency = widget.urgency;

    if (!appearance.enabled || urgency == OrderUrgency.normal) {
      _syncController(animating: false, duration: _controller.duration!);
      return _shell(
        color: context.colors.backgroundColor,
        borderColor: context.colors.borderColor,
        borderWidth: 1,
        child: widget.child,
      );
    }

    final blinkColor = urgency == OrderUrgency.critical
        ? context.colors.errorColor
        : context.colors.warningColor;

    // Base de fábrica: crítico destaca mais forte e mais rápido que alerta,
    // reforçando a diferença de nível sem precisar de mais nenhum elemento
    // na tela. `colorIntensity`/`speedFactor` escalam essa base a partir da
    // Aparência dos Alertas — 1.0 reproduz exatamente os valores antigos.
    final baseMaxBlend = urgency == OrderUrgency.critical ? 0.55 : 0.32;
    final maxBlend = (baseMaxBlend * appearance.colorIntensity).clamp(0.0, 1.0);
    final baseMillis = urgency == OrderUrgency.critical ? 550 : 1000;
    final duration = Duration(
      milliseconds:
          (baseMillis / appearance.speedFactor).round().clamp(80, 4000),
    );

    if (!appearance.animationEnabled) {
      _syncController(animating: false, duration: duration);
      return _shell(
        color:
            Color.lerp(context.colors.backgroundColor, blinkColor, maxBlend)!,
        borderColor: blinkColor,
        borderWidth: 2,
        child: widget.child,
      );
    }

    _syncController(animating: true, duration: duration);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return _shell(
          color: Color.lerp(
              context.colors.backgroundColor, blinkColor, maxBlend * t)!,
          borderColor: blinkColor,
          borderWidth: 2,
          child: child!,
        );
      },
      child: widget.child,
    );
  }

  Widget _shell({
    required Color color,
    required Color borderColor,
    required double borderWidth,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(kOrderCardRadius),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Raio de borda do card de pedido — a mesma curva usada aqui e por
/// qualquer elemento que precise acompanhar o contorno do card (ex: a barra
/// de ação no rodapé, em `kds_page.dart`). Um valor só, pra nunca dessincronizar
/// o arredondado do card com o de um botão que deveria se encaixar nele.
const kOrderCardRadius = 10.0;
