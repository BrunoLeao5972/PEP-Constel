# PEP Constel — Documento de Arquitetura de Software (SAD)

> **Nota de precisão técnica:** este documento descreve o sistema **como ele existe hoje no código**, verificado arquivo por arquivo. Um caminho de impressão via porta serial (`flutter_libserialport`, baud rate configurável) chegou a ser implementado e depois **removido** em favor de outra abordagem, validada em campo — isso está registrado no Capítulo 5, com a justificativa. Sempre que uma decisão de arquitetura tiver uma alternativa descartada relevante, ela é mencionada, para quem for mexer no código não repetir o mesmo caminho sem necessidade.

**Versão do documento:** 1.0
**Data:** Agosto de 2026
**Autor:** Documentação técnica gerada a partir de auditoria do código-fonte

---

## Sumário

1. [Visão Geral do Sistema](#1-visão-geral-do-sistema)
2. [Requisitos e Pré-requisitos do Ambiente](#2-requisitos-e-pré-requisitos-do-ambiente)
3. [Arquitetura da Aplicação e Organização do Projeto](#3-arquitetura-da-aplicação-e-organização-do-projeto)
4. [Design System e Temas (UI/UX)](#4-design-system-e-temas-uiux)
5. [Módulo de Impressão (ESC/POS)](#5-módulo-de-impressão-escpos)
6. [Modelo de Dados e Comunicação](#6-modelo-de-dados-e-comunicação)
7. [Tratamento de Erros, Feedback e Resiliência](#7-tratamento-de-erros-feedback-e-resiliência)
8. [Guia de Manutenção e Boas Práticas](#8-guia-de-manutenção-e-boas-práticas)

---

## 1. Visão Geral do Sistema

### 1.1. Propósito e valor de negócio

O **PEP Constel** é um **KDS (Kitchen Display System)** que se conecta diretamente ao banco de dados do PDV **APIL** (MongoDB) para dar à cozinha, ao administrativo e ao cliente uma visão em tempo (quase) real do fluxo de um pedido — sem exigir nenhuma alteração no sistema de vendas em si. O PEP Constel **lê e escreve** nas mesmas coleções que o PDV já usa (`venda.ocupacao`, `recurso.item`, `seguranca.usuario`); ele não é um sistema de vendas paralelo.

Valor de negócio:

- **Elimina comandas de papel** entre o caixa e a cozinha — o pedido aparece na tela assim que é lançado no PDV.
- **Reduz atrasos silenciosos**: cards piscam (amarelo/vermelho) quando um pedido passa de um tempo configurável sem avançar.
- **Dá visibilidade ao administrador** sobre volume, atrasos e tempo médio de preparo, sem expor valores monetários (não é o foco do KDS).
- **Reduz interrupção do balcão**: o cliente acompanha o próprio pedido pela tela do Chamador, sem precisar perguntar "já ficou pronto?".
- **Permite reimpressão de comandas** (senha, itens, observações) mesmo em dispositivos sem impressora conectada (tablets Android), via uma fila de impressão remota.

### 1.2. Módulos principais

| Módulo | Arquivo principal | Papel |
|---|---|---|
| **Cozinha (KDS)** | `lib/features/orders/presentation/pages/kds_page.dart` | Quadro de trabalho ativo, item a item. Duas visões: **Lista** (grid) e **Kanban** (colunas Recebido / Em Preparo / Pronto). Cards piscam por urgência de tempo. |
| **Administrativo** | `lib/features/admin/presentation/pages/admin_page.dart` | Histórico (até 30 dias), indicadores operacionais (pedidos, em andamento, atrasados, tempo médio de preparo), filtro por período/status/busca, paginação e reimpressão. |
| **Chamador de Pedidos** | `lib/features/orders/presentation/pages/customer_facing_page.dart` | Tela "ACOMPANHE SEU PEDIDO", voltada pro cliente — mostra os pedidos ativos com o número/senha/mesa. |
| **Configurações** | `lib/features/settings/presentation/pages/settings_page.dart` | Conexão com o banco, modalidades de atendimento habilitadas, exibição do painel, numeração do chamador, alertas de tempo e impressora. |

### 1.3. Fluxo macro de dados

```
┌──────────┐     grava venda.ocupacao +           ┌──────────────┐
│   PDV    │     ocupacaoItens (producaoSituacao)  │   MongoDB    │
│  (APIL)  │ ─────────────────────────────────────▶│  banco: apil │
└──────────┘                                        └──────┬───────┘
                                                            │ polling (2s)
                     ┌──────────────────────────────────────┼──────────────────────────┐
                     ▼                                      ▼                          ▼
              ┌─────────────┐                       ┌───────────────┐         ┌────────────────┐
              │   Cozinha   │  avança status item    │ Administrativo│         │ Chamador (tela  │
              │    (KDS)    │ ───────────────────────▶  (histórico)  │         │  do cliente)    │
              └──────┬──────┘  arrayFilters no Mongo └───────────────┘         └────────────────┘
                     │
                     │ "Reimprimir" (gera ticket ESC/POS)
                     ▼
        ┌────────────────────────┐        Windows: envia direto pro Spooler
        │   KdsPrinterService     │───────────────────────────────────────────▶ 🖨️ Impressora
        └────────────────────────┘
                     │ Android: sem impressora local
                     ▼
        ┌────────────────────────┐   grava job em kds_print_jobs   ┌──────────────────────┐
        │  Fila de impressão      │─────────────────────────────────▶  PC Windows com a    │
        │  remota (MongoDB)        │◀────────────────────────────────  impressora, watcher  │
        └────────────────────────┘   status: done/failed            │  PrintJobRelayController│
                                                                     └──────────────────────┘
```

Pontos-chave desse fluxo:

- **Não há Change Streams**: o MongoDB roda standalone (sem replica set), então o "tempo real" é inteiramente via **polling** (a cada 2 segundos, tanto para pedidos ativos quanto para o histórico do Admin).
- **Uma ocupação (mesa/cartão) pode virar vários cards**: cada lançamento na mesma mesa tem seu próprio `comandaCodigo`; o KDS agrupa por esse código para não misturar uma leva nova com uma leva antiga já entregue da mesma mesa (ver §6.3).
- **Status é derivado, não armazenado no pedido como um todo**: cada *item* tem seu `producaoSituacao`; o status do card (`Order.status`) é calculado a partir do status de todos os itens daquela leva.

---

## 2. Requisitos e Pré-requisitos do Ambiente

### 2.1. SDKs e versões

| Ferramenta | Versão exigida | Onde está declarado |
|---|---|---|
| Dart SDK | `>=3.0.0 <4.0.0` | `pubspec.yaml` → `environment.sdk` |
| Flutter SDK | Compatível com Dart 3.0+ (Flutter 3.10 ou superior) | Implícito pelo Dart SDK e por `useMaterial3: true` |
| Material Design | 3 (Material You) | `ThemeData(useMaterial3: true)` em `app_themes.dart` |

### 2.2. Sistemas operacionais suportados

> ⚠️ **Correção em relação ao briefing original:** o projeto **não** tem suporte a Linux nem a "Android Desktop" (esse não é um alvo real do Flutter). Os dois alvos configurados e ativamente usados são:

| Plataforma | Uso no sistema | Observação |
|---|---|---|
| **Windows (x64)** | PC do caixa/administrativo — é quem normalmente tem a impressora térmica conectada e/ou o MongoDB instalado localmente. | Único alvo com o pacote `win32` funcional (impressão local via Spooler do Windows). |
| **Android** | Tablets de Cozinha e/ou Administrativo. | Não imprime localmente — pedidos de impressão são retransmitidos para um PC Windows (ver Capítulo 5). |

O projeto **não** possui pastas de plataforma configuradas para Linux, macOS, iOS ou Web.

### 2.3. Banco de dados

- **MongoDB standalone** (sem replica set), versão testada: **8.0**.
- Banco lógico usado: `apil` (o mesmo do PDV).
- Coleções consumidas pelo PEP Constel:

| Coleção | Uso |
|---|---|
| `venda.ocupacao` | Pedidos ativos e histórico (leitura e escrita de status/produção). |
| `recurso.item` | Catálogo de produtos, usado só para resolver a imagem do item (cache de 5 minutos). |
| `seguranca.usuario` | Autenticação (login por `credencial` + hash `bcrypt`). |
| `kds_print_jobs` | **Exclusiva do PEP Constel** (não faz parte do schema do PDV) — fila de impressão remota. Prefixo `kds_` de propósito, para nunca ser confundida com uma coleção real do APIL. |

- **Configuração de rede obrigatória** para acesso multi-dispositivo:
  - `mongod.cfg` → `net.bindIp: 0.0.0.0` (aceitar conexões de qualquer IP da rede, não só do próprio PC).
  - Regra de firewall liberando a porta **27017/TCP** para a rede privada.
  - Script pronto para isso: `scripts/configurar-rede-mongodb.ps1` / `.bat` (idempotente, cria backup antes de alterar, e já vem embutido no instalador Windows — ver §8.1).

### 2.4. Periféricos

| Periférico | Requisito | Observação |
|---|---|---|
| **Impressora térmica ESC/POS** (ex: Daruma DR700) | Instalada como impressora comum do **Windows** (painel "Impressoras e scanners"), com o driver do fabricante. | ⚠️ Não é comunicação serial direta (ver Capítulo 5 para a justificativa técnica). Qualquer impressora ESC/POS instalada dessa forma no Windows é compatível — Epson, Bematech, Elgin etc. |
| Telas touch (Cozinha) | Nenhum driver especial — a UI usa componentes Material padrão com alvos de toque adequados. | Layout responsivo (grid adaptativo, Kanban, Drawer em telas estreitas via breakpoint de 600px). |

---

## 3. Arquitetura da Aplicação e Organização do Projeto

### 3.1. Padrão arquitetural

O projeto segue **Feature-First** (organização por funcionalidade de negócio, não por tipo técnico), com uma separação inspirada em Clean Architecture **dentro** de cada feature:

```
features/<feature>/
├── domain/
│   ├── entities/        → classes de negócio puras (sem dependência de Flutter/Mongo)
│   └── repositories/    → contratos abstratos (interfaces)
├── data/
│   └── repositories/    → implementação concreta dos contratos (fala com o MongoDB)
└── presentation/
    ├── pages/           → widgets de tela
    └── providers/       → estado e orquestração (Riverpod)
```

Não existe uma camada de "use cases" separada — os **providers Riverpod fazem esse papel de orquestração** entre repositório e UI (é um Clean Architecture "enxuto", adequado ao tamanho do projeto).

### 3.2. Árvore de diretórios (`lib/`)

```
lib/
├── main.dart                         # Bootstrap do app, AuthGate, MainScaffold (shell com sidebar/tabs)
│
├── core/                             # Código transversal, usado por múltiplas features
│   ├── config/                       # Modelos de configuração + seus providers (persistidos via SharedPreferences)
│   │   ├── mongo_config.dart / _provider.dart              → host/porta/banco do Mongo
│   │   ├── order_timing_config.dart / _provider.dart       → limites de alerta/crítico (minutos)
│   │   ├── order_caller_config.dart / _provider.dart       → numeração do Chamador (PDV vs KDS)
│   │   ├── panel_display_config.dart / _provider.dart      → quais modalidades aparecem no Chamador
│   │   ├── service_modalities_config.dart / _provider.dart → quais modalidades estão habilitadas
│   │   ├── printer_config.dart / _provider.dart            → impressora selecionada + largura do papel
│   │   └── theme_mode_provider.dart                        → claro/escuro
│   │
│   ├── data/                         # Integrações técnicas (não são "repositórios de domínio")
│   │   ├── mongo_service.dart        → provider da conexão (`Db`) com o MongoDB
│   │   ├── mongo_discovery.dart      → varredura de rede pra achar o servidor automaticamente
│   │   └── mongo_error.dart          → tradução de erros técnicos em mensagens pro usuário
│   │
│   ├── theme/                        # Design system
│   │   ├── app_colors.dart           → paleta (ThemeExtension) + cores de status fixas
│   │   └── app_themes.dart           → ThemeData completo (claro/escuro)
│   │
│   ├── widgets/                      # Widgets reutilizáveis entre features
│   │   ├── top_navigation_bar.dart   → sidebar/menu principal
│   │   └── order_urgency_shell.dart  → moldura animada de urgência (pisca-pisca dos cards)
│   │
│   └── providers/
│       └── navigation_provider.dart  → aba ativa do shell principal
│
├── features/
│   ├── auth/                         # Login
│   │   ├── domain/{entities/kds_user.dart, repositories/auth_repository.dart}
│   │   ├── data/repositories/mongo_auth_repository.dart
│   │   └── presentation/{pages/login_page.dart, providers/auth_provider.dart}
│   │
│   ├── orders/                       # Núcleo do negócio: pedidos
│   │   ├── domain/{entities/order.dart, repositories/order_repository.dart}
│   │   ├── data/repositories/mongo_order_repository.dart
│   │   └── presentation/
│   │       ├── pages/kds_page.dart, customer_facing_page.dart
│   │       └── providers/order_provider.dart, kds_view_provider.dart, order_caller_provider.dart
│   │
│   ├── admin/                        # Painel administrativo
│   │   └── presentation/{pages/admin_page.dart, providers/admin_view_provider.dart}
│   │
│   └── settings/
│       └── presentation/pages/settings_page.dart
│       └── printer_settings_widget.dart   # (exceção à convenção: widget componentizado direto em features/settings/)
│
└── services/                         # Serviços de infraestrutura que cruzam features
    ├── kds_printer_service.dart       # Geração ESC/POS + envio (local Windows ou fila remota)
    └── print_job_relay_service.dart   # Watcher que processa a fila remota (só ativo no Windows)
```

> Não existem pastas `models/` nem `widgets/` na raiz de `lib/` — o briefing original assumia essa nomenclatura, mas o projeto usa `domain/entities/` para os modelos de negócio e mantém widgets reutilizáveis dentro de `core/widgets/` (transversais) ou junto da própria página (quando são específicos de uma tela só).

### 3.3. Gerenciamento de estado — Riverpod

O projeto usa **`flutter_riverpod` 2.x** exclusivamente (não há Bloc, GetX ou `ValueNotifier` solto). Quatro tipos de provider cobrem praticamente todos os casos:

| Tipo | Quando é usado | Exemplo real |
|---|---|---|
| `Provider` | Serviço/repositório sem estado próprio, montado a partir de outro provider. | `orderRepositoryProvider` (monta `MongoOrderRepository` a partir do `Db`) |
| `StateProvider` | Estado simples e síncrono (filtro, seleção, texto de busca). | `adminStatusFilterProvider`, `kdsViewModeProvider` |
| `StateNotifierProvider` | Estado com lógica de transição, geralmente persistido. | `themeModeProvider`, `printerConfigProvider`, `PrintJobRelayController` |
| `FutureProvider` | Recurso assíncrono com estados implícitos de loading/erro/dado. | `mongoDbProvider` (conexão com o Mongo) |

Padrão de **stream via polling** (não existe `StreamProvider` customizado com Change Streams — é simulado):

```dart
// lib/features/orders/presentation/providers/order_provider.dart
final ordersStreamProvider = StreamProvider<List<Order>>((ref) {
  final repository = ref.watch(orderRepositoryProvider);
  return repository.getOrders(); // Stream<List<Order>> que faz polling internamente
});
```

Um padrão importante de **UI otimista** existe em `order_provider.dart`: ao tocar em "Iniciar"/"Pronto", o app aplica o novo status **localmente e imediatamente** (`itemStatusOverridesProvider`), sem esperar o próximo poll confirmar — e só remove o override quando o dado real do banco bate com o valor aplicado.

---

## 4. Design System e Temas (UI/UX)

### 4.1. Arquitetura do `ThemeData`

A paleta ativa é exposta como um **`ThemeExtension<AppColors>`**, o mecanismo oficial do Flutter para estender `ThemeData` com tokens próprios. Isso permite qualquer widget ler `context.colors.backgroundColor` (via uma extensão de conveniência) e reagir **automaticamente** à troca de tema — inclusive com a transição animada que o `MaterialApp` já faz sozinho (não há necessidade de nenhum `AnimatedTheme` manual).

```dart
// lib/core/theme/app_colors.dart
extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
```

```dart
// lib/main.dart — troca de tema é só isso, o resto é automático
return MaterialApp(
  theme: AppThemes.light,
  darkTheme: AppThemes.dark,
  themeMode: ref.watch(themeModeProvider),
  home: const AuthGate(),
);
```

O modo (claro/escuro) é persistido via `SharedPreferences` (`ThemeModeNotifier`, chave `theme_is_light`) e alternado por um botão sol/lua na barra lateral. **Não segue o tema do sistema operacional por padrão** — é uma escolha explícita do usuário, com `ThemeMode.dark` como padrão de fábrica (ambiente de cozinha costuma ter pouca luz ambiente).

### 4.2. Diretrizes de acessibilidade/conforto visual (ambiente de cozinha)

| Diretriz | Como foi implementada |
|---|---|
| **Fundo claro nunca é branco puro** | `AppColors.light.backgroundColor = #F4F5F8` (off-white) — evita ofuscar em cozinhas muito iluminadas. |
| **Cards ganham profundidade própria no claro** | Como o fundo off-white e o card branco são próximos, o tema claro usa `elevation: 0` + borda (`#E2E8F0`) + sombra leve (`#1A0F172A`) no card; o escuro já tem contraste suficiente só pela diferença de cor de fundo (`elevation: 2`, sem borda). |
| **Cores de status são fixas entre os dois temas** | `AppStatusColors` fica **fora** de `AppColors` de propósito — são constantes únicas, para impedir estruturalmente que alguém escureça uma cor de status só num dos temas e quebre a associação visual (verde = pronto, não importa o tema). |
| **Alerta de atraso é reforçado por animação, não só cor** | Cards piscam (ver `OrderUrgencyShell`, §3.2/§6) quando cruzam o tempo de alerta/crítico — o crítico pisca mais rápido (550 ms) e mais forte (55% de mescla de cor) que o alerta (1000 ms, 32%), reforçando a diferença de severidade sem precisar de mais nenhum elemento na tela. |

### 4.3. Paleta de cores centralizada

**Cores de marca/status (`AppStatusColors`) — idênticas em claro e escuro:**

| Token | Hex | Uso |
|---|---|---|
| `primary` | `#6E48AA` | Roxo Constel — cor de marca primária |
| `secondary` | `#9D50BB` | Lilás Constel |
| `accent` | `#FDB813` | Dourado Constel — destaque/marca |
| `info` | `#2196F3` | Status "Recebido / novo" |
| `warning` | `#FFB300` | Status "Em preparo" / nível de alerta |
| `success` | `#4CAF50` | Status "Pronto / finalizado" |
| `error` | `#E53935` | Atraso / erro / ação de reverter / nível crítico |

**Paleta de superfície e texto (`AppColors`) — muda entre os temas:**

| Token | Escuro | Claro |
|---|---|---|
| `backgroundColor` | `#161821` | `#F4F5F8` |
| `cardColor` | `#212433` | `#FFFFFF` |
| `borderColor` | `#1AFFFFFF` (branco 10%) | `#E2E8F0` |
| `shadowColor` | transparente | `#1A0F172A` |
| `textColor` | `#E1E1E6` | `#0F172A` |
| `textSecondaryColor` | `#A8A8B3` | `#64748B` |

Tipografia: **Space Grotesk** (`google_fonts`), aplicada via `GoogleFonts.spaceGroteskTextTheme`.

---

## 5. Módulo de Impressão (ESC/POS)

> ⚠️ **Divergência importante em relação ao briefing original — leia antes de mexer neste módulo.**
>
> Uma primeira versão deste módulo usou `flutter_libserialport` para falar diretamente com uma porta serial/COM (baud rate configurável, 8N1). Essa abordagem foi **testada em campo e substituída**, pelo seguinte motivo: a impressora usada nos testes (Daruma DR700) está instalada no Windows como uma impressora comum, e a **página de teste nativa do Windows já imprimia corretamente nela** — evidência de que o caminho correto de integração era o **Spooler de Impressão do Windows** (a mesma fila que "Impressoras e scanners" usa), não uma porta serial separada. Depois da migração, a impressão passou a funcionar de forma confiável. As bibliotecas `flutter_libserialport`/`libserialport` foram **removidas do `pubspec.yaml`**.
>
> Isso significa: **não existe configuração de baud rate, bits de dados, paridade ou porta COM no código atual.** Quem resolve a velocidade/framing da conexão física é o driver que o Windows já usa — o app só entrega bytes ESC/POS "prontos" para a fila de impressão.

### 5.1. Arquitetura do serviço de impressão

Arquivo: **`lib/services/kds_printer_service.dart`**

```dart
class KdsPrinterService {
  List<String> getAvailablePrinters();                 // Enumera impressoras instaladas no Windows
  Future<KdsPrintOutcome> printOrder(Order order, PrinterConfig config, {Db? db});
  Future<KdsPrintOutcome> printTestTicket(PrinterConfig config);
  KdsPrintOutcome sendRawBytes(String printerName, Uint8List data); // Envio de baixo nível (Windows apenas)
}
```

`printOrder` decide o caminho pela plataforma em tempo de execução:

```dart
Future<KdsPrintOutcome> printOrder(Order order, PrinterConfig config, {Db? db}) async {
  final ticket = await _buildOrderTicket(order, config.paperWidth.escPosSize);
  if (Platform.isWindows) {
    return _sendToPrinter(config, ticket);       // Envia direto pro Spooler
  }
  if (db == null) {
    return const KdsPrintOutcome.failure('Sem conexão com o banco para solicitar a impressão.');
  }
  return _requestRemotePrint(db, ticket);         // Android: enfileira no Mongo
}
```

Isso dá **um único ponto de entrada** para Cozinha e Administrativo chamarem ao reimprimir, independente da plataforma — quem decide "imprime local ou pede pra outro PC imprimir" é o próprio serviço, não a tela.

### 5.2. Bibliotecas utilizadas

| Pacote | Papel | Observação |
|---|---|---|
| `esc_pos_utils_plus` | Geração dos **comandos ESC/POS** (texto, estilos, corte de papel) — puro Dart, funciona em qualquer plataforma. | Usado tanto no Windows (imprime local) quanto no Android (só para montar os bytes que vão pra fila). |
| `win32` + `ffi` | Chamadas nativas ao **WinSpool** (API de impressão do Windows) — `EnumPrinters`, `OpenPrinter`, `StartDocPrinter`, `WritePrinter` etc. | Funcional **apenas no Windows**; todo uso é protegido por `Platform.isWindows` antes de chamar qualquer função do pacote, para nunca tentar carregar uma DLL do Windows a partir do Android. |
| `mongo_dart` | Usado pela fila de impressão remota (inserir/consultar/atualizar documentos em `kds_print_jobs`). | Já é dependência do projeto para tudo relacionado a pedidos. |

### 5.3. Configuração de impressora (não há configuração de baud rate)

```dart
// lib/core/config/printer_config.dart
enum PrinterPaperWidth {
  mm58(PaperSize.mm58),
  mm80(PaperSize.mm80);
  final PaperSize escPosSize;
  const PrinterPaperWidth(this.escPosSize);
}

class PrinterConfig {
  final String? printerName;                          // Nome exato como o Windows identifica a impressora
  final PrinterPaperWidth paperWidth;                  // 58mm (32 colunas) ou 80mm (48 colunas)
  const PrinterConfig({this.printerName, this.paperWidth = PrinterPaperWidth.mm80});
}
```

A UI de seleção (`printer_settings_widget.dart`) lista as impressoras via `getAvailablePrinters()` (chama `EnumPrinters` com nível `PRINTER_INFO_4` — o único nível que não exige privilégio elevado só para *listar* nomes) e persiste a escolha via `SharedPreferences`.

Um detalhe crítico de implementação em `sendRawBytes`, que já causou falha silenciosa em produção e vale documentar:

```dart
// Sem isso, o handle abre só com acesso padrão (leitura), e StartDocPrinter
// falha mais adiante sem gerar nenhum erro visível.
defaults.ref.DesiredAccess = _kPrinterAccessUse; // 0x00000008 == PRINTER_ACCESS_USE
```

`PRINTER_ACCESS_USE` não está entre as constantes documentadas do pacote `win32` — sem pedir esse acesso explicitamente no `PRINTER_DEFAULTS` passado a `OpenPrinter`, a impressora abre só para leitura e o job falha silenciosamente mais adiante.

### 5.4. Protocolo de comandos térmicos (formatação do cupom)

O ticket é montado acumulando `List<int>` a partir de um `Generator` (de `esc_pos_utils_plus`), sempre iniciado por `generator.reset()` (comando `ESC @`, reinicializa a impressora):

```dart
// lib/services/kds_printer_service.dart — trecho real de _buildOrderTicket
bytes += generator.reset();
bytes += generator.text('PEP CONSTEL',
    styles: const PosStyles(align: PosAlign.center, bold: true,
        height: PosTextSize.size2, width: PosTextSize.size2));
bytes += generator.hr(ch: '=');                                  // divisor "======"
bytes += generator.text('Pedido: #${order.number}', styles: const PosStyles(bold: true));
...
for (final item in order.items) {
  bytes += generator.text('${item.quantity}x ${item.name}', styles: const PosStyles(bold: true));
  final observation = item.observation?.trim();
  if (observation != null && observation.isNotEmpty) {
    bytes += generator.text('  Obs: $observation', styles: const PosStyles(reverse: true)); // destaque em vídeo invertido
  }
}
...
bytes += generator.feed(2);   // alimenta 2 linhas antes do corte
bytes += generator.cut();     // GS V — aciona a guilhotina
```

| Elemento visual | Comando ESC/POS usado | Detalhe |
|---|---|---|
| Cabeçalho centralizado, destacado | `PosStyles(align: center, bold: true, height/width: size2)` | Título "PEP CONSTEL" em dobro de tamanho |
| Divisores | `generator.hr(ch: '=')` / `hr(ch: '-')` | Preenche a largura configurada (32 ou 48 colunas conforme `PrinterPaperWidth`) |
| Itens com quantidade | `'${item.quantity}x ${item.name}'` + `bold: true` | Uma linha por item |
| Observação (item ou geral) | `PosStyles(reverse: true)` | Vídeo invertido (fundo preto, texto claro) — chama atenção sem precisar de outro recurso gráfico |
| Alimentação + corte | `generator.feed(2)` + `generator.cut()` | `cut()` já inclui internamente mais 5 linhas de alimentação antes do comando de corte físico |

O texto **não** passa por conversão manual de acentuação — a biblioteca usa `latin1` como codec padrão, compatível com a página de código da maioria das impressoras térmicas configuradas para Português/Latin America.

### 5.5. Fluxo remoto (Android → PC com impressora)

Quando o dispositivo que pede a reimpressão **não é Windows** (tablet Android de Cozinha/Admin), o ticket já pronto (bytes ESC/POS) é serializado em Base64 e gravado como um documento na coleção `kds_print_jobs`:

```dart
await collection.insertOne({
  '_id': jobId,
  'bytes': base64Encode(bytes),
  'status': 'pending',
  'createdAt': DateTime.now().toUtc(),
});
```

O dispositivo solicitante então faz *polling* nesse mesmo documento por até **15 segundos**, aguardando `status` virar `done` ou `failed`.

Do outro lado, **qualquer instância Windows do app** roda um watcher (`PrintJobRelayController`, em `lib/services/print_job_relay_service.dart`) que:

1. Só se ativa se `Platform.isWindows` for verdadeiro (senão o `Timer` nem é criado).
2. A cada 2 segundos, busca documentos com `status: 'pending'`.
3. Para cada um, decodifica os bytes e chama `sendRawBytes` com a impressora configurada **naquele PC**.
4. Grava `status: 'done'` ou `'failed'` (+ mensagem de erro) de volta no mesmo documento.
5. Faz limpeza: remove jobs já resolvidos (`done`/`failed`) com mais de 6 horas, para a coleção não crescer indefinidamente.

Esse watcher é mantido vivo pela raiz do app autenticado (`MainScaffold`, em `main.dart`), independente de qual aba está aberta:

```dart
// lib/main.dart
ref.watch(printJobRelayProvider); // mantém o watcher rodando o tempo todo, não só quando uma tela específica está aberta
```

---

## 6. Modelo de Dados e Comunicação

### 6.1. Entidades principais

As entidades de domínio ficam em `domain/entities/`, são classes Dart puras (sem `Map`/Mongo/Flutter):

```dart
// lib/features/orders/domain/entities/order.dart
enum OrderStatus { novo, emPreparo, pronto, entregue }

class OrderItem {
  final String id;              // id da linha do pedido (ocupacaoItens[i].id)
  final String name;
  final int quantity;
  final OrderStatus status;
  final String? imageUrl;
  final String? observation;    // observação específica do item (ex: "sem cebola")
}

class Order {
  final String id;              // composto: "<docId>::<roundCode>"
  final int number;             // venda.ocupacao.numero — compartilhado entre TODAS as levas da mesma ocupação
  final List<OrderItem> items;
  final String? observations;   // observação geral do pedido
  final DateTime timestamp;     // menor "inclusao" entre os itens DESSA leva
  final String roundCode;       // ocupacaoItens[i].comandaCodigo — identifica a leva
  final String modalityName;    // "Balcão" / "Mesa" / "Cartão"
  final String? locatorLabel;   // "04" (mesa), "501" (cartão) — null em Balcão
  final String? pdvSenha;       // senha impressa pelo PDV — só existe em Balcão
  final DateTime? updatedAt;    // venda.ocupacao.edicao

  OrderStatus get status { /* derivado do status de TODOS os itens da leva */ }
  String get modalityDisplay;   // "Mesa 04" / "Cartão 501" / "Senha 0006"
  String get pdvCallerLabel;    // igual, mas sem o prefixo "Senha" (usado no Chamador)
}
```

Outras entidades/modelos de configuração relevantes (todas em `core/config/`, todas com `copyWith` e persistidas via `SharedPreferences`):

| Classe | Campos principais | Default |
|---|---|---|
| `PrinterConfig` | `printerName`, `paperWidth` | sem impressora, 80mm |
| `OrderTimingConfig` | `alertMinutes`, `criticalMinutes` | 15 / 25 minutos |
| `OrderCallerConfig` | `source` (`pdv`/`kds`), `resetDaily`, `startNumber` | PDV, zera diariamente, começa em 1 |
| `MongoConfig` | `host`, `port`, `database` | `127.0.0.1:27017/apil` |

### 6.2. Integração com backend

> ⚠️ **Correção em relação ao briefing original:** não há REST, WebSockets, Firebase nem SQLite local. A integração é **MongoDB direto** (driver `mongo_dart`), com **polling** simulando tempo real, pelo motivo abaixo.

```dart
// lib/core/data/mongo_service.dart
final mongoDbProvider = FutureProvider<Db>((ref) async {
  final config = ref.watch(mongoConfigProvider);
  final db = await Db.create(config.connectionString);   // mongodb://host:porta/banco
  await db.open().timeout(const Duration(seconds: 8), onTimeout: () => throw TimeoutException(...));
  ref.onDispose(() => db.close());
  return db;
});
```

```dart
// lib/features/orders/data/repositories/mongo_order_repository.dart
Stream<List<Order>> getOrders() async* {
  // Mongo local roda standalone (sem replica set), então não há suporte a
  // Change Streams. O "tempo real" aqui é feito via polling.
  while (true) {
    try {
      yield await _fetchOrders();
    } catch (_) {
      // Mantém o stream vivo se uma consulta falhar (ex: instabilidade de rede).
    }
    await Future.delayed(const Duration(seconds: 2));
  }
}
```

| Stream | Intervalo de poll | Janela de dados |
|---|---|---|
| Pedidos ativos (Cozinha) | 2s | Documentos com `produzida != true` |
| Histórico (Admin) | 2s | Últimos 30 dias (`inicio >= agora - 30 dias`) — o Admin filtra períodos menores (hoje/24h/3 dias/semana) **no app**, em cima desse mesmo dado |
| Fila de impressão remota | 2s | `status: 'pending'` |

### 6.3. Agrupamento por leva (`comandaCodigo`) e atualização granular

Uma ocupação (mesa/cartão) pode acumular vários lançamentos ao longo do atendimento (bebidas → entrada → prato principal), cada um com seu próprio `comandaCodigo`. O repositório agrupa os itens de um documento `venda.ocupacao` por esse código, gerando **um `Order` por grupo** — assim uma leva nova ("novo") nunca fica misturada, no mesmo card, com uma leva antiga já "entregue" da mesma mesa.

```dart
final itemsByRound = <String, List<Map<String, dynamic>>>{};
for (final raw in itemsRaw) {
  final roundCode = raw['comandaCodigo'] as String? ?? 'sem-codigo';
  (itemsByRound[roundCode] ??= []).add(raw);
}
// ... um Order por entrada de itemsByRound, com id = "$docId::$roundCode"
```

Ao avançar o status, a escrita usa **`arrayFilters`** do MongoDB para atualizar só os itens da leva (ou só um item específico), nunca o documento inteiro:

```dart
await _collection.updateOne(
  where.eq('id', docId),
  modify.set(r'ocupacaoItens.$[elem].producaoSituacao', code),
  arrayFilters: [{'elem.comandaCodigo': roundCode}],   // só essa leva
);
```

O campo `produzida` (booleano no documento inteiro, não por leva) só é marcado `true` quando **todas** as levas daquela ocupação já estiverem entregues — senão uma leva ainda em preparo desapareceria do quadro ativo da Cozinha junto com a que acabou de ser entregue.

---

## 7. Tratamento de Erros, Feedback e Resiliência

### 7.1. Erros de conexão com o banco

Toda mensagem de erro de conexão passa por um tradutor único (`friendlyMongoError`), usado tanto no login quanto no "Testar Conexão" das Configurações — evita ter dois textos diferentes para o mesmo problema:

```dart
// lib/core/data/mongo_error.dart
String friendlyMongoError(Object error, {String? host, int? port}) {
  if (error is TimeoutException || ...) {
    return 'O servidor$where não respondeu a tempo.\n'
        'Verifique se este dispositivo está na mesma rede Wi-Fi do computador do sistema.';
  }
  if (_isConnectionRefused(text)) {  // errno 111/61/10061/1225 — estável entre idiomas do SO
    return 'A conexão$where foi recusada.\n'
        'Verifique se o MongoDB está rodando nessa máquina, se está configurado pra aceitar conexões '
        'da rede (não só do próprio computador) e se o firewall libera a porta.';
  }
  // SocketException, "No route to host" etc. → mensagem de rede genérica
}
```

Uma distinção importante de UX: **falha de conexão** (`ServerUnreachableException`) leva o usuário **direto para a tela de Configurações** ao tentar logar — já **senha incorreta** só mostra o erro na própria tela de login. A lógica está em `login_page.dart`:

```dart
ref.listen<AsyncValue<KdsUser?>>(authControllerProvider, (previous, next) {
  if (next.error is ServerUnreachableException) {
    _goToConnectionSettings();
  }
});
```

### 7.2. Erros de impressão

O serviço de impressão nunca lança exceção para a UI — sempre retorna um `KdsPrintOutcome` com `success` + `error` (mensagem já pronta para exibir):

```dart
class KdsPrintOutcome {
  final bool success;
  final String? error;
  const KdsPrintOutcome.ok() : success = true, error = null;
  const KdsPrintOutcome.failure(this.error) : success = false;
}
```

Mensagens específicas por etapa que falhou (impressora ocupada/desconectada, job não iniciado, escrita falhou), incluindo o **código de erro nativo do Windows** (`GetLastError()`), para diagnóstico rápido sem precisar reproduzir o problema:

```dart
if (OpenPrinter(printerNamePtr, phPrinter, defaults) == 0) {
  return KdsPrintOutcome.failure(
    'Não foi possível abrir "$printerName" (código de erro do Windows: ${GetLastError()}). '
    'Verifique se ela está ligada e conectada.',
  );
}
```

No fluxo remoto (Android → fila Mongo), se **nenhum PC responder em 15 segundos**, o tablet recebe uma mensagem específica orientando a verificar se o KDS está aberto no PC com a impressora.

### 7.3. Feedback visual ao operador

| Situação | Mecanismo |
|---|---|
| Ação concluída/falha (reimpressão, salvar configuração) | `SnackBar` colorido (`context.colors.successColor` / `errorColor`) |
| Confirmação antes de uma ação (reimprimir) | `AlertDialog` com resumo do pedido |
| Pedido demorando (alerta/crítico) | Card inteiro pisca (`OrderUrgencyShell`) — ver §4.2 |
| Estado de conexão com o banco | Banner fixo na tela de Configurações (verde/amarelo/vermelho conforme `AsyncValue` de `mongoDbProvider`) |
| Operação em andamento | `CircularProgressIndicator` embutido no próprio botão (ex: "Testar Impressão" enquanto processa) |

### 7.4. Resiliência de streams (polling)

Todo laço de polling captura exceções **sem deixar o stream morrer**:

```dart
while (true) {
  try {
    yield await _fetchOrders();
  } catch (_) {
    // Mantém o stream vivo se uma consulta falhar (ex: instabilidade de rede).
  }
  await Future.delayed(_pollInterval);
}
```

Isso significa que uma falha pontual de rede (um poll perdido) nunca trava a tela — na pior hipótese, o dado fica "parado" por um ciclo até a próxima tentativa.

---

## 8. Guia de Manutenção e Boas Práticas

### 8.1. Como rodar o projeto localmente

```bash
flutter pub get

# Windows (recomendado para desenvolvimento — hot reload real)
flutter run -d windows

# Android (dispositivo físico ou emulador conectado)
flutter run -d <device-id>
```

Pré-requisito: um MongoDB acessível (local ou na rede) com o banco `apil` populado — sem isso, o login trava esperando conexão. Para configurar/corrigir o acesso de rede do MongoDB, use o script já pronto:

```
scripts/configurar-rede-mongodb.bat   # clique duas vezes, aceite a elevação de administrador
```

Esse mesmo script já vem embutido no instalador Windows (`installer/setup.iss`) e roda automaticamente (em silêncio) logo após a instalação, sem interromper o assistente.

**Gerar builds de distribuição:**

```bash
# Windows — gera o .exe e depois empacota o instalador
flutter build windows --release
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\setup.iss   # gera dist\PEP-Constel-Setup.exe

# Android
flutter build apk --release   # gera build\app\outputs\flutter-apk\app-release.apk
```

### 8.2. Como adicionar um novo status de pedido

1. Adicionar o valor em `OrderStatus` (`lib/features/orders/domain/entities/order.dart`).
2. Mapear o código numérico correspondente em `_statusByCode`/`_codeByStatus` (`mongo_order_repository.dart`) — esses códigos vêm do PDV, **não invente um número sem confirmar com o backend do APIL**.
3. Atualizar a lógica derivada em `Order.status` (getter) se o novo status alterar a regra de agregação item → pedido.
4. Atualizar todo `switch`/`when` exaustivo sobre `OrderStatus` — o compilador Dart aponta os pontos que faltam (o enum é usado em badges, ícones, filtros do Admin e da Cozinha).
5. Se o novo status precisa de uma cor própria, adicionar em `AppStatusColors` (nunca reaproveitar uma cor existente com outro significado).

### 8.3. Como adicionar um novo periférico de impressão

O ponto de extensão é `KdsPrinterService`. Duas situações possíveis:

- **Outra impressora ESC/POS via Windows Spooler**: nenhuma mudança de código é necessária — qualquer impressora instalada em "Impressoras e scanners" já aparece em `getAvailablePrinters()` e recebe os mesmos bytes RAW.
- **Um transporte diferente** (ex: impressora de rede via socket TCP direto, sem passar pelo Windows): implementar um novo método privado equivalente a `sendRawBytes`, mantendo a mesma assinatura de retorno (`KdsPrintOutcome`), e decidir em `_sendToPrinter`/`printOrder` qual transporte usar com base em um novo campo de `PrinterConfig` (ex: `connectionType`). **Não reintroduzir comunicação serial (`flutter_libserialport`) sem antes confirmar que a impressora-alvo realmente não pode ser instalada como impressora Windows** — foi essa suposição errada que causou o retrabalho documentado no Capítulo 5.

### 8.4. Checklist de Code Review

- [ ] Toda nova tela/estado usa Riverpod (não introduzir `setState` para dado que devia ser compartilhado, nem outro gerenciador de estado).
- [ ] Cores vêm de `context.colors.*` ou `AppStatusColors` — nunca `Colors.xxx` hardcoded fora do design system.
- [ ] Todo `switch`/`when` sobre `OrderStatus` é exaustivo (sem `default` escondendo um caso esquecido).
- [ ] Escritas no MongoDB que afetam só uma leva/item usam `arrayFilters` — nunca substituem o array inteiro.
- [ ] Loops de polling continuam vivos após uma exceção (`try/catch` em volta do `yield`, nunca deixando a exceção propagar e matar o `Stream`).
- [ ] Toda operação de impressão retorna `KdsPrintOutcome` (nunca lança exceção direto pra UI).
- [ ] Mudança testada nas duas plataformas (Windows **e** Android) quando toca em código de `core/` ou `services/` — ver `feedback_dual_platform_builds` nas convenções do projeto: melhorias devem valer pros dois builds por padrão.
- [ ] `flutter analyze` e `flutter test` limpos antes de qualquer build de release.

### 8.5. Padrões de commit e organização

O histórico do projeto usa mensagens de commit em **português**, focadas no "porquê" da mudança. Recomendações para manter a consistência:

- Mensagens no imperativo, curtas, em português: `"Corrige race condition no login"`, não `"Fixed bug"`.
- Um commit por mudança logicamente coesa — evitar misturar refatoração com feature nova no mesmo commit.
- Nunca commitar segredos (strings de conexão com credencial, chaves de keystore) — o `.gitignore` já cobre `.claude/`, builds e artefatos de plataforma; revisar `git status` antes de commitar qualquer coisa fora de `lib/`.
- Builds de distribuição (`.exe`, `.apk`) não devem crescer o histórico do repositório indefinidamente — o caminho recomendado é publicá-los como **GitHub Releases**, não como arquivo versionado dentro de `dist/` (ver observação registrada no histórico do projeto; migração ainda pendente).

---

## Anexo — Dependências principais (`pubspec.yaml`)

| Pacote | Papel |
|---|---|
| `flutter_riverpod` | Gerenciamento de estado |
| `mongo_dart` | Cliente MongoDB |
| `bcrypt` | Hash de senha no login |
| `shared_preferences` | Persistência local de configurações |
| `google_fonts` | Tipografia (Space Grotesk) |
| `intl` | Formatação de data/hora (`pt_BR`) |
| `esc_pos_utils_plus` | Geração de comandos ESC/POS |
| `win32` + `ffi` | Integração nativa com o Spooler de impressão do Windows |
