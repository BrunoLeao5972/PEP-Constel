/// Modalidades de atendimento identificadas pelo campo `localizador` do
/// pedido em venda.ocupacao: sem localizador é Balcão. Com localizador, o
/// tipo do objeto indica Mesa ou Cartão.
class ServiceModalitiesConfig {
  final bool balcaoEnabled;
  final bool mesaEnabled;
  final bool cartaoEnabled;

  const ServiceModalitiesConfig({
    this.balcaoEnabled = true,
    this.mesaEnabled = true,
    this.cartaoEnabled = true,
  });

  ServiceModalitiesConfig copyWith({
    bool? balcaoEnabled,
    bool? mesaEnabled,
    bool? cartaoEnabled,
  }) {
    return ServiceModalitiesConfig(
      balcaoEnabled: balcaoEnabled ?? this.balcaoEnabled,
      mesaEnabled: mesaEnabled ?? this.mesaEnabled,
      cartaoEnabled: cartaoEnabled ?? this.cartaoEnabled,
    );
  }
}
