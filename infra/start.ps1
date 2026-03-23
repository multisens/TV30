# aop_infra -- Script de inicializacao
# Uso: .\start.ps1 [-Mosquitto] [-Proxies]
#   -Mosquitto  Sobe o Mosquitto (perfil mqtt)
#   -Proxies    Sobe proxy-win.js e proxy-wsl.js (sem networkingMode=mirrored)

param(
    [switch]$Mosquitto,
    [switch]$Proxies
)

$ROOT = $PSScriptRoot
$WSL_ROOT = "/mnt/" + ($ROOT -replace '\\', '/' -replace ':', '').ToLower()

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    [AVISO] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "    [ERRO] $msg" -ForegroundColor Red }

# --- 1. Verificar WSL e Docker ---
Write-Step "Verificando WSL e Docker..."
$dockerOk = wsl -- bash -c "docker info > /dev/null 2>&1 && echo ok"
if ($dockerOk -ne "ok") {
    Write-Err "Docker nao disponivel no WSL. Verifique a instalacao."
    exit 1
}
Write-Ok "Docker OK"

# --- 2. Docker Compose ---
Write-Step "Subindo stack via docker compose..."
if ($Mosquitto) {
    wsl -- bash -c "cd '$WSL_ROOT' && docker compose --profile mqtt up -d 2>&1"
} else {
    wsl -- bash -c "cd '$WSL_ROOT' && docker compose up -d 2>&1"
}
Write-Ok "Stack Docker pronto"

# --- 3. ccws-relay ---
Write-Step "Verificando ccws-relay..."
$relayOk = wsl -- bash -c "ss -tlnp | grep -q 44655 && echo ok"
if ($relayOk -eq "ok") {
    Write-Ok "ccws-relay ja rodando"
} else {
    wsl -- bash -c "node '$WSL_ROOT/ccws-relay.js' &>/tmp/ccws-relay.log & disown"
    Start-Sleep -Seconds 1
    $relayOk = wsl -- bash -c "ss -tlnp | grep -q 44655 && echo ok"
    if ($relayOk -eq "ok") {
        Write-Ok "ccws-relay iniciado (:44655 HTTPS, :44654 HTTP)"
    } else {
        Write-Err "ccws-relay falhou - verificar /tmp/ccws-relay.log no WSL"
    }
}

# --- 4. Proxies (opcional) ---
if ($Proxies) {
    Write-Step "Subindo proxy-wsl.js (WSL)..."
    $proxyWslOk = wsl -- bash -c "ss -tlnp | grep -q 8091 && echo ok"
    if ($proxyWslOk -eq "ok") {
        Write-Ok "proxy-wsl ja rodando"
    } else {
        wsl -- bash -c "node '$WSL_ROOT/proxy-wsl.js' &>/tmp/proxy-wsl.log & disown"
        Write-Ok "proxy-wsl iniciado (:8091)"
    }

    Write-Step "Descobrindo IP do WSL para proxy-win.js..."
    $WSL_IP = wsl -- bash -c "hostname -I | awk '{print `$1}'"
    $proxyFile = "$ROOT\proxy-win.js"
    $proxyContent = Get-Content $proxyFile -Raw
    $proxyUpdated = $proxyContent -replace "const WSL_IP = '[^']*'", "const WSL_IP = '$WSL_IP'"
    Set-Content $proxyFile $proxyUpdated -NoNewline
    Write-Ok "proxy-win.js atualizado com WSL IP: $WSL_IP"

    Write-Step "Subindo proxy-win.js (Windows)..."
    $proxyWinOk = netstat -ano | Select-String ":8090 "
    if ($proxyWinOk) {
        Write-Ok "Algo ja escuta em :8090 - proxy-win pode ja estar rodando"
    } else {
        Start-Process -FilePath "node" -ArgumentList "$ROOT\proxy-win.js" -WindowStyle Minimized
        Write-Ok "proxy-win.js iniciado (:8090)"
    }
}

# --- 5. CCWS ---
Write-Step "Iniciando CCWS (nova janela)..."
$ccwsPath = "$ROOT\GingaDistrib\ccws"
if (Test-Path $ccwsPath) {
    Start-Process -FilePath "cmd" -ArgumentList "/c cd /d `"$ccwsPath`" && npm run dev" -WindowStyle Normal
    Write-Ok "CCWS iniciado em nova janela (HTTP :44652, HTTPS :44653)"
} else {
    Write-Err "GingaDistrib/ccws nao encontrado - clone o repositorio em $ccwsPath"
}

# --- 6. Health check ---
Write-Step "Aguardando CCWS inicializar..."
Start-Sleep -Seconds 8
$health = try {
    (Invoke-WebRequest -Uri "https://localhost:44643/health" -SkipCertificateCheck -TimeoutSec 5 -UseBasicParsing).StatusCode
} catch { 0 }

if ($health -eq 200) {
    Write-Ok "Stack OK -- https://localhost:44643/health respondeu 200"
} else {
    Write-Warn "Health check falhou - CCWS pode ainda estar inicializando."
    Write-Warn "Tente: curl -k https://localhost:44643/health"
}

# --- Resumo ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Stack aop_infra" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " KrakenD External (HTTPS) : https://localhost:44643"
Write-Host " KrakenD Internal (HTTP)  : http://localhost:44642"
Write-Host " Swagger UI (external)    : http://localhost:8085"
Write-Host " Swagger UI (internal)    : http://localhost:8086"
Write-Host " Redis Commander          : http://localhost:8081"
Write-Host " CCWS (direto)            : https://localhost:44653 / http://localhost:44652"
if ($Mosquitto) {
    Write-Host " Mosquitto                : localhost:1883 (MQTT)"
}
Write-Host "========================================"
