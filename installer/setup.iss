#define MyAppName "PEP Constel"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Projeto Constel"
#define MyAppExeName "kds_constel.exe"

[Setup]
AppId={{EB942AED-7B62-49B5-A17E-E9C961804BBA}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=PEP-Constel-Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupIconFile=..\windows\runner\resources\app_icon.ico
; Sem isso, atualizar por cima de uma instalação com o app ainda aberto
; falhava silenciosamente em sobrescrever o .exe (arquivo travado pelo
; processo rodando) — o instalador "concluía" mas o app antigo continuava
; sendo o que abria depois. Força fechar antes de copiar os arquivos novos.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "Criar um atalho na área de trabalho"; GroupDescription: "Atalhos adicionais:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\scripts\configurar-rede-mongodb.ps1"; DestDir: "{app}\scripts"; Flags: ignoreversion
Source: "..\scripts\configurar-rede-mongodb.bat"; DestDir: "{app}\scripts"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Desinstalar {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Roda em silêncio logo após copiar os arquivos — o instalador já pede
; elevação de administrador, então esse passo herda isso de graça, sem
; precisar do próprio truque de auto-elevação do .bat. Não interrompe nem
; falha a instalação: se o MongoDB não estiver nesta máquina (ex: PC da
; Cozinha, que só roda o app), o script detecta isso e não faz nada.
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\configurar-rede-mongodb.ps1"" -NoPause"; StatusMsg: "Configurando acesso de rede ao banco de dados (se houver MongoDB neste PC)..."; Flags: runhidden waituntilterminated
Filename: "{app}\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent
