#!/usr/bin/env bash
# ==============================================================================
# SYNOPSIS
#   Instala o stack de monitoramento completo no cluster Kubernetes.
#
# DESCRIPTION
#   Wrapper que delega a instalação para o script dedicado em servicos/grafana/.
#   O stack (kube-prometheus-stack, Loki, Tempo, Pyroscope, Alloy, datasources
#   e ingresses) é gerenciado em 00.Infraestrutura/servicos/grafana/instalar.sh.
#
# NOTES
#   Pré-requisito: cluster monitoramento em execução (03.criar-cluster-k3d.sh)
#   Próximo    : sudo bash 09.atualizar-hosts.sh  → acesso via browser
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'

write_step() { echo -e "\n${CYAN}==> $1${RESET}"; }

GRAFANA_SCRIPT="${SCRIPT_DIR}/../servicos/grafana/instalar.sh"

if [[ ! -f "$GRAFANA_SCRIPT" ]]; then
    echo -e "\n    ${CYAN}ERRO: Script não encontrado: ${GRAFANA_SCRIPT}${RESET}"
    exit 1
fi

write_step "Delegando para servicos/grafana/instalar.sh..."
bash "$GRAFANA_SCRIPT"

