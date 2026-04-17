#!/usr/bin/env bash
# Instala HashiCorp Vault (modo dev) no namespace 'vault'.
#
# Namespace  : vault   | Release: vault
# Root Token : root    (dev mode — nao usar em producao)
# UI         : http://vault.monitoramento.local
# Metricas   : ServiceMonitor em /v1/sys/metrics (bearerToken=root)
# Idempotente: re-executar e seguro.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==> $1${NC}"; }
ok()   { echo -e "    ${GREEN}OK: $1${NC}"; }
warn() { echo -e "    ${YELLOW}AVISO: $1${NC}"; }
fail() { echo -e "\n    ${RED}ERRO: $1${NC}"; exit 1; }

# 1. Helm repo
step "Adicionando repositorio HashiCorp..."
helm repo add hashicorp https://helm.releases.hashicorp.com --force-update 2>/dev/null || true
helm repo update hashicorp 2>/dev/null
ok "Repositorio pronto."

# 2. Namespace
step "Criando namespace 'vault'..."
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "Namespace pronto."

# 3. Vault
step "Instalando HashiCorp Vault 'vault'..."
helm upgrade --install vault hashicorp/vault \
    --namespace vault \
    --values "$SCRIPT_DIR/values.yaml" \
    --wait --timeout 120s \
    || fail "Helm install falhou."
ok "Vault instalado."

# 4. Ingress HTTP
step "Criando Ingress HTTP para vault.monitoramento.local..."
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: vault
  namespace: vault
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: vault.monitoramento.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: vault
                port:
                  number: 8200
EOF
ok "Vault UI em http://vault.monitoramento.local."

# 5. Secret de metricas + ServiceMonitor
step "Criando Secret e ServiceMonitor para metricas..."
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: vault-metrics-token
  namespace: vault
  labels:
    app.kubernetes.io/instance: vault
type: Opaque
stringData:
  token: "root"
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vault
  namespace: vault
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: vault
      app.kubernetes.io/instance: vault
  endpoints:
    - port: http
      interval: 30s
      path: /v1/sys/metrics
      params:
        format: [prometheus]
      bearerTokenSecret:
        name: vault-metrics-token
        key: token
EOF
ok "ServiceMonitor criado."

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Vault pronto!${NC}"
echo -e "${GREEN}============================================${NC}"
echo "  Namespace  : vault"
echo "  Root Token : root  (dev mode)"
echo "  UI         : http://vault.monitoramento.local"
echo "  API        : http://vault.monitoramento.local/v1"
echo ""
echo -e "  ${YELLOW}Adicionar ao hosts (se necessario):${NC}"
echo "    127.0.0.1  vault.monitoramento.local"
echo ""
echo -e "  ${YELLOW}Aguardar pronto:${NC}"
echo "    kubectl -n vault get pods -w"
echo ""
echo -e "  ${YELLOW}AVISO: Modo dev — dados NAO persistem entre restarts.${NC}"
echo ""
