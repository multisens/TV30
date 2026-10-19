# tv30.ps1 — sobe e desce o testbed com a descoberta SSDP (C.3.4), no Windows.
#
#   .\tv30.ps1 up   [args do docker compose up]    compose up -d + anunciante
#   .\tv30.ps1 down [args do docker compose down]  anunciante (ssdp:byebye) + compose down
#   .\tv30.ps1 status                              containers e anunciante
#   .\tv30.ps1 logs                                log do anunciante
#
# Equivalente do ./tv30 (Linux e macOS); ver o cabecalho dele. Complemento do
# Joel de 15/10: o anunciante roda no host, fora do Docker (no Windows o
# container fica na VM do Docker e o multicast nao sai). No Windows nao ha
# SIGTERM para processo em segundo plano: a descida cria o arquivo de parada
# (SSDP_STOP_FILE), e o anunciante manda o ssdp:byebye e sai. Na primeira
# execucao o Windows Defender pede permissao de rede para o anunciante: marque
# "redes privadas", com o perfil da rede como Privada (medicao M6).
# Sem docker no PowerShell (Docker Engine instalado so dentro do WSL2), o
# script usa o do WSL: "wsl docker ...", na mesma pasta (o wsl traduz o
# diretorio corrente para /mnt/<unidade>/...). NAO medido no Windows.
# Roda tambem no PowerShell 7 (pwsh) do Linux e do macOS.
param([Parameter(Position = 0)][string]$Cmd = '', [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest = @())
$ErrorActionPreference = 'Stop'

$Root  = $PSScriptRoot
$State = Join-Path $Root '.tv30'
$Src   = Join-Path (Join-Path (Join-Path $Root 'infra') 'edgegateway') 'ssdp'
$OnWindows = ($PSVersionTable.PSEdition -eq 'Desktop') -or $IsWindows
$Exe   = if ($OnWindows) { 'ssdp-announcer.exe' } else { 'ssdp-announcer' }
$Bin   = Join-Path (Join-Path $State 'bin') $Exe
$PidF  = Join-Path $State 'ssdp.pid'
$Log   = Join-Path $State 'ssdp.log'
$StopF = Join-Path $State 'ssdp.stop'
$GoImg = if ($env:GO_IMG) { $env:GO_IMG } else { 'golang:1.22.7-alpine3.19' }  # o mesmo Go da borda
$SsdpKeys = 'SSDP_ENABLED', 'SSDP_ADVERTISE_HOST', 'SSDP_INTERFACE', 'EDGE_HTTP_PORT', 'EDGE_HTTPS_PORT', 'UDN'

function Info([string]$m) { Write-Host "[tv30] $m" }
function Die([string]$m) { Write-Host "[tv30] ERRO: $m"; exit 1 }

# docker do PowerShell ou, sem ele, o do WSL
$UseWsl = $false
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    if ($OnWindows -and (Get-Command wsl -ErrorAction SilentlyContinue)) { $UseWsl = $true }
}
function DockerCmd {
    if ($UseWsl) { wsl docker @args } else { docker @args }
}
# caminho do Windows como o Docker do WSL o ve
function DockerPath([string]$p) {
    if ($UseWsl) { return (wsl wslpath -a ($p -replace '\\', '/')).Trim() }
    return $p
}

# valor da chave nos arquivos de ambiente (tv3ws/.env, depois o .env da raiz,
# como no compose); o ambiente do processo prevalece
function EnvValue([string]$Key) {
    $val = ''
    foreach ($f in @((Join-Path (Join-Path $Root 'tv3ws') '.env'), (Join-Path $Root '.env'))) {
        if (-not (Test-Path $f)) { continue }
        foreach ($line in Get-Content $f) {
            if ($line.StartsWith("$Key=")) { $val = $line.Substring($Key.Length + 1).Trim("`r") }
        }
    }
    $val = $val.Trim('"').Trim("'")
    $fromEnv = [Environment]::GetEnvironmentVariable($Key)
    if ($null -ne $fromEnv) { $val = $fromEnv }
    return $val
}

function AnnouncerProcess {
    if (-not (Test-Path $PidF)) { return $null }
    $id = [int](Get-Content $PidF -Raw).Trim()
    return Get-Process -Id $id -ErrorAction SilentlyContinue
}

function Target {
    $os = if ($OnWindows) { 'windows' } elseif ($IsMacOS) { 'darwin' } else { 'linux' }
    $a = if ($OnWindows) { $env:PROCESSOR_ARCHITECTURE } else { (uname -m) }
    $arch = switch -Regex ($a) { '^(AMD64|x86_64|amd64)$' { 'amd64' } '^(ARM64|arm64|aarch64)$' { 'arm64' } default { Die "arquitetura $a sem suporte" } }
    return @($os, $arch)
}

# compila o anunciante se faltar o binario ou se o codigo mudou depois dele
function Build([switch]$Force) {
    if (-not $Force -and (Test-Path $Bin)) {
        $t = (Get-Item $Bin).LastWriteTime
        $newer = Get-ChildItem $Src -Recurse -Include '*.go', 'go.mod' | Where-Object { $_.LastWriteTime -gt $t }
        if (-not $newer) { return }
    }
    $os, $arch = Target
    New-Item -ItemType Directory -Force (Join-Path $State 'bin') | Out-Null
    Info "compilando o anunciante SSDP ($os/$arch) a partir de infra/edgegateway/ssdp..."
    if (Get-Command go -ErrorAction SilentlyContinue) {
        Push-Location $Src
        try {
            go vet ./...; if ($LASTEXITCODE) { Die 'go vet falhou' }
            go test -count=1 ./... | Out-Null; if ($LASTEXITCODE) { Die 'testes do anunciante falharam' }
            $env:CGO_ENABLED = '0'; $env:GOOS = $os; $env:GOARCH = $arch
            go build -trimpath -o $Bin .; if ($LASTEXITCODE) { Die 'go build falhou' }
        } finally {
            Remove-Item Env:GOOS, Env:GOARCH, Env:CGO_ENABLED -ErrorAction SilentlyContinue
            Pop-Location
        }
    } else {
        if (-not $UseWsl -and -not (Get-Command docker -ErrorAction SilentlyContinue)) { Die 'sem go e sem docker para compilar o anunciante' }
        $out = "ssdp-announcer$(if ($os -eq 'windows') { '.exe' })"
        $srcD = DockerPath $Src; $outD = DockerPath (Join-Path $State 'bin')
        DockerCmd run --rm -v "${srcD}:/src:ro" -v "${outD}:/out" -w /src `
            -e CGO_ENABLED=0 -e GOCACHE=/tmp/gocache -e GOFLAGS=-buildvcs=false $GoImg `
            sh -c "go vet ./... && go test -count=1 ./... >/dev/null && GOOS=$os GOARCH=$arch go build -trimpath -o /out/$out ."
        if ($LASTEXITCODE) { Die "falha ao compilar o anunciante (container $GoImg)" }
    }
}

function SsdpStop {
    $p = AnnouncerProcess
    if ($null -eq $p) { Remove-Item $PidF, $StopF -ErrorAction SilentlyContinue; return }
    New-Item -ItemType File -Force $StopF | Out-Null   # ssdp:byebye e saida
    if (-not $p.WaitForExit(5000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item $PidF, $StopF -ErrorAction SilentlyContinue
    $n = (Select-String -Path $Log -Pattern 'ssdp:byebye' -ErrorAction SilentlyContinue | Measure-Object).Count
    Info "anunciante SSDP encerrado ($n linha(s) de byebye no log)"
}

function SsdpStart {
    if ((EnvValue 'SSDP_ENABLED').ToLower() -in @('false', '0')) { Info 'SSDP_ENABLED=false: anunciante nao sobe'; return }
    Build
    SsdpStop
    New-Item -ItemType Directory -Force $State | Out-Null
    Remove-Item $StopF -ErrorAction SilentlyContinue
    foreach ($k in $SsdpKeys) { $v = EnvValue $k; if ($v) { Set-Item "Env:$k" $v } }
    $env:SSDP_STOP_FILE = $StopF
    # o anunciante escreve no stderr; cada subida comeca o log de novo
    $opts = @{ FilePath = $Bin; PassThru = $true; RedirectStandardError = $Log; RedirectStandardOutput = "$Log.out" }
    if ($OnWindows) { $opts.WindowStyle = 'Hidden' }
    $p = Start-Process @opts
    Set-Content $PidF $p.Id
    Start-Sleep -Seconds 2
    if ($p.HasExited) { Get-Content $Log -Tail 5; Die 'o anunciante SSDP saiu logo depois de subir (log: .tv30/ssdp.log)' }
    $last = (Select-String -Path $Log -Pattern '^\[ssdp\]' | Select-Object -Last 1).Line
    Info "anunciante SSDP de pe (pid $($p.Id)): $last"
}

Set-Location $Root
switch ($Cmd) {
    'up'     {
        if ($UseWsl) { Info 'sem docker no PowerShell: usando o do WSL (wsl docker compose)' }
        New-Item -ItemType Directory -Force (Join-Path $State 'tls') | Out-Null
        DockerCmd compose up -d @Rest; if ($LASTEXITCODE) { Die 'docker compose up falhou' }
        SsdpStart
    }
    'down'   { SsdpStop; DockerCmd compose down @Rest }
    'status' {
        DockerCmd compose ps
        $p = AnnouncerProcess
        if ($p) { Info "anunciante SSDP: de pe (pid $($p.Id)); log em .tv30/ssdp.log" } else { Info 'anunciante SSDP: parado' }
    }
    'logs'   { Get-Content $Log -Tail 30 -Wait }
    'ssdp-build' { Build -Force; Info "binario em .tv30/bin/$Exe" }
    default  { Get-Content $PSCommandPath -TotalCount 6 | Select-Object -Skip 1 | ForEach-Object { $_ -replace '^# ?', '' }; exit 2 }
}
