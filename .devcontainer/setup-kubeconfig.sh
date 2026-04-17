#!/usr/bin/env bash
# Configura o kubectl dentro do dev container para acessar o cluster k3d 'monitoramento'.
#
# Como funciona:
#   1. Conecta este container à rede Docker interna do k3d (k3d-monitoramento)
#   2. Obtém o kubeconfig via k3d
#   3. Substitui a URL do API server pelo IP interno do load-balancer k3d,
#      acessível dentro da rede Docker compartilhada
#
# Idempotente: pode ser re-executado a qualquer momento.
# Use após criar/recriar o cluster:
#   bash .devcontainer/setup-kubeconfig.sh

set -euo pipefail

CLUSTER_NAME="monitoramento"
NETWORK="k3d-${CLUSTER_NAME}"
SERVERLB_CONTAINER="k3d-${CLUSTER_NAME}-serverlb"

echo ""
echo "==> Verificando cluster k3d '${CLUSTER_NAME}'..."
if ! k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    echo ""
    echo "⚠️  Cluster '${CLUSTER_NAME}' não encontrado."
    echo "   Crie o cluster primeiro com:"
    echo "     Windows : .\\00.Infraestrutura\\windows\\03.criar-cluster-k3d.ps1"
    echo "     Linux   : bash 00.Infraestrutura/linux/03.criar-cluster-k3d.sh"
    echo ""
    echo "   Depois re-execute este script:"
    echo "     bash .devcontainer/setup-kubeconfig.sh"
    echo ""
    exit 0
fi

echo "==> Conectando dev container à rede Docker '${NETWORK}'..."
# O hostname do container no Docker é o seu short ID (12 chars)
SELF=$(hostname)
if docker network connect "${NETWORK}" "${SELF}" 2>/dev/null; then
    echo "    Conectado a ${NETWORK}."
else
    echo "    Já conectado ou ignorado — continuando."
fi

echo "==> Obtendo kubeconfig para o cluster '${CLUSTER_NAME}'..."
mkdir -p "${HOME}/.kube"
k3d kubeconfig get "${CLUSTER_NAME}" > "${HOME}/.kube/config"
chmod 600 "${HOME}/.kube/config"

echo "==> Resolvendo IP interno do API server (${SERVERLB_CONTAINER})..."
SERVERLB_IP=$(docker inspect "${SERVERLB_CONTAINER}" \
    --format "{{(index .NetworkSettings.Networks \"${NETWORK}\").IPAddress}}" 2>/dev/null || echo "")

if [ -n "${SERVERLB_IP}" ]; then
    kubectl config set-cluster "k3d-${CLUSTER_NAME}" \
        --server="https://${SERVERLB_IP}:6443"
    echo "    API server: https://${SERVERLB_IP}:6443"
else
    # Fallback: skip TLS (útil para labs quando o IP não é resolvível)
    echo "    ⚠️  IP do serverlb não encontrado. Ativando insecure-skip-tls-verify."
    kubectl config set-cluster "k3d-${CLUSTER_NAME}" \
        --insecure-skip-tls-verify=true
fi

echo "==> Testando conexão com o cluster..."
if kubectl cluster-info 2>/dev/null; then
    echo ""
    echo "✅  kubectl configurado com sucesso!"
    echo "    Execute: kubectl get nodes"
else
    echo ""
    echo "⚠️  Conexão não estabelecida. Diagnóstico:"
    echo "    kubectl config view --minify"
    echo "    kubectl cluster-info"
fi
echo ""
