#!/usr/bin/env bash
# Instala Keycloak (Bitnami OCI) no namespace 'keycloak'.
#
# Namespace  : keycloak  | Release: keycloak
# Admin      : admin / Workshop1!kc
# UI         : http://keycloak.k3d.localhost
# Metricas   : ServiceMonitor porta 9000 (via values.yaml)
# Idempotente: re-executar e seguro.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==> $1${NC}"; }
ok()   { echo -e "    ${GREEN}OK: $1${NC}"; }
warn() { echo -e "    ${YELLOW}AVISO: $1${NC}"; }
fail() { echo -e "\n    ${RED}ERRO: $1${NC}"; exit 1; }

# 1. Namespace
step "Criando namespace 'keycloak'..."
kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "Namespace pronto."

# 2. Keycloak (OCI chart — sem helm repo add)
step "Instalando Keycloak 'keycloak' (pode levar 3-5 min)..."
helm upgrade --install keycloak oci://registry-1.docker.io/bitnamicharts/keycloak \
    --namespace keycloak \
    --values "$SCRIPT_DIR/values.yaml" \
    --wait --timeout 300s \
    || fail "Helm install falhou."
ok "Keycloak instalado."

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Keycloak pronto!${NC}"
echo -e "${GREEN}============================================${NC}"
echo "  Namespace  : keycloak"
echo "  Admin      : admin"
echo "  Senha      : Workshop1!kc"
echo "  UI         : http://keycloak.k3d.localhost"
echo "  OIDC       : http://keycloak.k3d.localhost/realms/master/.well-known/openid-configuration"
echo ""
echo -e "  ${YELLOW}Adicionar ao hosts (se necessario):${NC}"
echo "    127.0.0.1  keycloak.k3d.localhost"
echo ""
echo -e "  ${YELLOW}Aguardar pronto:${NC}"
echo "    kubectl -n keycloak get pods -w"
echo ""
echo -e "  ${YELLOW}AVISO: Modo HTTP (sem TLS) — apenas para workshop/desenvolvimento.${NC}"
echo ""
