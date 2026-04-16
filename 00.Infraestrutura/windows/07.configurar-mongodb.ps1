#Requires -Version 7.0
<#
.SYNOPSIS
    Gerencia instancias MongoDB via Community Operator no cluster k3d.

.DESCRIPTION
    - Instala o MongoDB Community Operator via Helm se ainda nao estiver presente (idempotente).
    - Modo interativo: cria ou remove instancias MongoDB (ReplicaSet com 1 membro).
      Criacao: solicita namespace e nome da instancia, gera usuario e senha aleatorios,
               aplica os manifestos via kubectl e exibe o comando de port-forward.
      Remocao: lista instancias existentes por numero e remove a selecionada.

.EXAMPLE
    .\07.mongodb.ps1
    Executa o assistente interativo de gerenciamento de instancias MongoDB.

.NOTES
    Pre-requisito: cluster k3d 'monitoramento' em execucao (03.criar-cluster-k3d.ps1),
    kubectl e helm no PATH.
    Chart utilizado: mongodb/community-operator (MongoDB Inc., open-source Apache 2.0).
    CRD criado: MongoDBCommunity  |  Porta: 27017  |  Service: <nome>-svc
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

# Retorna todas as instancias MongoDBCommunity do cluster k8s como array de objetos tipados.
function Get-AllMongoInstances {
    $raw = kubectl get mongodbcommunity -A -o json 2>&1
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }
    try {
        $json = $raw | ConvertFrom-Json
        if (-not $json.items -or $json.items.Count -eq 0) { return @() }
        return @($json.items | ForEach-Object {
            [PSCustomObject]@{
                Namespace = $_.metadata.namespace
                Name      = $_.metadata.name
            }
        })
    } catch {
        return @()
    }
}

# ---------------------------------------------------------------------------
# 1. Instalar / verificar MongoDB Community Operator (idempotente)
# ---------------------------------------------------------------------------
Write-Step "Verificando MongoDB Community Operator..."

helm repo add mongodb https://mongodb.github.io/helm-charts 2>&1 | Out-Null
helm repo update 2>&1 | Out-Null

helm upgrade --install community-operator mongodb/community-operator `
    --namespace mongodb-operator `
    --create-namespace `
    --set operator.watchNamespace="*" `
    --wait `
    --timeout 120s

if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao instalar o MongoDB Community Operator." }

$opReadyRaw = kubectl -n mongodb-operator get deployment mongodb-kubernetes-operator `
    -o jsonpath='{.status.readyReplicas}' 2>&1
$opReady = 0
if (-not [int]::TryParse($opReadyRaw, [ref]$opReady) -or $opReady -lt 1) {
    Write-Fail "MongoDB Community Operator nao esta pronto. Verifique: kubectl -n mongodb-operator get pods"
}
Write-Success "MongoDB Community Operator pronto ($opReady replica(s))."

# ---------------------------------------------------------------------------
# 2. Menu principal
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  O que deseja fazer?" -ForegroundColor Cyan
Write-Host "    [1] Criar instancia MongoDB"
Write-Host "    [2] Remover instancia MongoDB"
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
    $allInstances = Get-AllMongoInstances
    $InstanceName = ''
    do {
        $inputName = (Read-Host "  Nome da instancia MongoDB").Trim().ToLower()
        if (-not $inputName) { continue }

        $alreadyExists = $allInstances | Where-Object {
            $_.Namespace -eq $Namespace -and $_.Name -eq $inputName
        }
        if ($alreadyExists) {
            Write-Warn "Ja existe uma instancia '$inputName' no namespace '$Namespace'. Escolha outro nome."
            continue
        }
        $InstanceName = $inputName
    } while (-not $InstanceName)

    # --- Derivar valores ---
    $Username        = $InstanceName
    $Password        = New-RandomPassword
    $MetricsPassword = New-RandomPassword
    $Svc             = "$InstanceName-svc"

    # --- Manifestos: Secret + MongoDBCommunity ---
    Write-Step "Aplicando Secret e MongoDBCommunity '$InstanceName' no namespace '$Namespace'..."

    $manifest = @"
apiVersion: v1
kind: Secret
metadata:
  name: $InstanceName-password
  namespace: $Namespace
type: Opaque
stringData:
  password: "$Password"
---
apiVersion: v1
kind: Secret
metadata:
  name: $InstanceName-metrics-password
  namespace: $Namespace
type: Opaque
stringData:
  password: "$MetricsPassword"
---
apiVersion: mongodbcommunity.mongodb.com/v1
kind: MongoDBCommunity
metadata:
  name: $InstanceName
  namespace: $Namespace
spec:
  members: 1
  type: ReplicaSet
  version: "7.0.14"
  security:
    authentication:
      modes: ["SCRAM"]
  users:
    - name: $Username
      db: admin
      passwordSecretRef:
        name: $InstanceName-password
      roles:
        - name: readWriteAnyDatabase
          db: admin
        - name: dbAdminAnyDatabase
          db: admin
      scramCredentialsSecretName: $InstanceName-scram
  prometheus:
    passwordSecretRef:
      name: $InstanceName-metrics-password
  statefulSet:
    spec:
      template:
        spec:
          containers:
            - name: mongod
              resources:
                requests:
                  cpu: 100m
                  memory: 256Mi
                limits:
                  cpu: 500m
                  memory: 512Mi
"@

    $manifest | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { Write-Fail "kubectl apply falhou. Verifique os logs acima." }
    Write-Success "Manifesto aplicado. O operator vai provisionar o pod em background."

    # --- Resumo ---
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  Instancia MongoDB criada com sucesso!" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Namespace : $Namespace"
    Write-Host "  Instancia : $InstanceName"
    Write-Host "  Usuario   : $Username"
    Write-Host "  Senha     : $Password"
    Write-Host ""
    # --- IngressRouteTCP (expoe localhost:27017 via Traefik) ---
    Write-Step "Aplicando IngressRouteTCP para MongoDB (porta 27017)..."
    $tcpManifest = @"
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: mongodb-$InstanceName
  namespace: $Namespace
  labels:
    app: $InstanceName
    managed-by: 07.mongodb
spec:
  entryPoints:
    - mongodb
  routes:
    - match: HostSNI(``*``)
      services:
        - name: $Svc
          port: 27017
"@
    $tcpManifest | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { Write-Warn "IngressRouteTCP nao aplicado. Porta 27017 pode ja estar em uso por outra instancia." }
    else { Write-Success "IngressRouteTCP aplicado. MongoDB acessivel em localhost:27017." }

    # --- ServiceMonitor (Prometheus) ---
    # O Community Operator com spec.prometheus habilita o mongodb_exporter na porta 9216.
    # O port name no Service e 'prometheus' (convencao do operator).
    Write-Step "Criando ServiceMonitor para MongoDB '$InstanceName'..."
    $smMongo = @"
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mongodb-$InstanceName
  namespace: $Namespace
  labels:
    app: $InstanceName
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: $InstanceName
  endpoints:
    - port: prometheus
      interval: 30s
      path: /metrics
"@
    $smMongo | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { Write-Warn "ServiceMonitor nao aplicado. Metricas do MongoDB nao serao coletadas." }
    else { Write-Success "ServiceMonitor criado. Metricas disponiveis no Grafana." }

    Write-Host "  Aguardar o pod ficar pronto:" -ForegroundColor Yellow
    Write-Host "    kubectl -n $Namespace get mongodbcommunity $InstanceName -w"
    Write-Host ""
    Write-Host "  Connection string interna:" -ForegroundColor Yellow
    Write-Host "    mongodb://${Username}:${Password}@${Svc}.${Namespace}.svc.cluster.local:27017/admin?authSource=admin"
    Write-Host ""
    Write-Host "  MONGODB_URL local (via Traefik):" -ForegroundColor Yellow
    Write-Host "    mongodb://${Username}:${Password}@localhost:27017/admin?authSource=admin&directConnection=true"
    Write-Host ""
    Write-Warn "Nota: apenas uma instancia MongoDB pode ser exposta na porta 27017 por vez."
    Write-Host ""
}

# ===========================================================================
# REMOVER INSTANCIA
# ===========================================================================
if ($action -eq '2') {

    $instances = @(Get-AllMongoInstances)

    if ($instances.Count -eq 0) {
        Write-Host ""
        Write-Warn "Nenhuma instancia MongoDB encontrada no cluster."
        exit 0
    }

    Write-Host ""
    Write-Host "  Instancias MongoDB existentes:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $instances.Count; $i++) {
        Write-Host "    [$($i + 1)]  $($instances[$i].Namespace) / $($instances[$i].Name)"
    }
    Write-Host ""

    $max = $instances.Count
    do {
        $sel = (Read-Host "  Numero da instancia a remover (1-$max)").Trim()
    } while ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $max)

    $chosen    = $instances[[int]$sel - 1]
    $ns        = $chosen.Namespace
    $name      = $chosen.Name

    Write-Step "Removendo instancia MongoDB '$name' do namespace '$ns'..."

    kubectl -n $ns delete mongodbcommunity $name --ignore-not-found
    if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao remover o MongoDBCommunity '$name'." }

    kubectl -n $ns delete secret "$name-password" "$name-scram" "$name-metrics-password" --ignore-not-found | Out-Null
    kubectl -n $ns delete ingressroutetcp "mongodb-$name" --ignore-not-found | Out-Null
    kubectl -n $ns delete servicemonitor "mongodb-$name" --ignore-not-found | Out-Null

    # O operator nao remove o PVC automaticamente; avisar o usuario
    Write-Warn "PVC do MongoDB pode ter ficado para tras. Para remover:"
    Write-Warn "  kubectl -n $ns delete pvc -l app=$name"

    Write-Success "Instancia MongoDB '$name' removida do namespace '$ns'."
    Write-Host ""
}
