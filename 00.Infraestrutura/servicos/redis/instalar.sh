#!/usr/bin/env bash
# Instala Redis (Bitnami standalone) no namespace 'redis'.
#
# Namespace  : redis   | Release: redis
# Senha      : Workshop123redis
# Acesso TCP : localhost:6379  (entrypoint 'redis' no Traefik)
# Metricas   : ServiceMonitor porta 9121 (via values.yaml)
# Idempotente: re-executar e seguro.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==> $1${NC}"; }
ok()   { echo -e "    ${GREEN}OK: $1${NC}"; }
warn() { echo -e "    ${YELLOW}AVISO: $1${NC}"; }
fail() { echo -e "\n    ${RED}ERRO: $1${NC}"; exit 1; }

# 1. Helm repo
step "Adicionando repositorio Bitnami..."
helm repo add bitnami https://charts.bitnami.com/bitnami --force-update 2>/dev/null || true
helm repo update bitnami 2>/dev/null
ok "Repositorio pronto."

# 2. Namespace
step "Criando namespace 'redis'..."
kubectl create namespace redis --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "Namespace pronto."

# 3. Redis
step "Instalando Redis 'redis'..."
helm upgrade --install redis bitnami/redis \
    --namespace redis \
    --values "$SCRIPT_DIR/values.yaml" \
    || fail "Helm install falhou."
ok "Redis instalado."

# 4. IngressRouteTCP — expoe localhost:6379
step "Aplicando IngressRouteTCP (porta 6379)..."
kubectl apply -f - <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: redis
  namespace: redis
spec:
  entryPoints:
    - redis
  routes:
    - match: HostSNI(`*`)
      services:
        - name: redis-master
          port: 6379
EOF
ok "Redis acessivel em localhost:6379."

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Redis pronto!${NC}"
echo -e "${GREEN}============================================${NC}"
echo "  Namespace  : redis"
echo "  Senha      : Workshop123redis"
echo "  Host local : localhost:6379"
echo "  URI        : redis://:Workshop123redis@localhost:6379"
echo ""
echo -e "  ${YELLOW}Aguardar pronto:${NC}"
echo "    kubectl -n redis get pods -w"
echo ""
