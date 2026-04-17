#Requires -Version 7.0
<#
.SYNOPSIS
    Instala RavenDB no namespace 'ravendb'.
.NOTES
    Namespace  : ravendb   | Release: ravendb
    Modo       : Nao-seguro (workshop/dev) — sem TLS, sem autenticacao
    UI         : http://ravendb.monitoramento.local  (adicionar ao /etc/hosts)
    Metricas   : ServiceMonitor em /metrics porta 8080
    Licenca    : Editar services/ravendb/values.yaml (campo ravendb.license)
    Idempotente: re-executar e seguro.
#>
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

function Write-Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "`n    ERRO: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# 1. Helm repo
# ---------------------------------------------------------------------------
Write-Step "Adicionando repositorio RavenDB..."
helm repo add ravendb https://ravendb.github.io/helm-charts --force-update 2>&1 | Out-Null
helm repo update ravendb 2>&1 | Out-Null
Write-Success "Repositorio pronto."

# ---------------------------------------------------------------------------
# 2. Namespace
# ---------------------------------------------------------------------------
Write-Step "Criando namespace 'ravendb'..."
kubectl create namespace ravendb --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Success "Namespace pronto."

# ---------------------------------------------------------------------------
# 3. RavenDB
# ---------------------------------------------------------------------------
Write-Step "Instalando RavenDB 'ravendb'..."
helm upgrade --install ravendb ravendb/ravendb-cluster `
    --namespace ravendb `
    --values "$scriptDir/values.yaml" `
    --wait --timeout 180s
if ($LASTEXITCODE -ne 0) { Write-Fail "Helm install falhou." }
Write-Success "RavenDB instalado."

# ---------------------------------------------------------------------------
# 4. Ingress HTTP (porta 8080 via porta 80)
# ---------------------------------------------------------------------------
Write-Step "Criando Ingress HTTP para ravendb.monitoramento.local..."
@"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ravendb
  namespace: ravendb
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: ravendb.monitoramento.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ravendb-ravendb-cluster
                port:
                  number: 8080
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "Ingress nao aplicado." }
else { Write-Success "RavenDB Studio em http://ravendb.monitoramento.local." }

# ---------------------------------------------------------------------------
# 5. ServiceMonitor (Prometheus — metricas nativas em /metrics)
# ---------------------------------------------------------------------------
Write-Step "Criando ServiceMonitor..."
@"
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ravendb
  namespace: ravendb
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/instance: ravendb
  endpoints:
    - port: http
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
Write-Host "  RavenDB pronto!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Namespace  : ravendb"
Write-Host "  Modo       : Nao-seguro (dev/workshop)"
Write-Host "  UI         : http://ravendb.monitoramento.local"
Write-Host ""
Write-Host "  Adicionar ao hosts (se necessario):" -ForegroundColor Yellow
Write-Host "    127.0.0.1  ravendb.monitoramento.local"
Write-Host ""
Write-Host "  Aguardar pronto:" -ForegroundColor Yellow
Write-Host "    kubectl -n ravendb get pods -w"
Write-Host ""
Write-Host "  NOTA: Para adicionar licenca, edite values.yaml (campo ravendb.license)" -ForegroundColor Yellow
Write-Host "        e re-execute este script." -ForegroundColor Yellow
Write-Host ""
