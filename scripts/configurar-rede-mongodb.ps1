# Configura o MongoDB local para aceitar conexoes de outros dispositivos na
# rede (Android, outros PCs) -- usado quando o KDS Constel da erro de rede ao
# tentar conectar de um tablet/celular ao servidor rodando neste PC.
#
# O que faz:
#   1. Acha o mongod.cfg (arquivo de configuracao do MongoDB)
#   2. Garante que bindIp esteja em 0.0.0.0 (aceita qualquer IP da rede,
#      nao so o proprio PC) -- faz backup antes, so se for mudar algo
#   3. Libera a porta 27017 no Firewall do Windows para rede privada
#   4. Reinicia o servico do MongoDB, so se algo realmente mudou
#   5. Mostra o IP deste PC para usar na tela de Conexao do app Android
#
# Seguro rodar mais de uma vez -- cada passo confere o estado atual antes de
# mudar algo. Se um passo falhar (ex: rodou sem clicar em "Executar como
# administrador"), os outros passos e a verificacao final no fim continuam
# rodando mesmo assim, em vez de travar o script no meio.
#
# -NoPause: usado quando o instalador do PEP Constel chama este script
# sozinho, sem ninguem sentado esperando -- sem isso, o "Pressione Enter
# para sair" no final ficaria esperando pra sempre e travaria a instalacao.

param(
    [switch]$NoPause
)

Write-Host "==================================================="
Write-Host " Configurar MongoDB para aceitar conexoes de rede"
Write-Host "==================================================="
Write-Host ""

$changed = $false

# 1. Localizar o mongod.cfg
$cfgPath = $null
try {
    $cfgPath = Get-ChildItem -Path "C:\Program Files\MongoDB" -Filter "mongod.cfg" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
} catch {
    Write-Host "Erro ao procurar o mongod.cfg: $_" -ForegroundColor Red
}

if (-not $cfgPath) {
    if ($NoPause) {
        # Chamado pelo instalador -- normal nao achar nada aqui em maquinas
        # que so rodam o app (Cozinha, Admin) sem o MongoDB instalado
        # localmente. Nao e um erro, so nao ha nada pra configurar aqui.
        Write-Host "MongoDB nao encontrado nesta maquina -- nada a configurar."
        exit 0
    }
    Write-Host "ERRO: nao encontrei o mongod.cfg em C:\Program Files\MongoDB." -ForegroundColor Red
    Write-Host "Verifique se o MongoDB esta instalado nesta maquina."
    Read-Host "Pressione Enter para sair"
    exit 1
}

Write-Host "Arquivo encontrado: $cfgPath"

# 2. Ajustar bindIp (com backup só se for realmente mudar algo)
try {
    $content = Get-Content -Path $cfgPath -Raw
    if ($content -match '(?m)^[ \t]*bindIp[ \t]*:.*$') {
        # [^\r\n]* em vez de .*$ -- sem isso, o "." do ".*$" engolia o \r do
        # fim da linha (o "$" em modo multiline só marca a posição antes do
        # \n), e a troca trocava "...0.0.0.0\r\n" por "...0.0.0.0\n": o
        # texto visível ficava igual, mas o arquivo mudava (quebra de linha
        # diferente) e o script achava que precisava escrever de novo toda
        # vez que rodasse.
        $newContent = [regex]::Replace($content, '(?m)^([ \t]*bindIp[ \t]*:[ \t]*)[^\r\n]*', '${1}0.0.0.0')
        if ($newContent -eq $content) {
            Write-Host "bindIp ja estava em 0.0.0.0 -- nada a mudar."
        } else {
            $backupPath = "$cfgPath.bak-{0:yyyyMMdd-HHmmss}" -f (Get-Date)
            Copy-Item -Path $cfgPath -Destination $backupPath -Force
            Write-Host "Backup salvo em: $backupPath"
            Set-Content -Path $cfgPath -Value $newContent -NoNewline
            Write-Host "bindIp atualizado para 0.0.0.0." -ForegroundColor Green
            $changed = $true
        }
    } else {
        $backupPath = "$cfgPath.bak-{0:yyyyMMdd-HHmmss}" -f (Get-Date)
        Copy-Item -Path $cfgPath -Destination $backupPath -Force
        Write-Host "Backup salvo em: $backupPath"
        if ($content -match '(?m)^net:[ \t]*$') {
            $newContent = [regex]::Replace($content, '(?m)^(net:)[ \t]*$', "`$1`r`n  bindIp: 0.0.0.0")
        } else {
            $newContent = $content.TrimEnd() + "`r`n`r`nnet:`r`n  bindIp: 0.0.0.0`r`n"
        }
        Set-Content -Path $cfgPath -Value $newContent -NoNewline
        Write-Host "Bloco 'net.bindIp: 0.0.0.0' adicionado ao arquivo." -ForegroundColor Green
        $changed = $true
    }
} catch {
    Write-Host "AVISO: nao consegui ajustar o bindIp ($_)." -ForegroundColor Yellow
    Write-Host "Confirme que este script foi aberto como Administrador." -ForegroundColor Yellow
}

# 3. Firewall -- usa netsh (funciona mesmo sem elevar so pra consultar; só
# criar a regra de fato precisa de Administrador, igual o resto do script).
$ruleName = "MongoDB LAN"
try {
    $ruleCheck = netsh advfirewall firewall show rule name="$ruleName" 2>&1
    $ruleExists = ($LASTEXITCODE -eq 0) -and ($ruleCheck -match [regex]::Escape($ruleName))

    if ($ruleExists) {
        Write-Host "Regra de firewall '$ruleName' ja existia."
    } else {
        $addResult = netsh advfirewall firewall add rule name="$ruleName" dir=in action=allow protocol=TCP localport=27017 profile=private 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Regra de firewall '$ruleName' criada (porta 27017, rede privada)." -ForegroundColor Green
            $changed = $true
        } else {
            Write-Host "AVISO: nao foi possivel criar a regra de firewall ($addResult)." -ForegroundColor Yellow
            Write-Host "Confirme que este script foi aberto como Administrador." -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "AVISO: nao consegui checar/criar a regra de firewall ($_)." -ForegroundColor Yellow
}

# 4. Reiniciar o servico -- só se algo realmente mudou, pra não derrubar o
# MongoDB à toa no meio do expediente do cliente quando já estava tudo certo.
try {
    $service = Get-Service -Name "MongoDB" -ErrorAction SilentlyContinue
    if ($changed) {
        if ($service) {
            Write-Host "Reiniciando o servico do MongoDB (algo mudou)..."
            Restart-Service -Name "MongoDB" -Force
            Start-Sleep -Seconds 2
            $service.Refresh()
            Write-Host "Servico MongoDB: $($service.Status)"
        } else {
            Write-Host "AVISO: servico 'MongoDB' nao encontrado -- reinicie manualmente se necessario." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Nada mudou -- servico do MongoDB nao precisou ser reiniciado."
    }
} catch {
    Write-Host "AVISO: nao consegui reiniciar o servico ($_)." -ForegroundColor Yellow
    Write-Host "Confirme que este script foi aberto como Administrador." -ForegroundColor Yellow
}

# 5. Verificacao final -- roda sempre, mesmo se algum passo acima falhou.
Write-Host ""
Write-Host "--- Verificacao final ---"
try {
    Select-String -Path $cfgPath -Pattern "bindIp" | ForEach-Object { Write-Host $_.Line.Trim() }
} catch {
    Write-Host "(nao consegui reler o arquivo de configuracao)" -ForegroundColor Yellow
}

$listening = netstat -an | Select-String ":27017.*LISTENING"
if ($listening) {
    Write-Host "Escutando em: $($listening.Line.Trim())" -ForegroundColor Green
} else {
    Write-Host "Porta 27017 nao aparece como LISTENING -- confira o servico." -ForegroundColor Yellow
}

$ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "IP deste computador na rede: $ip" -ForegroundColor Cyan
Write-Host "Use esse IP (porta 27017) na tela de Configurar Conexao do app Android."
Write-Host ""
if (-not $NoPause) {
    Read-Host "Pressione Enter para sair"
}
