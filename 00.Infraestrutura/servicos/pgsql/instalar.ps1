#Requires -Version 7.0
<#
.SYNOPSIS
    Instala PostgreSQL via CloudNativePG no namespace 'pgsql'.
.NOTES
    Namespace  : pgsql       | Release  : pgsql
    Banco      : workshop    | Usuario  : workshop
    Senha      : Workshop123pgsql
    Acesso TCP : localhost:5432  (entrypoint 'postgres' no Traefik)
    Metricas   : ServiceMonitor porta 9187
    Idempotente: re-executar e seguro.
#>
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

function Write-Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "`n    ERRO: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# 1. CloudNativePG Operator
# ---------------------------------------------------------------------------
Write-Step "Instalando CloudNativePG operator (namespace cnpg-system)..."
helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update 2>&1 | Out-Null
helm repo update cnpg 2>&1 | Out-Null
helm upgrade --install cnpg cnpg/cloudnative-pg `
    --namespace cnpg-system --create-namespace --wait --timeout 120s
if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao instalar CNPG operator." }
Write-Success "CNPG operator pronto."

# ---------------------------------------------------------------------------
# 2. Namespace + credenciais
# ---------------------------------------------------------------------------
Write-Step "Criando namespace 'pgsql' e Secret de credenciais..."
kubectl create namespace pgsql --dry-run=client -o yaml | kubectl apply -f - | Out-Null
kubectl -n pgsql create secret generic pgsql-credentials `
    --from-literal=username=workshop `
    --from-literal=password=Workshop123pgsql `
    --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Success "Namespace e Secret prontos."

# ---------------------------------------------------------------------------
# 3. Cluster PostgreSQL
# ---------------------------------------------------------------------------
Write-Step "Instalando cluster PostgreSQL 'pgsql'..."
helm upgrade --install pgsql cnpg/cluster `
    --namespace pgsql `
    --values "$scriptDir/values.yaml" `
    --wait --timeout 180s
if ($LASTEXITCODE -ne 0) { Write-Fail "Helm install falhou." }
Write-Success "Cluster PostgreSQL criado."

# ---------------------------------------------------------------------------
# 4. IngressRouteTCP — expoe localhost:5432
# ---------------------------------------------------------------------------
Write-Step "Aplicando IngressRouteTCP (porta 5432)..."
@"
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: pgsql
  namespace: pgsql
spec:
  entryPoints:
    - postgres
  routes:
    - match: HostSNI(``*``)
      services:
        - name: pgsql-cluster-rw
          port: 5432
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "IngressRouteTCP nao aplicado." }
else { Write-Success "PostgreSQL acessivel em localhost:5432." }

# ---------------------------------------------------------------------------
# 5. ServiceMonitor (Prometheus)
# ---------------------------------------------------------------------------
Write-Step "Criando ServiceMonitor..."
@"
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: pgsql
  namespace: pgsql
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      cnpg.io/cluster: pgsql
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "ServiceMonitor nao aplicado." }
else { Write-Success "ServiceMonitor criado." }

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  PostgreSQL pronto!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Namespace : pgsql"
Write-Host "  Banco     : workshop"
Write-Host "  Usuario   : workshop"
Write-Host "  Senha     : Workshop123pgsql"
Write-Host "  Host local: localhost:5432"
Write-Host "  JDBC URL  : jdbc:postgresql://localhost:5432/workshop"
Write-Host ""
Write-Host "  Aguardar cluster pronto:" -ForegroundColor Yellow
Write-Host "    kubectl -n pgsql get cluster pgsql -w"
Write-Host ""
