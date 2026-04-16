#Requires -Version 7.0
<#
.SYNOPSIS
    Gerencia instancias Redis via Helm (bitnami/redis) no cluster k3d.

.DESCRIPTION
    - Adiciona o repositorio bitnami e atualiza os repos (idempotente).
    - Modo interativo: cria ou remove instancias Redis standalone.
      Criacao: solicita namespace e nome da instancia, gera senha aleatoria,
               instala via Helm e exibe o comando de port-forward.
      Remocao: lista instancias existentes por numero e remove a selecionada.

.EXAMPLE
    .\06.redis.ps1
    Executa o assistente interativo de gerenciamento de instancias Redis.

.NOTES
    Pre-requisito: cluster k3d 'monitoramento' em execucao (03.criar-cluster-k3d.ps1),
    kubectl e helm no PATH.
    Chart utilizado: bitnami/redis (standalone, sem replicas — adequado para workshop).
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "`n    ERRO: $msg" -ForegroundColor Red; exit 1 }

function New-RandomPassword {
    $bytes = [byte[]]::new(32)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    # Remove +/= para evitar problemas em connection strings e variaveis de ambiente
    $b64 = [Convert]::ToBase64String($bytes) -replace '[+/=]'
    return $b64.Substring(0, 24)
}

function Get-FreePort {
    param([int]$Min = 15000, [int]$Max = 20000)
    do {
        $port  = Get-Random -Minimum $Min -Maximum $Max
        $inUse = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    } while ($inUse)
    return $port
}

# Retorna todas as instancias Redis instaladas via Helm (chart bitnami/redis).
function Get-AllRedisInstances {
    $raw = helm list -A -o json 2>&1
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }
    try {
        $json = $raw | ConvertFrom-Json
        if (-not $json -or $json.Count -eq 0) { return @() }
        return @($json | Where-Object { $_.chart -like 'redis-*' } | ForEach-Object {
            [PSCustomObject]@{
                Namespace = $_.namespace
                Release   = $_.name
            }
        })
    } catch {
        return @()
    }
}

# ---------------------------------------------------------------------------
# 1. Repositorio Helm (idempotente)
# ---------------------------------------------------------------------------
Write-Step "Configurando repositorio bitnami..."

helm repo add bitnami https://charts.bitnami.com/bitnami 2>&1 | Out-Null
helm repo update 2>&1 | Out-Null

Write-Success "Repositorio bitnami atualizado."

# ---------------------------------------------------------------------------
# 2. Menu principal
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  O que deseja fazer?" -ForegroundColor Cyan
Write-Host "    [1] Criar instancia Redis"
Write-Host "    [2] Remover instancia Redis"
Write-Host ""

do {
    $action = (Read-Host "  Opcao").Trim()
} while ($action -notin @('1', '2'))

# ===========================================================================
# CRIAR INSTANCIA
# ===========================================================================
if ($action -eq '1') {

    # --- Namespace ---
    Write-Host ""
    $Namespace = ''
    do {
        $Namespace = (Read-Host "  Namespace").Trim()
    } while (-not $Namespace)

    kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f - | Out-Null
    Write-Success "Namespace '$Namespace' pronto."

    # --- Nome da instancia (unico no namespace) ---
    $allInstances = Get-AllRedisInstances
    $InstanceName = ''
    do {
        $inputName = (Read-Host "  Nome da instancia Redis").Trim().ToLower()
        if (-not $inputName) { continue }

        $alreadyExists = $allInstances | Where-Object {
            $_.Namespace -eq $Namespace -and $_.Release -eq $inputName
        }
        if ($alreadyExists) {
            Write-Warn "Ja existe uma instancia '$inputName' no namespace '$Namespace'. Escolha outro nome."
            continue
        }
        $InstanceName = $inputName
    } while (-not $InstanceName)

    # --- Derivar valores ---
    $Password  = New-RandomPassword
    $MasterSvc = "$InstanceName-redis-master"
    $LocalPort = Get-FreePort

    # --- Helm install ---
    Write-Step "Instalando Redis '$InstanceName' no namespace '$Namespace'..."
    helm upgrade --install $InstanceName bitnami/redis `
        --namespace $Namespace `
        --set auth.password=$Password `
        --set replica.replicaCount=0 `
        --set master.resources.requests.cpu=100m `
        --set master.resources.requests.memory=128Mi `
        --set master.resources.limits.cpu=500m `
        --set master.resources.limits.memory=256Mi `
        --set master.persistence.size=512Mi

    if ($LASTEXITCODE -ne 0) { Write-Fail "Helm install falhou. Verifique os logs acima." }
    Write-Success "Instancia Redis '$InstanceName' criada."

    # --- Resumo ---
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  Instancia Redis criada com sucesso!" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Namespace : $Namespace"
    Write-Host "  Instancia : $InstanceName"
    Write-Host "  Senha     : $Password"
    Write-Host ""
    Write-Host "  Connection string interna:" -ForegroundColor Yellow
    Write-Host "    redis://:${Password}@${MasterSvc}.${Namespace}.svc.cluster.local:6379"
    Write-Host ""
    Write-Host "  Comando para abrir o port-forward (porta $LocalPort):" -ForegroundColor Yellow
    Write-Host "    kubectl port-forward -n $Namespace svc/$MasterSvc ${LocalPort}:6379"
    Write-Host ""
    Write-Host "  REDIS_URL local:" -ForegroundColor Yellow
    Write-Host "    redis://:${Password}@localhost:${LocalPort}"
    Write-Host ""
}

# ===========================================================================
# REMOVER INSTANCIA
# ===========================================================================
if ($action -eq '2') {

    $instances = @(Get-AllRedisInstances)

    if ($instances.Count -eq 0) {
        Write-Host ""
        Write-Warn "Nenhuma instancia Redis encontrada no cluster."
        exit 0
    }

    Write-Host ""
    Write-Host "  Instancias Redis existentes:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $instances.Count; $i++) {
        Write-Host "    [$($i + 1)]  $($instances[$i].Namespace) / $($instances[$i].Release)"
    }
    Write-Host ""

    $max = $instances.Count
    do {
        $sel = (Read-Host "  Numero da instancia a remover (1-$max)").Trim()
    } while ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $max)

    $chosen    = $instances[[int]$sel - 1]
    $ns        = $chosen.Namespace
    $release   = $chosen.Release

    Write-Step "Removendo instancia Redis '$release' do namespace '$ns'..."

    helm uninstall $release --namespace $ns
    if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao remover o release Helm '$release'." }

    # O chart bitnami/redis nao remove o PVC automaticamente; avisar o usuario
    Write-Warn "PVC do Redis pode ter ficado para tras. Para remover:"
    Write-Warn "  kubectl -n $ns delete pvc -l app.kubernetes.io/instance=$release"

    Write-Success "Instancia Redis '$release' removida do namespace '$ns'."
    Write-Host ""
}
