#!/bin/bash
# instalar.sh — Instala o ArgoCD no cluster monitoramento (k3d + Traefik).
#
# O servidor roda em modo --insecure para que o Traefik realize a terminacao
# HTTP no Ingress padrao. Um Ingress networking.k8s.io/v1 e criado ao final
# expondo a UI em http://argocd.monitoramento.local.
#
# Prereqs : cluster monitoramento em execucao (03.criar-cluster-k3d.sh)
# Proximo : adicionar entrada no /etc/hosts via 09.atualizar-hosts.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/values.yaml"

ARGOCD_NS="argocd"
ARGOCD_HOST="argocd.monitoramento.local"
ARGOCD_CHART_VERSION=""   # vazio = latest stable

# ── Helpers de output ─────────────────────────────────────────────────────────
cyan()   { [ -t 1 ] && printf '\033[0;36m%s\033[0m\n' "$*" || echo "$*"; }
green()  { [ -t 1 ] && printf '\033[0;32m%s\033[0m\n' "$*" || echo "$*"; }
yellow() { [ -t 1 ] && printf '\033[0;33m%s\033[0m\n' "$*" || echo "$*"; }
white()  { [ -t 1 ] && printf '\033[1;37m%s\033[0m\n' "$*" || echo "$*"; }
red()    { printf '\033[0;31mERRO: %s\033[0m\n' "$*" >&2; }

# ── 0. Pre-checks ─────────────────────────────────────────────────────────────
cyan ""
cyan "[0/5] Verificando pre-requisitos..."

for cmd in kubectl helm; do
    if ! command -v "$cmd" &>/dev/null; then
        red "'$cmd' nao encontrado no PATH. Instale antes de continuar."
        exit 1
    fi
done

if ! kubectl cluster-info &>/dev/null; then
    red "kubectl nao consegue conectar ao cluster. Execute 03.criar-cluster-k3d.sh primeiro."
    exit 1
fi

echo "    OK: kubectl, helm encontrados e cluster acessivel."

# ── 1. Namespace ──────────────────────────────────────────────────────────────
cyan ""
cyan "[1/5] Criando namespace ${ARGOCD_NS}..."
kubectl create namespace "${ARGOCD_NS}" --dry-run=client -o yaml | kubectl apply -f -

# ── 2. Helm repo ──────────────────────────────────────────────────────────────
cyan ""
cyan "[2/5] Adicionando repositorio Helm do ArgoCD..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# ── 3. Instalar ArgoCD ────────────────────────────────────────────────────────
cyan ""
cyan "[3/5] Instalando ArgoCD via Helm..."

version_flag=()
if [ -n "${ARGOCD_CHART_VERSION}" ]; then
    version_flag=("--version" "${ARGOCD_CHART_VERSION}")
fi

helm upgrade --install argocd argo/argo-cd \
    --namespace "${ARGOCD_NS}" \
    --values "${VALUES_FILE}" \
    "${version_flag[@]}" \
    --wait \
    --timeout 5m

echo "    OK: ArgoCD instalado."

# ── 4. Ingress (Traefik) ──────────────────────────────────────────────────────
cyan ""
cyan "[4/5] Criando Ingress para o ArgoCD UI..."

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: ${ARGOCD_NS}
  labels:
    app: argocd
    version: "1.0.0"
spec:
  ingressClassName: traefik
  rules:
    - host: ${ARGOCD_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
EOF

echo "    OK: Ingress criado."

# ── 5. Aguardar pods prontos ───────────────────────────────────────────────────
cyan ""
cyan "[5/5] Aguardando pods do ArgoCD ficarem prontos (timeout: 2m)..."
kubectl wait --for=condition=Ready pods \
    --all \
    -n "${ARGOCD_NS}" \
    --timeout=120s

# ── Senha inicial do admin ─────────────────────────────────────────────────────
INITIAL_PASSWORD="$(
    kubectl -n "${ARGOCD_NS}" get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' 2>/dev/null \
    | base64 -d 2>/dev/null \
    || echo '<nao disponivel>'
)"

# ── Resumo ────────────────────────────────────────────────────────────────────
echo ""
green "============================================================"
green " ArgoCD instalado com sucesso!"
green "============================================================"
echo ""
echo " Adicione a entrada abaixo no arquivo /etc/hosts"
echo " (ou execute 09.atualizar-hosts.sh):"
echo ""
white "   127.0.0.1   ${ARGOCD_HOST}"
echo ""
cyan " Acesso via browser:"
cyan "   ArgoCD UI  http://${ARGOCD_HOST}"
echo ""
echo " Credenciais iniciais:"
white "   Usuario : admin"
white "   Senha   : ${INITIAL_PASSWORD}"
echo ""
yellow "AVISO: Altere a senha inicial apos o primeiro acesso:"
yellow "   argocd login ${ARGOCD_HOST} --username admin --password '${INITIAL_PASSWORD}' --insecure"
yellow "   argocd account update-password"
echo ""
