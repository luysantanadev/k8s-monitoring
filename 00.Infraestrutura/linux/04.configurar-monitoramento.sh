#!/usr/bin/env bash
# ==============================================================================
# SYNOPSIS
#   Instala o stack de monitoramento completo no cluster Kubernetes.
#
# DESCRIPTION
#   Instala kube-prometheus-stack, Loki, Tempo, Pyroscope e Alloy via Helm
#   no namespace monitoring. Ao final aplica datasources e ingresses do Grafana.
#
# NOTES
#   Arquivo    : 04.configurar-monitoramento.sh
#   Pré-requisito: cluster monitoramento em execução (03.setup-k3d-multi-node.sh)
#   Próximo    : sudo bash 09.atualizar-hosts.sh  → acesso via browser
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAMLS_DIR="${SCRIPT_DIR}/../yamls"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'

write_step()    { echo -e "\n${CYAN}==> $1${RESET}"; }
write_success() { echo -e "    ${GREEN}OK: $1${RESET}"; }

# ── [1/7] Namespace ───────────────────────────────────────────────────────────
write_step "[1/7] Criando namespace monitoring..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f - >/dev/null
write_success "Namespace 'monitoring' pronto."

# ── [2/7] Helm repos ──────────────────────────────────────────────────────────
write_step "[2/7] Adicionando repositórios Helm..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update >/dev/null
write_success "Repositórios atualizados."

# ── [3/7] kube-prometheus-stack ───────────────────────────────────────────────
write_step "[3/7] Instalando kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --values "${YAMLS_DIR}/05.01-kube-prometheus-stack.yaml"
write_success "kube-prometheus-stack instalado."

# ── [4/7] Loki ────────────────────────────────────────────────────────────────
write_step "[4/7] Instalando Loki..."
helm upgrade --install loki grafana/loki \
    --namespace monitoring \
    --values "${YAMLS_DIR}/05.02-loki.yaml"
write_success "Loki instalado."

# ── [5/7] Tempo ───────────────────────────────────────────────────────────────
write_step "[5/7] Instalando Tempo..."
helm upgrade --install tempo grafana/tempo \
    --namespace monitoring \
    --values "${YAMLS_DIR}/05.03-tempo.yaml"
write_success "Tempo instalado."

# ── [6/7] Pyroscope ───────────────────────────────────────────────────────────
write_step "[6/7] Instalando Pyroscope..."
helm upgrade --install pyroscope grafana/pyroscope \
    --namespace monitoring \
    --values "${YAMLS_DIR}/05.04-pyroscope.yaml"
write_success "Pyroscope instalado."

# ── [7/7] Alloy ───────────────────────────────────────────────────────────────
write_step "[7/7] Instalando Alloy..."
helm upgrade --install alloy grafana/alloy \
    --namespace monitoring \
    --values "${YAMLS_DIR}/05.05-alloy.yaml"
write_success "Alloy instalado."

# ── Datasources extras ────────────────────────────────────────────────────────
write_step "Aplicando datasources extras no Grafana..."
kubectl apply -f "${YAMLS_DIR}/05.06-grafana-datasource.yaml"
write_success "Datasources aplicados."

# ── Ingresses (Traefik) ───────────────────────────────────────────────────────
write_step "Aplicando Ingresses e IngressRoutes..."
kubectl apply -f "${YAMLS_DIR}/05.07-ingresses.yaml"
write_success "Ingresses aplicados."

# ── Resumo ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}============================================================${RESET}"
echo -e "${GREEN} Stack de monitoramento instalado com sucesso!${RESET}"
echo -e "${GREEN}============================================================${RESET}"
echo ""
echo -e "${YELLOW} Adicione as entradas abaixo em /etc/hosts (requer sudo):${RESET}"
echo ""
echo "   127.0.0.1   grafana.monitoramento.local"
echo "   127.0.0.1   loki.monitoramento.local"
echo "   127.0.0.1   tempo.monitoramento.local"
echo "   127.0.0.1   pyroscope.monitoramento.local"
echo ""
echo -e "${YELLOW} Ou execute o script de atualização automática:${RESET}"
echo "   sudo bash 09.atualizar-hosts.sh"
echo ""
echo -e "${YELLOW} Acesso via browser (após atualizar /etc/hosts):${RESET}"
echo -e "   ${CYAN}Grafana    http://grafana.monitoramento.local       admin / workshop123${RESET}"
echo -e "   ${CYAN}Loki       http://loki.monitoramento.local${RESET}"
echo -e "   ${CYAN}Tempo      http://tempo.monitoramento.local${RESET}"
echo -e "   ${CYAN}Pyroscope  http://pyroscope.monitoramento.local${RESET}"
echo ""
echo -e "${YELLOW} Variáveis de ambiente para a aplicação local:${RESET}"
echo "   OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318"
echo "   OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf"
echo "   PYROSCOPE_SERVER_ADDRESS=http://pyroscope.monitoramento.local"
echo ""
