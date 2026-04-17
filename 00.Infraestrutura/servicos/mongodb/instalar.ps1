#Requires -Version 7.0
<#
.SYNOPSIS
    Instala MongoDB Community Operator + instancia no namespace 'mongodb'.
.NOTES
    Namespace  : mongodb   | Resource: mongodb
    Usuario    : workshop  | Banco: admin
    Senha      : Workshop123mongo
    Acesso TCP : localhost:27017  (entrypoint 'mongodb' no Traefik)
    Metricas   : ServiceMonitor porta 9216
    Idempotente: re-executar e seguro.
#>
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

function Write-Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "`n    ERRO: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# 1. MongoDB Community Operator
# ---------------------------------------------------------------------------
Write-Step "Instalando MongoDB Community Operator..."
helm repo add mongodb https://mongodb.github.io/helm-charts --force-update 2>&1 | Out-Null
helm repo update mongodb 2>&1 | Out-Null
helm upgrade --install community-operator mongodb/community-operator `
    --namespace mongodb-operator --create-namespace `
    --set operator.watchNamespace="*" `
    --wait --timeout 120s
if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao instalar MongoDB Community Operator." }
Write-Success "Operator pronto."

# ---------------------------------------------------------------------------
# 2. Namespace + manifests (Secrets + MongoDBCommunity)
# ---------------------------------------------------------------------------
Write-Step "Criando namespace 'mongodb'..."
kubectl create namespace mongodb --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Success "Namespace pronto."

Write-Step "Aplicando Secrets e MongoDBCommunity..."
kubectl apply -f "$scriptDir/manifest.yaml"
if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao aplicar manifest.yaml." }
Write-Success "Secrets e MongoDBCommunity aplicados."

# ---------------------------------------------------------------------------
# 3. IngressRouteTCP — expoe localhost:27017
# ---------------------------------------------------------------------------
Write-Step "Aplicando IngressRouteTCP (porta 27017)..."
@"
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: mongodb
  namespace: mongodb
spec:
  entryPoints:
    - mongodb
  routes:
    - match: HostSNI(``*``)
      services:
        - name: mongodb-svc
          port: 27017
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "IngressRouteTCP nao aplicado." }
else { Write-Success "MongoDB acessivel em localhost:27017." }

# ---------------------------------------------------------------------------
# 4. ServiceMonitor (Prometheus)
# ---------------------------------------------------------------------------
Write-Step "Criando ServiceMonitor..."
@"
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mongodb
  namespace: mongodb
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: mongodb
  endpoints:
    - port: prometheus
      interval: 30s
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "ServiceMonitor nao aplicado." }
else { Write-Success "ServiceMonitor criado." }

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  MongoDB pronto!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Namespace  : mongodb"
Write-Host "  Usuario    : workshop"
Write-Host "  Senha      : Workshop123mongo"
Write-Host "  Host local : localhost:27017"
Write-Host "  URI        : mongodb://workshop:Workshop123mongo@localhost:27017/?authSource=admin"
Write-Host ""
Write-Host "  Aguardar cluster pronto (pode levar 2-3 min):" -ForegroundColor Yellow
Write-Host "    kubectl -n mongodb get mongodbcommunity mongodb -w"
Write-Host ""
