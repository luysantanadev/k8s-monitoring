#Requires -Version 7.0
<#
.SYNOPSIS
    Instala Redis (Bitnami standalone) no namespace 'redis'.
.NOTES
    Namespace  : redis   | Release: redis
    Senha      : Workshop123redis
    Acesso TCP : localhost:6379  (entrypoint 'redis' no Traefik)
    Metricas   : ServiceMonitor porta 9121 (via values.yaml)
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
Write-Step "Adicionando repositorio Bitnami..."
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update 2>&1 | Out-Null
helm repo update bitnami 2>&1 | Out-Null
Write-Success "Repositorio pronto."

# ---------------------------------------------------------------------------
# 2. Namespace
# ---------------------------------------------------------------------------
Write-Step "Criando namespace 'redis'..."
kubectl create namespace redis --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Success "Namespace pronto."

# ---------------------------------------------------------------------------
# 3. Redis
# ---------------------------------------------------------------------------
Write-Step "Instalando Redis 'redis'..."
helm upgrade --install redis bitnami/redis `
    --namespace redis `
    --values "$scriptDir/values.yaml" `
    --wait --timeout 120s
if ($LASTEXITCODE -ne 0) { Write-Fail "Helm install falhou." }
Write-Success "Redis instalado."

# ---------------------------------------------------------------------------
# 4. IngressRouteTCP — expoe localhost:6379
# ---------------------------------------------------------------------------
Write-Step "Aplicando IngressRouteTCP (porta 6379)..."
@"
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: redis
  namespace: redis
spec:
  entryPoints:
    - redis
  routes:
    - match: HostSNI(``*``)
      services:
        - name: redis-master
          port: 6379
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "IngressRouteTCP nao aplicado." }
else { Write-Success "Redis acessivel em localhost:6379." }

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Redis pronto!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Namespace  : redis"
Write-Host "  Senha      : Workshop123redis"
Write-Host "  Host local : localhost:6379"
Write-Host "  URI        : redis://:Workshop123redis@localhost:6379"
Write-Host ""
Write-Host "  Aguardar pronto:" -ForegroundColor Yellow
Write-Host "    kubectl -n redis get pods -w"
Write-Host ""
