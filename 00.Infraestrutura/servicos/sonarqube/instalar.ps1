#Requires -Version 7.0
<#
.SYNOPSIS
    Instala SonarQube Community no namespace 'sonarqube'.
.NOTES
    Namespace  : sonarqube  | Release: sonarqube
    Admin      : admin / Workshop_1_sonar
    UI         : http://sonarqube.monitoramento.local  (adicionar ao /etc/hosts)
    Metricas   : PodMonitor (via values.yaml)
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
Write-Step "Adicionando repositorio SonarSource..."
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube --force-update 2>&1 | Out-Null
helm repo update sonarqube 2>&1 | Out-Null
Write-Success "Repositorio pronto."

# ---------------------------------------------------------------------------
# 2. Namespace
# ---------------------------------------------------------------------------
Write-Step "Criando namespace 'sonarqube'..."
kubectl create namespace sonarqube --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Success "Namespace pronto."

# ---------------------------------------------------------------------------
# 3. SonarQube
# ---------------------------------------------------------------------------
Write-Step "Instalando SonarQube 'sonarqube' (pode levar 3-5 min)..."
helm upgrade --install sonarqube sonarqube/sonarqube `
    --namespace sonarqube `
    --values "$scriptDir/values.yaml" `
    --wait --timeout 300s
if ($LASTEXITCODE -ne 0) { Write-Fail "Helm install falhou." }
Write-Success "SonarQube instalado."

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  SonarQube pronto!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Namespace      : sonarqube"
Write-Host "  Admin          : admin"
Write-Host "  Senha          : Workshop_1_sonar"
Write-Host "  UI             : http://sonarqube.monitoramento.local"
Write-Host "  Monitoring code: sonarWorkshop123"
Write-Host ""
Write-Host "  Adicionar ao hosts (se necessario):" -ForegroundColor Yellow
Write-Host "    127.0.0.1  sonarqube.monitoramento.local"
Write-Host ""
Write-Host "  Aguardar pronto:" -ForegroundColor Yellow
Write-Host "    kubectl -n sonarqube get pods -w"
Write-Host ""
