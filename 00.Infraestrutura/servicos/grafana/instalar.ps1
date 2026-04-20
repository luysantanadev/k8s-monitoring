#Requires -Version 7.0
<#
.SYNOPSIS
    Instala o stack de monitoramento completo no cluster Kubernetes.
.DESCRIPTION
    Instala kube-prometheus-stack, Loki, Tempo, Pyroscope e Alloy via Helm
    no namespace monitoring. Ao final aplica os datasources extras do Grafana.
.NOTES
    Arquivo : 04.configurar-monitoramento.ps1
    Prereqs : cluster monitoramento em execucao (03.criar-cluster-k3d.ps1)
    Proximo : adicionar entradas no hosts e acessar http://grafana.monitoramento.local
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$YamlsDir = Join-Path $PSScriptRoot '..\yamls'

# ── 1. Namespace ──────────────────────────────────────────────────────────────
Write-Host "`n[1/7] Criando namespace monitoring..." -ForegroundColor Cyan
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# ── 2. Helm repos ─────────────────────────────────────────────────────────────
Write-Host "`n[2/7] Adicionando repositorios Helm..." -ForegroundColor Cyan
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# ── 3. kube-prometheus-stack (Prometheus + Grafana + exporters) ───────────────
Write-Host "`n[3/7] Instalando kube-prometheus-stack..." -ForegroundColor Cyan
$ValuesFile = Join-Path $YamlsDir '05.01-kube-prometheus-stack.yaml'
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
    --namespace monitoring `
    --values $ValuesFile

# ── 4. Loki ───────────────────────────────────────────────────────────────────
Write-Host "`n[4/7] Instalando Loki..." -ForegroundColor Cyan
$ValuesFile = Join-Path $YamlsDir '05.02-loki.yaml'
helm upgrade --install loki grafana/loki `
    --namespace monitoring `
    --values $ValuesFile

# ── 5. Tempo ──────────────────────────────────────────────────────────────────
Write-Host "`n[5/7] Instalando Tempo..." -ForegroundColor Cyan
$ValuesFile = Join-Path $YamlsDir '05.03-tempo.yaml'
helm upgrade --install tempo grafana/tempo `
    --namespace monitoring `
    --values $ValuesFile

# ── 6. Pyroscope ──────────────────────────────────────────────────────────────
Write-Host "`n[6/7] Instalando Pyroscope..." -ForegroundColor Cyan
$ValuesFile = Join-Path $YamlsDir '05.04-pyroscope.yaml'
helm upgrade --install pyroscope grafana/pyroscope `
    --namespace monitoring `
    --values $ValuesFile

# ── 7. Alloy (coletor OpenTelemetry) ──────────────────────────────────────────
Write-Host "`n[7/7] Instalando Alloy..." -ForegroundColor Cyan
$ValuesFile = Join-Path $YamlsDir '05.05-alloy.yaml'
helm upgrade --install alloy grafana/alloy `
    --namespace monitoring `
    --values $ValuesFile

# ── Datasources extras (Loki, Tempo, Pyroscope no Grafana) ────────────────────
Write-Host "`nAplicando datasources extras no Grafana..." -ForegroundColor Cyan
$DatasourceFile = Join-Path $YamlsDir '05.06-grafana-datasource.yaml'
kubectl apply -f $DatasourceFile

# ── Ingresses (Traefik) ───────────────────────────────────────────────────────
Write-Host "`nAplicando Ingresses e IngressRoutesTCP..." -ForegroundColor Cyan
$IngressFile = Join-Path $YamlsDir '05.07-ingresses.yaml'
kubectl apply -f $IngressFile

# ── Resumo ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Stack de monitoramento instalado com sucesso!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host " Adicione as entradas abaixo no arquivo hosts do Windows:" -ForegroundColor Yellow
Write-Host " C:\Windows\System32\drivers\etc\hosts" -ForegroundColor Gray
Write-Host ""
Write-Host "   127.0.0.1   grafana.monitoramento.local" -ForegroundColor White
Write-Host "   127.0.0.1   loki.monitoramento.local" -ForegroundColor White
Write-Host "   127.0.0.1   tempo.monitoramento.local" -ForegroundColor White
Write-Host "   127.0.0.1   pyroscope.monitoramento.local" -ForegroundColor White
Write-Host ""
Write-Host " Acesso via browser:" -ForegroundColor Yellow
Write-Host "   Grafana    http://grafana.monitoramento.local       admin / workshop123" -ForegroundColor Cyan
Write-Host "   Tempo      http://tempo.monitoramento.local" -ForegroundColor Cyan
Write-Host "   Pyroscope  http://pyroscope.monitoramento.local" -ForegroundColor Cyan
Write-Host "   Loki       http://loki.monitoramento.local" -ForegroundColor Cyan
Write-Host ""
Write-Host " Variaveis de ambiente para a aplicacao local:" -ForegroundColor Yellow
Write-Host "   OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318" -ForegroundColor White
Write-Host "   OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf" -ForegroundColor White
Write-Host "   PYROSCOPE_SERVER_ADDRESS=http://pyroscope.monitoramento.local" -ForegroundColor White
Write-Host ""