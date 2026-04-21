#!/usr/bin/env bash
# Instala PostgreSQL via CloudNativePG no namespace 'pgsql'.
#
# Namespace  : pgsql       | Release  : pgsql
# Banco      : workshop    | Usuario  : workshop
# Senha      : Workshop123pgsql
# Acesso TCP : localhost:5432  (entrypoint 'postgres' no Traefik)
# Metricas   : ServiceMonitor porta 9187
# Idempotente: re-executar e seguro.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==> $1${NC}"; }
ok()   { echo -e "    ${GREEN}OK: $1${NC}"; }
warn() { echo -e "    ${YELLOW}AVISO: $1${NC}"; }
fail() { echo -e "\n    ${RED}ERRO: $1${NC}"; exit 1; }

# 1. CloudNativePG Operator
step "Instalando CloudNativePG operator (namespace cnpg-system)..."
helm repo add cnpg https://cloudnative-pg.github.io/charts --force-update 2>/dev/null || true
helm repo update cnpg 2>/dev/null
helm upgrade --install cnpg cnpg/cloudnative-pg \
    --namespace cnpg-system --create-namespace \
    || fail "Falha ao instalar CNPG operator."
ok "CNPG operator pronto."

# 2. Namespace + credenciais
step "Criando namespace 'pgsql' e Secret de credenciais..."
kubectl create namespace pgsql --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n pgsql create secret generic pgsql-credentials \
    --from-literal=username=workshop \
    --from-literal=password=Workshop123pgsql \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "Namespace e Secret prontos."

# 3. Cluster PostgreSQL
step "Instalando cluster PostgreSQL 'pgsql'..."
helm upgrade --install pgsql cnpg/cluster \
    --namespace pgsql \
    --values "$SCRIPT_DIR/values.yaml" \
    || fail "Helm install falhou."
ok "Cluster PostgreSQL criado."

# 4. IngressRouteTCP — expoe localhost:5432
step "Aplicando IngressRouteTCP (porta 5432)..."
kubectl apply -f - <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: pgsql
  namespace: pgsql
spec:
  entryPoints:
    - postgres
  routes:
    - match: HostSNI(`*`)
      services:
        - name: pgsql-cluster-rw
          port: 5432
EOF
ok "PostgreSQL acessivel em localhost:5432."

# 5. ServiceMonitor
step "Criando ServiceMonitor..."
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: pgsql
  namespace: pgsql
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      cnpg.io/cluster: pgsql
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
EOF
ok "ServiceMonitor criado."

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  PostgreSQL pronto!${NC}"
echo -e "${GREEN}============================================${NC}"
echo "  Namespace : pgsql"
echo "  Banco     : workshop"
echo "  Usuario   : workshop"
echo "  Senha     : Workshop123pgsql"
echo "  Host local: localhost:5432"
echo "  JDBC URL  : jdbc:postgresql://localhost:5432/workshop"
echo ""
echo -e "  ${YELLOW}Aguardar cluster pronto:${NC}"
echo "    kubectl -n pgsql get cluster pgsql -w"
echo ""
