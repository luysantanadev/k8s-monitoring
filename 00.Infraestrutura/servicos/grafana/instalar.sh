#!/bin/bash
# instalar.sh — Instala o stack de monitoramento completo no cluster Kubernetes.
#
# Instala kube-prometheus-stack, Loki, Tempo, Pyroscope e Alloy via Helm
# no namespace monitoring. Ao final aplica os datasources extras do Grafana.
#
# Prereqs : cluster monitoramento em execucao (03.criar-cluster-k3d.sh)
# Proximo : adicionar entradas no hosts e acessar http://grafana.monitoramento.local

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAMLS_DIR="${SCRIPT_DIR}/yamls"

# ── Helpers de output ─────────────────────────────────────────────────────────
cyan()  { [ -t 1 ] && printf '\033[0;36m%s\033[0m\n' "$*" || echo "$*"; }
green() { [ -t 1 ] && printf '\033[0;32m%s\033[0m\n' "$*" || echo "$*"; }
white() { [ -t 1 ] && printf '\033[1;37m%s\033[0m\n' "$*" || echo "$*"; }

# ── 1. Namespace ──────────────────────────────────────────────────────────────
cyan ""
cyan "[1/7] Criando namespace monitoring..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# ── 2. Helm repos ─────────────────────────────────────────────────────────────
cyan ""
cyan "[2/7] Adicionando repositorios Helm..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# ── 3. kube-prometheus-stack (Prometheus + Grafana + exporters) ───────────────
cyan ""
cyan "[3/7] Instalando kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --values "${YAMLS_DIR}/05.01-kube-prometheus-stack.yaml"

# ── 4. Loki ───────────────────────────────────────────────────────────────────
cyan ""
cyan "[4/7] Instalando Loki..."
helm upgrade --install loki grafana/loki \
    --namespace monitoring \
    --values "${YAMLS_DIR}/05.02-loki.yaml"

# ── 5. Tempo ──────────────────────────────────────────────────────────────────
cyan ""
cyan "[5/7] Instalando Tempo..."
helm upgrade --install tempo grafana/tempo \
    --namespace monitoring \
    --values "${YAMLS_DIR}/05.03-tempo.yaml"

# ── 6. Pyroscope ──────────────────────────────────────────────────────────────
cyan ""
cyan "[6/7] Instalando Pyroscope..."
helm upgrade --install pyroscope grafana/pyroscope \
    --namespace monitoring \
    --values "${YAMLS_DIR}/05.04-pyroscope.yaml"

# ── 7. Alloy (coletor OpenTelemetry) ──────────────────────────────────────────
cyan ""
cyan "[7/7] Instalando Alloy..."
helm upgrade --install alloy grafana/alloy \
    --namespace monitoring \
    --values "${YAMLS_DIR}/05.05-alloy.yaml"

# ── Datasources extras (Loki, Tempo, Pyroscope no Grafana) ────────────────────
cyan ""
cyan "Aplicando datasources extras no Grafana..."
kubectl apply -f "${YAMLS_DIR}/05.06-grafana-datasource.yaml"

# ── Ingresses (Traefik) ───────────────────────────────────────────────────────
cyan ""
cyan "Aplicando Ingresses e IngressRoutesTCP..."
kubectl apply -f "${YAMLS_DIR}/05.07-ingresses.yaml"

# ── Resumo ────────────────────────────────────────────────────────────────────
echo ""
green "============================================================"
green " Stack de monitoramento instalado com sucesso!"
green "============================================================"
echo ""
echo " Adicione as entradas abaixo no arquivo /etc/hosts:"
echo ""
white "   127.0.0.1   grafana.monitoramento.local"
white "   127.0.0.1   loki.monitoramento.local"
white "   127.0.0.1   tempo.monitoramento.local"
white "   127.0.0.1   pyroscope.monitoramento.local"
echo ""
cyan " Acesso via browser:"
cyan "   Grafana    http://grafana.monitoramento.local       admin / workshop123"
cyan "   Tempo      http://tempo.monitoramento.local"
cyan "   Pyroscope  http://pyroscope.monitoramento.local"
cyan "   Loki       http://loki.monitoramento.local"
echo ""
echo " Variaveis de ambiente para a aplicacao local:"
white "   OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318"
white "   OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf"
white "   PYROSCOPE_SERVER_ADDRESS=http://pyroscope.monitoramento.local"
echo ""
