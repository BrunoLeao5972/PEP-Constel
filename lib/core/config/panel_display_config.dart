/// Controla quais modalidades de atendimento aparecem no Painel (tela do
/// cliente), independente das modalidades habilitadas no estabelecimento.
class PanelDisplayConfig {
  final bool showBalcao;
  final bool showMesa;
  final bool showCartao;

  const PanelDisplayConfig({
    this.showBalcao = true,
    this.showMesa = true,
    this.showCartao = true,
  });

  PanelDisplayConfig copyWith({
    bool? showBalcao,
    bool? showMesa,
    bool? showCartao,
  }) {
    return PanelDisplayConfig(
      showBalcao: showBalcao ?? this.showBalcao,
      showMesa: showMesa ?? this.showMesa,
      showCartao: showCartao ?? this.showCartao,
    );
  }

  /// Se um pedido com essa modalidade deve aparecer no Painel. Modalidades
  /// desconhecidas (fora de Balcão/Mesa/Cartão) sempre aparecem.
  bool isVisible(String modalityName) {
    switch (modalityName) {
      case 'Balcão':
        return showBalcao;
      case 'Mesa':
        return showMesa;
      case 'Cartão':
        return showCartao;
      default:
        return true;
    }
  }
}
