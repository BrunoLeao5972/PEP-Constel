# KDS Constel

Sistema de Exibição de Cozinha (Kitchen Display System) desenvolvido em Flutter.

## Tecnologias

- Flutter + Riverpod
- Google Fonts (Space Grotesk)
- Intl para formatação de datas

## Estrutura

```
lib/
  core/         # Tema e widgets globais
  features/
    orders/     # Pedidos (domain, data, presentation)
    admin/      # Painel administrativo
```

## Como Rodar

```bash
flutter pub get
flutter run -d windows
```

## Build Windows

```bash
flutter build windows --release
```

## Funcionalidades

- Layout responsivo (TV, Desktop, Tablet, Mobile)
- Pedidos em tempo real (simulação via Stream)
- Fluxo de status: Novo → Em Preparo → Pronto → Entregue
- Painel administrativo com visão tabular
