#!/usr/bin/env bash
# Instala MongoDB Community Operator + instancia no namespace 'mongodb'.
#
# Namespace  : mongodb   | Resource: mongodb
# Usuario    : workshop  | Banco: admin
# Senha      : Workshop123mongo
# Acesso TCP : localhost:27017  (entrypoint 'mongodb' no Traefik)
# Metricas   : ServiceMonitor porta 9216
# Idempotente: re-executar e seguro.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==> $1${NC}"; }
ok()   { echo -e "    ${GREEN}OK: $1${NC}"; }
warn() { echo -e "    ${YELLOW}AVISO: $1${NC}"; }
fail() { echo -e "\n    ${RED}ERRO: $1${NC}"; exit 1; }

# 1. MongoDB Community Operator
step "Instalando MongoDB Community Operator..."
helm repo add mongodb https://mongodb.github.io/helm-charts --force-update 2>/dev/null || true
helm repo update mongodb 2>/dev/null
helm upgrade --install community-operator mongodb/community-operator \
    --namespace mongodb-operator --create-namespace \
    --set operator.watchNamespace="*" \
    --wait --timeout 120s \
    || fail "Falha ao instalar MongoDB Community Operator."
ok "Operator pronto."

# 2. Namespace + manifests
step "Criando namespace 'mongodb'..."
kubectl create namespace mongodb --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "Namespace pronto."

step "Aplicando Secrets e MongoDBCommunity..."
kubectl apply -f "$SCRIPT_DIR/manifest.yaml" || fail "Falha ao aplicar manifest.yaml."
ok "Secrets e MongoDBCommunity aplicados."

# 3. IngressRouteTCP — expoe localhost:27017
step "Aplicando IngressRouteTCP (porta 27017)..."
kubectl apply -f - <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: mongodb
  namespace: mongodb
spec:
  entryPoints:
    - mongodb
  routes:
    - match: HostSNI(`*`)
      services:
        - name: mongodb-svc
          port: 27017
EOF
ok "MongoDB acessivel em localhost:27017."

# 4. ServiceMonitor
step "Criando ServiceMonitor..."
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mongodb
  namespace: mongodb
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: mongodb
  endpoints:
    - port: prometheus
      interval: 30s
EOF
ok "ServiceMonitor criado."

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  MongoDB pronto!${NC}"
echo -e "${GREEN}============================================${NC}"
echo "  Namespace  : mongodb"
echo "  Usuario    : workshop"
echo "  Senha      : Workshop123mongo"
echo "  Host local : localhost:27017"
echo "  URI        : mongodb://workshop:Workshop123mongo@localhost:27017/?authSource=admin"
echo ""
echo -e "  ${YELLOW}Aguardar cluster pronto (pode levar 2-3 min):${NC}"
echo "    kubectl -n mongodb get mongodbcommunity mongodb -w"
echo ""
