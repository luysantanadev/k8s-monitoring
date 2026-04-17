#Requires -Version 7.0
<#
.SYNOPSIS
    Instala HashiCorp Vault (modo dev) no namespace 'vault'.
.NOTES
    Namespace  : vault   | Release: vault
    Root Token : root    (dev mode — nao usar em producao)
    UI         : http://vault.k3d.localhost  (adicionar ao /etc/hosts)
    Metricas   : ServiceMonitor em /v1/sys/metrics (bearerToken=root)
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
Write-Step "Adicionando repositorio HashiCorp..."
helm repo add hashicorp https://helm.releases.hashicorp.com --force-update 2>&1 | Out-Null
helm repo update hashicorp 2>&1 | Out-Null
Write-Success "Repositorio pronto."

# ---------------------------------------------------------------------------
# 2. Namespace
# ---------------------------------------------------------------------------
Write-Step "Criando namespace 'vault'..."
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Success "Namespace pronto."

# ---------------------------------------------------------------------------
# 3. Vault
# ---------------------------------------------------------------------------
Write-Step "Instalando HashiCorp Vault 'vault'..."
helm upgrade --install vault hashicorp/vault `
    --namespace vault `
    --values "$scriptDir/values.yaml" `
    --wait --timeout 120s
if ($LASTEXITCODE -ne 0) { Write-Fail "Helm install falhou." }
Write-Success "Vault instalado."

# ---------------------------------------------------------------------------
# 4. Ingress HTTP
# ---------------------------------------------------------------------------
Write-Step "Criando Ingress HTTP para vault.k3d.localhost..."
@"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vault
  namespace: vault
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: vault.k3d.localhost
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: vault
                port:
                  number: 8200
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "Ingress nao aplicado." }
else { Write-Success "Vault UI em http://vault.k3d.localhost." }

# ---------------------------------------------------------------------------
# 5. Secret de metricas + ServiceMonitor
# ---------------------------------------------------------------------------
Write-Step "Criando Secret e ServiceMonitor para metricas..."
@"
apiVersion: v1
kind: Secret
metadata:
  name: vault-metrics-token
  namespace: vault
  labels:
    app.kubernetes.io/instance: vault
type: Opaque
stringData:
  token: "root"
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vault
  namespace: vault
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: vault
      app.kubernetes.io/instance: vault
  endpoints:
    - port: http
      interval: 30s
      path: /v1/sys/metrics
      params:
        format: [prometheus]
      bearerTokenSecret:
        name: vault-metrics-token
        key: token
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "Secret/ServiceMonitor nao aplicados." }
else { Write-Success "ServiceMonitor criado." }

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Vault pronto!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Namespace  : vault"
Write-Host "  Root Token : root  (dev mode)"
Write-Host "  UI         : http://vault.k3d.localhost"
Write-Host "  API        : http://vault.k3d.localhost/v1"
Write-Host ""
Write-Host "  Adicionar ao hosts (se necessario):" -ForegroundColor Yellow
Write-Host "    127.0.0.1  vault.k3d.localhost"
Write-Host ""
Write-Host "  Aguardar pronto:" -ForegroundColor Yellow
Write-Host "    kubectl -n vault get pods -w"
Write-Host ""
Write-Host "  AVISO: Modo dev — dados NAO persistem entre restarts." -ForegroundColor Yellow
Write-Host ""
