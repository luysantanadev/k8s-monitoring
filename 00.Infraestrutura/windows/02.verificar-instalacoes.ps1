#Requires -Version 7.0
<#
.SYNOPSIS
    Verifica se todas as ferramentas do workshop estão instaladas e o Docker Desktop está em execução.

.DESCRIPTION
    Checa a presença de docker, k3d, kubectl e helm no PATH, exibe as versões instaladas
    e confirma que o daemon do Docker está respondendo.

.EXAMPLE
    .\02.verificar-instalacoes.ps1
    Executa todas as verificações e exibe o resultado.

.NOTES
    Execute em um novo terminal após rodar 01.instalar-dependencias.ps1 e abrir o Docker Desktop.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ok = $true

# Recarrega o PATH do registro do Windows antes de qualquer verificação.
# Necessário quando o terminal foi aberto antes ou logo após as instalações
# do winget propagarem os valores no registro do usuário.
$machinePath = [System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::Machine) ?? ''
$userPath    = [System.Environment]::GetEnvironmentVariable('Path', [System.EnvironmentVariableTarget]::User)   ?? ''
$env:Path    = ($machinePath + ';' + $userPath) -replace ';{2,}', ';'

# Flags de versão por ferramenta — cada uma tem sua própria convenção.
# kubectl --short foi removido na versão 1.29; usa-se apenas --client.
$versionArgs = @{
    docker  = @('--version')
    k3d     = @('--version')
    kubectl = @('version', '--client')
    helm    = @('version', '--short')
}

function Write-Check {
    param([bool]$Passed, [string]$Label, [string]$Detail = "")
    $status = if ($Passed) { " OK  " } else { " FALTANDO " }
    $color  = if ($Passed) { "Green" } else { "Red" }
    $suffix = if ($Detail) { "  ($Detail)" } else { "" }
    Write-Host "  [$status]  $Label$suffix" -ForegroundColor $color
}

Write-Host ""
Write-Host "==> Ferramentas no PATH" -ForegroundColor Cyan

foreach ($cmd in @("docker", "k3d", "kubectl", "helm")) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        $ver = & $cmd @($versionArgs[$cmd]) 2>&1 | Select-Object -First 1
        Write-Check -Passed $true -Label $cmd -Detail $ver
    } else {
        Write-Check -Passed $false -Label $cmd
        $ok = $false
    }
}

Write-Host ""
Write-Host "==> Docker Desktop" -ForegroundColor Cyan

$null = docker info 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Check -Passed $true -Label "daemon respondendo"
} else {
    Write-Check -Passed $false -Label "daemon nao esta rodando — abra o Docker Desktop primeiro"
    $ok = $false
}

Write-Host ""
if ($ok) {
    Write-Host "  Tudo pronto! Pode rodar: .\03.setup-k3d-multi-node.ps1" -ForegroundColor Green
} else {
    Write-Host "  Corrija os itens acima antes de continuar." -ForegroundColor Red
    exit 1
}
Write-Host ""