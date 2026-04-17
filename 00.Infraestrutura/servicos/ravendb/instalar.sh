#!/usr/bin/env bash
# Instala RavenDB no namespace 'ravendb'.
#
# Namespace  : ravendb   | Release: ravendb
# Modo       : Nao-seguro (workshop/dev) — sem TLS, sem autenticacao
# UI         : http://ravendb.monitoramento.local
# Metricas   : ServiceMonitor em /metrics porta 8080
# Idempotente: re-executar e seguro.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==> $1${NC}"; }
ok()   { echo -e "    ${GREEN}OK: $1${NC}"; }
warn() { echo -e "    ${YELLOW}AVISO: $1${NC}"; }
fail() { echo -e "\n    ${RED}ERRO: $1${NC}"; exit 1; }

# 1. Helm repo
step "Adicionando repositorio RavenDB..."
helm repo add ravendb https://ravendb.github.io/helm-charts --force-update 2>/dev/null || true
helm repo update ravendb 2>/dev/null
ok "Repositorio pronto."

# 2. Namespace
step "Criando namespace 'ravendb'..."
kubectl create namespace ravendb --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "Namespace pronto."

# 3. RavenDB
step "Instalando RavenDB 'ravendb'..."
helm upgrade --install ravendb ravendb/ravendb-cluster \
    --namespace ravendb \
    --values "$SCRIPT_DIR/values.yaml" \
    --wait --timeout 180s \
    || fail "Helm install falhou."
ok "RavenDB instalado."

# 4. Ingress HTTP
step "Criando Ingress HTTP para ravendb.monitoramento.local..."
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ravendb
  namespace: ravendb
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: ravendb.monitoramento.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ravendb-ravendb-cluster
                port:
                  number: 8080
EOF
ok "RavenDB Studio em http://ravendb.monitoramento.local."

# 5. ServiceMonitor
step "Criando ServiceMonitor..."
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ravendb
  namespace: ravendb
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/instance: ravendb
  endpoints:
    - port: http
      interval: 30s
      path: /metrics
EOF
ok "ServiceMonitor criado."

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  RavenDB pronto!${NC}"
echo -e "${GREEN}============================================${NC}"
echo "  Namespace  : ravendb"
echo "  Modo       : Nao-seguro (dev/workshop)"
echo "  UI         : http://ravendb.monitoramento.local"
echo ""
echo -e "  ${YELLOW}Adicionar ao hosts (se necessario):${NC}"
echo "    127.0.0.1  ravendb.monitoramento.local"
echo ""
echo -e "  ${YELLOW}Aguardar pronto:${NC}"
echo "    kubectl -n ravendb get pods -w"
echo ""
echo -e "  ${YELLOW}NOTA: Para adicionar licenca, edite values.yaml (campo ravendb.license)${NC}"
echo -e "  ${YELLOW}      e re-execute este script.${NC}"
echo ""
