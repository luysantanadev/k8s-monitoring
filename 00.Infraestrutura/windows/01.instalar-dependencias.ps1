#Requires -Version 7.0
<#
.SYNOPSIS
    Instala ou atualiza todas as ferramentas necessárias para Kubernetes local com k3d.

.DESCRIPTION
    Execução totalmente não-interativa: aceita termos e licenças automaticamente.
    - Ferramenta não instalada        → instala.
    - Instalada com update disponível → atualiza.
    - Já na versão mais recente       → prossegue sem alteração.

    Docker Desktop é verificado e instalado automaticamente. Requer UAC apenas
    para essa etapa. k3d, kubectl e Helm são instalados no escopo do usuário,
    sem necessidade de Administrador.

.EXAMPLE
    .\01.instalar-dependencias.ps1
    Verifica e instala Docker Desktop, k3d, kubectl e Helm.

.NOTES
    Pré-requisito: winget (App Installer) disponível no PATH.
    Após a execução, feche o terminal para que as variáveis de PATH sejam aplicadas.
#>

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "`n    ERRO: $msg" -ForegroundColor Red; exit 1 }

# Códigos de saída do winget que indicam "tudo certo, nada a fazer" — não são erros reais.
# 0x8A150014 (-1978335212) = pacote já instalado nessa versão (install)
# 0x8A150011 (-1978335215) = nenhuma atualização aplicável      (upgrade)
# 0x8A15002B (-1978335189) = pacote instalado fora do gerenciamento do winget
$script:WingetOkCodes = @(0, -1978335212, -1978335215, -1978335189)

function Install-Or-Upgrade {
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [Parameter(Mandatory)][string]$DisplayName,
        [switch]$UserScope
    )

    Write-Step "$DisplayName"

    $wingetArgs = @(
        '--id', $PackageId,
        '--exact',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity',
        '--silent'
    )
    if ($UserScope) { $wingetArgs += @('--scope', 'user') }

    # Tenta atualizar primeiro; se o pacote ainda não estiver instalado,
    # winget upgrade retorna código desconhecido e caímos no install abaixo.
    winget upgrade @wingetArgs 2>&1 | Out-Null
    if ($script:WingetOkCodes -contains $LASTEXITCODE) {
        if ($LASTEXITCODE -eq 0) { Write-Success "$DisplayName atualizado." }
        else                     { Write-Success "$DisplayName já está na versão mais recente." }
        return
    }

    winget install @wingetArgs 2>&1 | Out-Null
    if ($script:WingetOkCodes -notcontains $LASTEXITCODE) {
        Write-Fail "Falha ao instalar '$DisplayName' (ID: $PackageId, código de saída: $LASTEXITCODE)"
    }
    Write-Success "$DisplayName instalado."
}

function Install-DockerDesktop {
    Write-Step "Docker Desktop (instalacao de sistema — requer UAC)"

    # Se já estiver instalado (por qualquer meio), não toca — evita UAC desnecessário.
    winget list --id Docker.DockerDesktop --exact --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Docker Desktop ja esta instalado. Pulando."
        return
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    $pkgArgs = @(
        '--id', 'Docker.DockerDesktop', '--exact',
        '--accept-package-agreements', '--accept-source-agreements',
        '--disable-interactivity', '--silent'
    )

    if ($isAdmin) {
        winget install @pkgArgs 2>&1 | Out-Null
        if ($script:WingetOkCodes -notcontains $LASTEXITCODE) {
            Write-Fail "Falha ao instalar Docker Desktop (codigo de saida: $LASTEXITCODE)"
        }
    } else {
        Write-Host "    Solicitando UAC apenas para Docker Desktop..." -ForegroundColor Yellow

        # EncodedCommand evita problemas de escaping ao passar script para o processo elevado.
        $elevatedScript = @'
$okCodes = @(0, -1978335212, -1978335215, -1978335189)
$pkgArgs = @('--id','Docker.DockerDesktop','--exact','--accept-package-agreements','--accept-source-agreements','--disable-interactivity','--silent')
winget install @pkgArgs 2>&1 | Out-Null; $ec = $LASTEXITCODE
exit $(if ($okCodes -contains $ec) { 0 } else { $ec })
'@
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($elevatedScript))
        $proc = Start-Process pwsh -Verb RunAs -Wait -PassThru `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"

        if ($proc.ExitCode -ne 0) {
            Write-Fail "Falha ao instalar Docker Desktop (codigo de saida: $($proc.ExitCode))"
        }
    }

    Write-Success "Docker Desktop instalado."
}

# ---------------------------------------------------------------------------
# 0. Verificar pré-requisito: winget disponível e fontes atualizadas
# ---------------------------------------------------------------------------
Write-Step "Verificando winget..."
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Fail "winget nao encontrado.`n  Solucao: instale o 'App Installer' pela Microsoft Store ou atualize o Windows 10/11."
}

winget source update --disable-interactivity 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Warn "Nao foi possivel atualizar as fontes do winget. Prosseguindo com cache local."
} else {
    Write-Success "Fontes do winget atualizadas."
}

# ---------------------------------------------------------------------------
# 1. Docker Desktop — verificação automática, requer elevação (UAC sob demanda)
# ---------------------------------------------------------------------------
Install-DockerDesktop

# ---------------------------------------------------------------------------
# 2. CLIs — instalados no escopo do usuário, sem elevação necessária
# ---------------------------------------------------------------------------
Install-Or-Upgrade -PackageId "k3d.k3d"            -DisplayName "k3d"     -UserScope
Install-Or-Upgrade -PackageId "Kubernetes.kubectl"  -DisplayName "kubectl" -UserScope
Install-Or-Upgrade -PackageId "Helm.Helm"           -DisplayName "Helm"    -UserScope

# ---------------------------------------------------------------------------
# 3. Próximos passos
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Ferramentas instaladas/atualizadas com sucesso!"           -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "PROXIMOS PASSOS:" -ForegroundColor Yellow
Write-Host "  1. Feche este terminal para aplicar as variaveis de PATH"  -ForegroundColor Yellow
Write-Host "  2. Abra o Docker Desktop e aguarde o icone estabilizar"    -ForegroundColor Yellow
Write-Host "  3. Abra um novo terminal e rode: .\02.verificar-instalacoes.ps1" -ForegroundColor Yellow
Write-Host ""
Write-Host "Pressione qualquer tecla para fechar..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")