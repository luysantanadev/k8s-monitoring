#!/usr/bin/env bash
# ==============================================================================
# SYNOPSIS
#   Verifica se todas as ferramentas do workshop estão instaladas e o daemon
#   do Docker está em execução.
#
# DESCRIPTION
#   Checa a presença de docker, k3d, kubectl e helm no PATH, exibe as versões
#   instaladas e confirma que o daemon do Docker está respondendo.
#
# NOTES
#   Execute em um novo terminal após rodar 01.install-dependencies.sh.
# ==============================================================================

set -euo pipefail

# Cores ANSI
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

ok=true

write_check() {
  local passed="$1"
  local label="$2"
  local detail="${3:-}"

  if [[ "$passed" == "true" ]]; then
    local status=" OK  "
    local color="$GREEN"
  else
    local status=" FALTANDO "
    local color="$RED"
  fi

  local suffix=""
  [[ -n "$detail" ]] && suffix="  ($detail)"
  echo -e "  [${color}${status}${RESET}]  ${label}${suffix}"
}

echo ""
echo -e "${CYAN}==> Ferramentas no PATH${RESET}"

for cmd in docker k3d kubectl helm; do
  if command -v "$cmd" &>/dev/null; then
    case "$cmd" in
      docker)  ver=$(docker  --version 2>&1 | head -1) ;;
      k3d)     ver=$(k3d     --version 2>&1 | head -1) ;;
      kubectl) ver=$(kubectl version --client 2>&1 | head -1) ;;
      helm)    ver=$(helm    version --short 2>&1 | head -1) ;;
    esac
    write_check "true" "$cmd" "$ver"
  else
    write_check "false" "$cmd"
    ok=false
  fi
done

echo ""
echo -e "${CYAN}==> Docker Daemon${RESET}"

if docker info &>/dev/null; then
  write_check "true" "daemon respondendo"
else
  write_check "false" "daemon não está rodando — inicie com: sudo systemctl start docker"
  ok=false
fi

echo ""
if [[ "$ok" == "true" ]]; then
  echo -e "  ${GREEN}Tudo pronto! Pode rodar: ./03.criar-cluster-k3d.sh${RESET}"
else
  echo -e "  ${RED}Corrija os itens acima antes de continuar.${RESET}"
  exit 1
fi
echo ""
