#Requires -Version 7.0
<#
.SYNOPSIS
    Atualiza o arquivo hosts do Windows com todas as entradas de Ingress do cluster k3d.

.DESCRIPTION
    Gerencia um bloco marcado no arquivo hosts (C:\Windows\System32\drivers\etc\hosts)
    com todas as entradas necessarias para acessar os servicos do cluster via navegador.

    Entradas ESTATICAS (sempre presentes quando o monitoramento estiver instalado):
      127.0.0.1   grafana.monitoramento.local
      127.0.0.1   loki.monitoramento.local
      127.0.0.1   tempo.monitoramento.local
      127.0.0.1   pyroscope.monitoramento.local

    Entradas DINAMICAS (descobertas consultando o cluster):
      Todos os hosts de recursos Ingress existentes no cluster.
      Ex: 127.0.0.1   minha-app-ravendb.k3d.localhost

    O script e IDEMPOTENTE: re-executar substitui o bloco sem duplicar linhas.
    Requer execucao como Administrador (necessario para editar o arquivo hosts).

.EXAMPLE
    .\09.atualizar-hosts.ps1
    Atualiza o hosts com as entradas estaticas + todas as descobertas no cluster.

.EXAMPLE
    .\09.atualizar-hosts.ps1 -Remover
    Remove o bloco gerenciado do arquivo hosts.

.NOTES
    O bloco no hosts e delimitado por:
      # --- k8s-monitoramento BEGIN ---
      # --- k8s-monitoramento END ---
    Nao edite manualmente as linhas dentro do bloco.
#>
[CmdletBinding()]
param(
    [switch]$Remover
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "`n    ERRO: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# 1. Verificar privilegios de Administrador
# ---------------------------------------------------------------------------
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "  Este script precisa ser executado como Administrador." -ForegroundColor Yellow
    Write-Host "  Tentando elevar privilegios automaticamente..." -ForegroundColor Yellow
    Write-Host ""

    $psArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($Remover) { $psArgs += " -Remover" }

    Start-Process pwsh -Verb RunAs -ArgumentList $psArgs
    exit 0
}

# ---------------------------------------------------------------------------
# 2. Configuracoes
# ---------------------------------------------------------------------------
$HostsFile   = "$env:SystemRoot\System32\drivers\etc\hosts"
$BlockBegin  = "# --- k8s-monitoramento BEGIN ---"
$BlockEnd    = "# --- k8s-monitoramento END ---"
$Ip          = "127.0.0.1"

# Entradas fixas — presentes independentemente do que esta no cluster
$StaticHosts = @(
    "grafana.monitoramento.local"
    "loki.monitoramento.local"
    "tempo.monitoramento.local"
    "pyroscope.monitoramento.local"
)

# ---------------------------------------------------------------------------
# 3. Ler o arquivo hosts atual
# ---------------------------------------------------------------------------
Write-Step "Lendo $HostsFile ..."

if (-not (Test-Path $HostsFile)) {
    Write-Fail "Arquivo hosts nao encontrado: $HostsFile"
}

$hostsContent = Get-Content $HostsFile -Encoding UTF8 -Raw
if (-not $hostsContent) { $hostsContent = '' }

# ---------------------------------------------------------------------------
# 4. Modo remocao: apagar apenas o bloco gerenciado
# ---------------------------------------------------------------------------
if ($Remover) {
    if ($hostsContent -notmatch [regex]::Escape($BlockBegin)) {
        Write-Warn "Bloco gerenciado nao encontrado no arquivo hosts. Nada a remover."
        exit 0
    }

    $pattern = "(?ms)[\r\n]*$([regex]::Escape($BlockBegin)).*?$([regex]::Escape($BlockEnd))[\r\n]*"
    $newContent = $hostsContent -replace $pattern, "`r`n"

    $newContent | Set-Content $HostsFile -Encoding UTF8 -NoNewline
    Write-Success "Bloco k8s-monitoramento removido do arquivo hosts."
    exit 0
}

# ---------------------------------------------------------------------------
# 5. Descobrir hosts dinamicos consultando o cluster
# ---------------------------------------------------------------------------
Write-Step "Consultando Ingresses no cluster k3d..."

$dynamicHosts = @()

$ingressRaw = kubectl get ingress -A -o json 2>&1
if ($LASTEXITCODE -eq 0 -and $ingressRaw) {
    try {
        $ingressJson = $ingressRaw | ConvertFrom-Json
        foreach ($item in $ingressJson.items) {
            foreach ($rule in $item.spec.rules) {
                if ($rule.host -and $rule.host -notin $StaticHosts -and $rule.host -notin $dynamicHosts) {
                    $dynamicHosts += $rule.host
                }
            }
        }
    } catch {
        Write-Warn "Nao foi possivel parsear os Ingresses do cluster: $_"
    }
} else {
    Write-Warn "kubectl nao retornou Ingresses (cluster pode estar desligado)."
    Write-Warn "Apenas as entradas estaticas serao adicionadas."
}

$allHosts = $StaticHosts + $dynamicHosts | Sort-Object -Unique

# ---------------------------------------------------------------------------
# 6. Construir o novo bloco
# ---------------------------------------------------------------------------
$blockLines = @($BlockBegin)
$blockLines += "# Gerado automaticamente por 09.atualizar-hosts.ps1 em $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$blockLines += "# Nao edite manualmente as linhas dentro deste bloco."
$blockLines += ""

foreach ($host in $allHosts) {
    $blockLines += "$Ip`t$host"
}

$blockLines += $BlockEnd
$newBlock = $blockLines -join "`r`n"

# ---------------------------------------------------------------------------
# 7. Substituir ou inserir o bloco no arquivo hosts
# ---------------------------------------------------------------------------
Write-Step "Atualizando $HostsFile ..."

if ($hostsContent -match [regex]::Escape($BlockBegin)) {
    # Bloco ja existe: substituir
    $pattern    = "(?ms)$([regex]::Escape($BlockBegin)).*?$([regex]::Escape($BlockEnd))"
    $newContent = $hostsContent -replace $pattern, $newBlock
} else {
    # Bloco ainda nao existe: acrescentar ao final
    $newContent = $hostsContent.TrimEnd() + "`r`n`r`n" + $newBlock + "`r`n"
}

# Fazer backup antes de salvar
$backup = "$HostsFile.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $HostsFile $backup
Write-Warn "Backup salvo em $backup"

$newContent | Set-Content $HostsFile -Encoding UTF8 -NoNewline

# ---------------------------------------------------------------------------
# 8. Resumo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Arquivo hosts atualizado com sucesso!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Entradas estaticas (monitoramento):" -ForegroundColor Cyan
foreach ($h in $StaticHosts) {
    Write-Host "    $Ip  $h"
}

if ($dynamicHosts.Count -gt 0) {
    Write-Host ""
    Write-Host "  Entradas dinamicas (descobertas no cluster):" -ForegroundColor Cyan
    foreach ($h in $dynamicHosts) {
        Write-Host "    $Ip  $h"
    }
} else {
    Write-Host ""
    Write-Warn "Nenhuma entrada dinamica encontrada (sem Ingresses extras no cluster)."
}

Write-Host ""
Write-Host "  Para remover todas as entradas gerenciadas:" -ForegroundColor Yellow
Write-Host "    .\09.atualizar-hosts.ps1 -Remover"
Write-Host ""
