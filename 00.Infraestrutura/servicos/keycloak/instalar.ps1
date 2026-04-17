#Requires -Version 7.0
<#
.SYNOPSIS
    Instala Keycloak (imagem oficial quay.io) + PostgreSQL no namespace 'keycloak'.
.NOTES
    Namespace  : keycloak
    Admin      : admin / Workshop1!kc
    UI         : http://keycloak.monitoramento.local  (adicionar ao /etc/hosts)
    Metricas   : ServiceMonitor porta http /metrics
    Idempotente: re-executar e seguro.
#>
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

function Write-Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Fail($msg)    { Write-Host "`n    ERRO: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# 1. Namespace
# ---------------------------------------------------------------------------
Write-Step "Criando namespace 'keycloak'..."
kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Success "Namespace pronto."

# ---------------------------------------------------------------------------
# 2. Aplicar manifests (PostgreSQL + Keycloak)
# ---------------------------------------------------------------------------
Write-Step "Aplicando manifests (PostgreSQL + Keycloak)..."
kubectl apply -f "$scriptDir/manifest.yaml"
if ($LASTEXITCODE -ne 0) { Write-Fail "kubectl apply falhou." }
Write-Success "Manifests aplicados."

# ---------------------------------------------------------------------------
# 3. Aguardar PostgreSQL
# ---------------------------------------------------------------------------
Write-Step "Aguardando PostgreSQL ficar pronto..."
kubectl rollout status deployment/keycloak-postgresql -n keycloak --timeout=120s
if ($LASTEXITCODE -ne 0) { Write-Fail "PostgreSQL nao iniciou a tempo." }
Write-Success "PostgreSQL pronto."

# ---------------------------------------------------------------------------
# 4. Aguardar Keycloak
# ---------------------------------------------------------------------------
Write-Step "Aguardando Keycloak ficar pronto (pode levar 2-3 min)..."
kubectl rollout status deployment/keycloak -n keycloak --timeout=300s
if ($LASTEXITCODE -ne 0) { Write-Fail "Keycloak nao iniciou a tempo." }
Write-Success "Keycloak pronto."

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Keycloak pronto!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Namespace  : keycloak"
Write-Host "  Admin      : admin"
Write-Host "  Senha      : Workshop1!kc"
Write-Host "  UI         : http://keycloak.monitoramento.local"
Write-Host "  OIDC       : http://keycloak.monitoramento.local/realms/master/.well-known/openid-configuration"
Write-Host ""
Write-Host "  Adicionar ao hosts (se necessario):" -ForegroundColor Yellow
Write-Host "    127.0.0.1  keycloak.monitoramento.local"
Write-Host ""
Write-Host "  Aguardar pronto:" -ForegroundColor Yellow
Write-Host "    kubectl -n keycloak get pods -w"
Write-Host ""
Write-Host "  AVISO: Modo HTTP (sem TLS) — apenas para workshop/desenvolvimento." -ForegroundColor Yellow
Write-Host ""
