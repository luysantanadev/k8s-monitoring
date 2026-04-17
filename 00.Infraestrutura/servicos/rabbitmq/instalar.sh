#!/usr/bin/env bash
# Instala RabbitMQ (Bitnami OCI) no namespace 'rabbitmq'.
#
# Namespace  : rabbitmq  | Release: rabbitmq
# Usuario    : user      | Senha: Workshop123rabbit
# AMQP TCP   : localhost:5672  (entrypoint 'amqp' no Traefik)
# UI         : http://rabbitmq.k3d.localhost
# Metricas   : ServiceMonitor porta 9419 (via values.yaml)
# Idempotente: re-executar e seguro.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==> $1${NC}"; }
ok()   { echo -e "    ${GREEN}OK: $1${NC}"; }
warn() { echo -e "    ${YELLOW}AVISO: $1${NC}"; }
fail() { echo -e "\n    ${RED}ERRO: $1${NC}"; exit 1; }

# 1. Namespace
step "Criando namespace 'rabbitmq'..."
kubectl create namespace rabbitmq --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "Namespace pronto."

# 2. RabbitMQ (OCI chart — sem helm repo add)
step "Instalando RabbitMQ 'rabbitmq'..."
helm upgrade --install rabbitmq oci://registry-1.docker.io/bitnamicharts/rabbitmq \
    --namespace rabbitmq \
    --values "$SCRIPT_DIR/values.yaml" \
    --wait --timeout 180s \
    || fail "Helm install falhou."
ok "RabbitMQ instalado."

# 3. IngressRouteTCP — expoe localhost:5672 (AMQP)
step "Aplicando IngressRouteTCP AMQP (porta 5672)..."
kubectl apply -f - <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: rabbitmq-amqp
  namespace: rabbitmq
spec:
  entryPoints:
    - amqp
  routes:
    - match: HostSNI(`*`)
      services:
        - name: rabbitmq
          port: 5672
EOF
ok "RabbitMQ AMQP acessivel em localhost:5672."

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  RabbitMQ pronto!${NC}"
echo -e "${GREEN}============================================${NC}"
echo "  Namespace  : rabbitmq"
echo "  Usuario    : user"
echo "  Senha      : Workshop123rabbit"
echo "  AMQP       : amqp://user:Workshop123rabbit@localhost:5672"
echo "  UI         : http://rabbitmq.k3d.localhost"
echo ""
echo -e "  ${YELLOW}Adicionar ao hosts (se necessario):${NC}"
echo "    127.0.0.1  rabbitmq.k3d.localhost"
echo ""
echo -e "  ${YELLOW}Aguardar pronto:${NC}"
echo "    kubectl -n rabbitmq get pods -w"
echo ""
