#!/usr/bin/env bash
# Instala SonarQube Community no namespace 'sonarqube'.
#
# Namespace  : sonarqube  | Release: sonarqube
# DB         : sonarqube-postgresql (Postgres 17) | Senha: Workshop123sonar
# Admin      : admin / Workshop_1_sonar
# UI         : http://sonarqube.monitoramento.local
# Metricas   : PodMonitor (via values.yaml)
# Idempotente: re-executar e seguro.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==> $1${NC}"; }
ok()   { echo -e "    ${GREEN}OK: $1${NC}"; }
warn() { echo -e "    ${YELLOW}AVISO: $1${NC}"; }
fail() { echo -e "\n    ${RED}ERRO: $1${NC}"; exit 1; }

# 1. Helm repo
step "Adicionando repositorio SonarSource..."
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube --force-update 2>/dev/null || true
helm repo update sonarqube 2>/dev/null
ok "Repositorio pronto."

# 2. Namespace
step "Criando namespace 'sonarqube'..."
kubectl create namespace sonarqube --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "Namespace pronto."

# 3. PostgreSQL
step "Aplicando PostgreSQL para SonarQube (manifest.yaml)..."
kubectl apply -f "$SCRIPT_DIR/manifest.yaml" || fail "kubectl apply manifest.yaml falhou."
step "Aguardando PostgreSQL ficar pronto..."
kubectl rollout status deployment/sonarqube-postgresql -n sonarqube --timeout=120s \
    || fail "PostgreSQL nao iniciou a tempo."
ok "PostgreSQL pronto."

# 4. SonarQube
step "Instalando SonarQube 'sonarqube' (pode levar 3-5 min)..."
helm upgrade --install sonarqube sonarqube/sonarqube \
    --namespace sonarqube \
    --values "$SCRIPT_DIR/values.yaml" \
    --wait \
    --timeout 300s \
    || fail "Helm install falhou."
ok "SonarQube instalado."

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  SonarQube pronto!${NC}"
echo -e "${GREEN}============================================${NC}"
echo "  Namespace      : sonarqube"
echo "  DB             : sonarqube-postgresql / Workshop123sonar"
echo "  Admin          : admin"
echo "  Senha          : Workshop_1_sonar"
echo "  UI             : http://sonarqube.monitoramento.local"
echo "  Monitoring code: sonarWorkshop123"
echo ""
echo -e "  ${YELLOW}Adicionar ao hosts (se necessario):${NC}"
echo "    127.0.0.1  sonarqube.monitoramento.local"
echo ""
echo -e "  ${YELLOW}Aguardar pronto:${NC}"
echo "    kubectl -n sonarqube get pods -w"
echo ""
