#Requires -Version 7.0
<#
.SYNOPSIS
    Instala Keycloak (Bitnami OCI) no namespace 'keycloak'.
.NOTES
    Namespace  : keycloak  | Release: keycloak
    Admin      : admin / Workshop1!kc
    UI         : http://keycloak.k3d.localhost  (adicionar ao /etc/hosts)
    Metricas   : ServiceMonitor porta 9000 (via values.yaml)
    Idempotente: re-executar e seguro.
#>
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

function Write-Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "`n    ERRO: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# 1. Namespace
# ---------------------------------------------------------------------------
Write-Step "Criando namespace 'keycloak'..."
kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Success "Namespace pronto."

# ---------------------------------------------------------------------------
# 2. Keycloak (OCI chart — sem helm repo add)
# ---------------------------------------------------------------------------
Write-Step "Instalando Keycloak 'keycloak' (pode levar 3-5 min)..."
helm upgrade --install keycloak oci://registry-1.docker.io/bitnamicharts/keycloak `
    --namespace keycloak `
    --values "$scriptDir/values.yaml" `
    --wait --timeout 300s
if ($LASTEXITCODE -ne 0) { Write-Fail "Helm install falhou." }
Write-Success "Keycloak instalado."

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
Write-Host "  UI         : http://keycloak.k3d.localhost"
Write-Host "  OIDC       : http://keycloak.k3d.localhost/realms/master/.well-known/openid-configuration"
Write-Host ""
Write-Host "  Adicionar ao hosts (se necessario):" -ForegroundColor Yellow
Write-Host "    127.0.0.1  keycloak.k3d.localhost"
Write-Host ""
Write-Host "  Aguardar pronto:" -ForegroundColor Yellow
Write-Host "    kubectl -n keycloak get pods -w"
Write-Host ""
Write-Host "  AVISO: Modo HTTP (sem TLS) — apenas para workshop/desenvolvimento." -ForegroundColor Yellow
Write-Host ""
