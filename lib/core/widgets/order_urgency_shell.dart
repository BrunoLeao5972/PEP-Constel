import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../config/order_timing_config.dart';
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
Color orderUrgencyColor(BuildContext context, OrderUrgency urgency) {
  return switch (urgency) {
    OrderUrgency.critical => context.colors.errorColor,
    OrderUrgency.alert => context.colors.warningColor,
    OrderUrgency.normal => context.colors.textSecondaryColor,
  };
}

/// Moldura animada do card de pedido — o conteúdo (child) é montado uma
/// única vez e não é reconstruído a cada tick da animação (o AnimatedBuilder
/// cuida disso). Fica parada em pedidos normais; quando o pedido cruza o
/// tempo de alerta ou crítico, o CARD INTEIRO pisca em amarelo ou vermelho
/// pra chamar atenção — o crítico pisca mais forte e mais rápido que o
/// alerta. Usado tanto na Cozinha quanto no Administrativo, pra quem
/// estiver de olho no dashboard também perceber pedidos ativos ficando
/// atrasados.
class OrderUrgencyShell extends StatefulWidget {
  final OrderUrgency urgency;
  final Widget child;

  const OrderUrgencyShell(
      {super.key, required this.urgency, required this.child});

  @override
  State<OrderUrgencyShell> createState() => _OrderUrgencyShellState();
}

class _OrderUrgencyShellState extends State<OrderUrgencyShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: _durationFor(widget.urgency));
    if (widget.urgency != OrderUrgency.normal) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant OrderUrgencyShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urgency == widget.urgency) return;

    _controller.duration = _durationFor(widget.urgency);
    if (widget.urgency == OrderUrgency.normal) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration _durationFor(OrderUrgency urgency) {
    // Crítico pisca visivelmente mais rápido que alerta — reforça que é o
    // nível mais urgente sem precisar de mais nenhum elemento na tela.
    return urgency == OrderUrgency.critical
        ? const Duration(milliseconds: 550)
        : const Duration(milliseconds: 1000);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urgency == OrderUrgency.normal) {
      return Container(
        decoration: BoxDecoration(
          color: context.colors.backgroundColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.colors.borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: widget.child,
      );
    }

    final blinkColor = widget.urgency == OrderUrgency.critical
        ? context.colors.errorColor
        : context.colors.warningColor;
    // Crítico pisca mais forte que alerta, além de mais rápido — reforça a
    // diferença de nível sem precisar de mais nenhum elemento na tela. Fica
    // abaixo de 1.0 mesmo no pico pra o conteúdo do card (texto, badges,
    // fotos) continuar legível durante o pisca.
    final maxBlend = widget.urgency == OrderUrgency.critical ? 0.55 : 0.32;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Container(
          decoration: BoxDecoration(
            color: Color.lerp(
                context.colors.backgroundColor, blinkColor, maxBlend * t),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: blinkColor, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
