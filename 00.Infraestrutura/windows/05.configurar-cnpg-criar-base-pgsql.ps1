#Requires -Version 7.0
<#
.SYNOPSIS
    Gerencia bases de dados PostgreSQL via CloudNativePG no cluster k3d.

.DESCRIPTION
    - Instala o CNPG operator via Helm se ainda nao estiver presente (idempotente).
    - Modo interativo: cria ou remove clusters PostgreSQL.
      Criacao: solicita namespace e nome da base, gera usuario e senha aleatorios,
               instala via Helm e exibe o comando de port-forward.
      Remocao: lista bases existentes por numero e remove a selecionada.

.EXAMPLE
    .\05.configurar-cnpg-criar-base-pgsql.ps1
    Executa o assistente interativo de gerenciamento de bases.

.NOTES
    Pre-requisito: cluster k3d 'monitoramento' em execucao (03.criar-cluster-k3d.ps1),
    monitoramento instalado (04.configurar-monitoramento.ps1) — necessario para ServiceMonitor.
    kubectl e helm no PATH.
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

# Retorna todos os clusters CNPG do cluster k8s como array de objetos tipados.
function Get-AllClusters {
    $raw = kubectl get cluster -A -o json 2>&1
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }
    try {
        $json = $raw | ConvertFrom-Json
        if (-not $json.items -or $json.items.Count -eq 0) { return @() }
        return @($json.items | ForEach-Object {
            [PSCustomObject]@{
                Namespace = $_.metadata.namespace
                Release   = $_.metadata.name -replace '-cluster$', ''
            }
        })
    } catch {
        return @()
    }
}

# ---------------------------------------------------------------------------
# 1. Instalar / verificar CloudNativePG operator (idempotente)
# ---------------------------------------------------------------------------
Write-Step "Verificando CloudNativePG operator..."

helm repo add cnpg https://cloudnative-pg.github.io/charts 2>&1 | Out-Null
helm repo update 2>&1 | Out-Null

helm upgrade --install cnpg cnpg/cloudnative-pg `
    --namespace cnpg-system `
    --create-namespace `
    --wait `
    --timeout 120s

if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao instalar o CloudNativePG operator." }

$cnpgReadyRaw = kubectl -n cnpg-system get deployment cnpg-cloudnative-pg `
    -o jsonpath='{.status.readyReplicas}' 2>&1
$cnpgReady = 0
if (-not [int]::TryParse($cnpgReadyRaw, [ref]$cnpgReady) -or $cnpgReady -lt 1) {
    Write-Fail "CNPG operator nao esta pronto. Verifique: kubectl -n cnpg-system get pods"
}
Write-Success "CNPG operator pronto ($cnpgReady replica(s))."

# ---------------------------------------------------------------------------
# 2. Menu principal
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  O que deseja fazer?" -ForegroundColor Cyan
Write-Host "    [1] Criar base de dados"
Write-Host "    [2] Remover base de dados"
Write-Host ""

do {
    $action = (Read-Host "  Opcao").Trim()
} while ($action -notin @('1', '2'))

# ===========================================================================
# CRIAR BASE
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

    # --- Nome da base (unico no namespace) ---
    $allClusters = Get-AllClusters
    $Database = ''
    do {
        $dbName = (Read-Host "  Nome da base de dados").Trim().ToLower()
        if (-not $dbName) { continue }

        $alreadyExists = $allClusters | Where-Object {
            $_.Namespace -eq $Namespace -and $_.Release -eq $dbName
        }
        if ($alreadyExists) {
            Write-Warn "Ja existe uma base '$dbName' no namespace '$Namespace'. Escolha outro nome."
            continue
        }
        $Database = $dbName
    } while (-not $Database)

    # --- Derivar valores ---
    $Username   = $Database
    $Password   = New-RandomPassword
    $SecretName = "$Database-credentials"
    $rwSvc      = "$Database-cluster-rw"

    # --- Secret de credenciais ---
    Write-Step "Criando Secret de credenciais '$SecretName'..."
    kubectl -n $Namespace create secret generic $SecretName `
        --from-literal=username=$Username `
        --from-literal=password=$Password `
        --dry-run=client -o yaml | kubectl apply -f - | Out-Null
    Write-Success "Secret criado."

    # --- Helm install ---
    Write-Step "Instalando cluster PostgreSQL '$Database' no namespace '$Namespace'..."
    helm upgrade --install $Database cnpg/cluster `
        --namespace $Namespace `
        --set cluster.instances=1 `
        --set cluster.storage.size=1Gi `
        --set cluster.initdb.database=$Database `
        --set cluster.initdb.owner=$Username `
        --set cluster.initdb.secret.name=$SecretName `
        --set-string cluster.postgresql.parameters.max_connections=200 `
        --wait `
        --timeout 180s

    if ($LASTEXITCODE -ne 0) { Write-Fail "Helm install falhou. Verifique os logs acima." }
    Write-Success "Cluster PostgreSQL pronto."

    # --- IngressRouteTCP (expoe localhost:5432 via Traefik) ---
    Write-Step "Aplicando IngressRouteTCP para PostgreSQL (porta 5432)..."
    $tcpManifest = @"
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: postgres-$Database
  namespace: $Namespace
  labels:
    app: $Database
    managed-by: 05.configurar-cnpg-criar-base-pgsql
spec:
  entryPoints:
    - postgres
  routes:
    - match: HostSNI(``*``)
      services:
        - name: $rwSvc
          port: 5432
"@
    $tcpManifest | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { Write-Warn "IngressRouteTCP nao aplicado. Porta 5432 pode ja estar em uso por outra instancia." }
    else { Write-Success "IngressRouteTCP aplicado. PostgreSQL acessivel em localhost:5432." }

    # --- ServiceMonitor (Prometheus) ---
    # CNPG cria automaticamente o servico $Database-cluster-metrics (porta 9187) para cada cluster.
    # O ServiceMonitor instrui o Prometheus a coletar metricas desse endpoint.
    Write-Step "Criando ServiceMonitor para PostgreSQL '$Database'..."
    $smCnpg = @"
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: postgres-$Database
  namespace: $Namespace
  labels:
    app: $Database
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      cnpg.io/cluster: $Database-cluster
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
"@
    $smCnpg | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { Write-Warn "ServiceMonitor nao aplicado. Metricas do PostgreSQL nao serao coletadas." }
    else { Write-Success "ServiceMonitor criado. Metricas disponiveis no Grafana." }

    # --- Resumo ---
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  Base de dados criada com sucesso!" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Namespace : $Namespace"
    Write-Host "  Base      : $Database"
    Write-Host "  Usuario   : $Username"
    Write-Host "  Senha     : $Password"
    Write-Host ""
    Write-Host "  Connection string interna:" -ForegroundColor Yellow
    Write-Host "    postgresql://${Username}:${Password}@${rwSvc}.${Namespace}.svc.cluster.local:5432/${Database}"
    Write-Host ""
    Write-Host "  DATABASE_URL local (via Traefik):" -ForegroundColor Yellow
    Write-Host "    postgresql://${Username}:${Password}@localhost:5432/${Database}"
    Write-Host ""
    Write-Warn "Nota: apenas uma instancia PostgreSQL pode ser exposta na porta 5432 por vez."
    Write-Host ""
}

# ===========================================================================
# REMOVER BASE
# ===========================================================================
if ($action -eq '2') {

    $clusters = @(Get-AllClusters)

    if ($clusters.Count -eq 0) {
        Write-Host ""
        Write-Warn "Nenhuma base de dados encontrada no cluster."
        exit 0
    }

    Write-Host ""
    Write-Host "  Bases de dados existentes:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $clusters.Count; $i++) {
        Write-Host "    [$($i + 1)]  $($clusters[$i].Namespace) / $($clusters[$i].Release)"
    }
    Write-Host ""

    $max = $clusters.Count
    do {
        $sel = (Read-Host "  Numero da base a remover (1-$max)").Trim()
    } while ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $max)

    $chosen  = $clusters[[int]$sel - 1]
    $ns      = $chosen.Namespace
    $release = $chosen.Release

    Write-Step "Removendo base '$release' do namespace '$ns'..."

    helm uninstall $release --namespace $ns
    if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao remover o release Helm '$release'." }

    kubectl -n $ns delete secret "$release-credentials" --ignore-not-found | Out-Null
    kubectl -n $ns delete ingressroutetcp "postgres-$release" --ignore-not-found | Out-Null
    kubectl -n $ns delete servicemonitor "postgres-$release" --ignore-not-found | Out-Null

    Write-Success "Base '$release' removida do namespace '$ns'."
    Write-Host ""
}
