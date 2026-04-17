#!/usr/bin/env bash
# Instala Keycloak (imagem oficial quay.io) + PostgreSQL no namespace 'keycloak'.
#
# Namespace  : keycloak
# Admin      : admin / Workshop1!kc
# UI         : http://keycloak.monitoramento.local
# Metricas   : ServiceMonitor porta http /metrics
# Idempotente: re-executar e seguro.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==> $1${NC}"; }
ok()   { echo -e "    ${GREEN}OK: $1${NC}"; }
fail() { echo -e "\n    ${RED}ERRO: $1${NC}"; exit 1; }

# 1. Namespace
step "Criando namespace 'keycloak'..."
kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "Namespace pronto."

# 2. Aplicar manifests (PostgreSQL + Keycloak)
step "Aplicando manifests (PostgreSQL + Keycloak)..."
kubectl apply -f "$SCRIPT_DIR/manifest.yaml" || fail "kubectl apply falhou."
ok "Manifests aplicados."

# 3. Aguardar PostgreSQL
step "Aguardando PostgreSQL ficar pronto..."
kubectl rollout status deployment/keycloak-postgresql -n keycloak --timeout=120s \
    || fail "PostgreSQL nao iniciou a tempo."
ok "PostgreSQL pronto."

# 4. Aguardar Keycloak
step "Aguardando Keycloak ficar pronto (pode levar 2-3 min)..."
kubectl rollout status deployment/keycloak -n keycloak --timeout=300s \
    || fail "Keycloak nao iniciou a tempo."
ok "Keycloak pronto."

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Keycloak pronto!${NC}"
echo -e "${GREEN}============================================${NC}"
echo "  Namespace  : keycloak"
echo "  Admin      : admin"
echo "  Senha      : Workshop1!kc"
echo "  UI         : http://keycloak.monitoramento.local"
echo "  OIDC       : http://keycloak.monitoramento.local/realms/master/.well-known/openid-configuration"
echo ""
echo -e "  ${YELLOW}Adicionar ao hosts (se necessario):${NC}"
echo "    127.0.0.1  keycloak.monitoramento.local"
echo ""
echo -e "  ${YELLOW}Aguardar pronto:${NC}"
echo "    kubectl -n keycloak get pods -w"
echo ""
echo -e "  ${YELLOW}AVISO: Modo HTTP (sem TLS) — apenas para workshop/desenvolvimento.${NC}"
echo ""
