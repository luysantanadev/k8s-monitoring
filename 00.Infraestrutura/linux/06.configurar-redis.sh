#!/usr/bin/env bash
# ==============================================================================
# SYNOPSIS
#   Gerencia instâncias Redis via Helm (bitnami/redis) no cluster k3d.
#
# DESCRIPTION
#   - Adiciona o repositório bitnami e atualiza os repos (idempotente).
#   - Modo interativo: cria ou remove instâncias Redis standalone.
#     Criação: solicita namespace e nome, gera senha aleatória, instala via Helm,
#              cria IngressRouteTCP e ServiceMonitor.
#     Remoção: lista instâncias existentes por número e remove a selecionada.
#
# NOTES
#   Pré-requisito: cluster k3d 'monitoramento' em execução (03.setup-k3d-multi-node.sh)
#   kubectl e helm no PATH.
#   Chart utilizado: bitnami/redis (standalone, sem réplicas — adequado para workshop).
# ==============================================================================

set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

write_step()    { echo -e "\n${CYAN}==> $1${RESET}"; }
write_success() { echo -e "    ${GREEN}OK: $1${RESET}"; }
write_warn()    { echo -e "    ${YELLOW}AVISO: $1${RESET}"; }
write_fail()    { echo -e "\n    ${RED}ERRO: $1${RESET}"; exit 1; }

new_random_password() {
    openssl rand -base64 32 | tr -d '+/=' | head -c 24
}

# Returns "namespace<TAB>release" for all Redis helm releases (chart starts with redis-)
get_all_redis_instances() {
    helm list -A -o json 2>/dev/null | \
    python3 -c "
import sys, json
for item in json.load(sys.stdin):
    if item.get('chart','').startswith('redis-'):
        print(item['namespace'] + '\t' + item['name'])" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 1. Repositório Helm (idempotente)
# ---------------------------------------------------------------------------
write_step "Configurando repositório bitnami..."
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update >/dev/null
write_success "Repositório bitnami atualizado."

# ---------------------------------------------------------------------------
# 2. Menu principal
# ---------------------------------------------------------------------------
echo ""
echo -e "  ${CYAN}O que deseja fazer?${RESET}"
echo "    [1] Criar instância Redis"
echo "    [2] Remover instância Redis"
echo ""

action=""
while true; do
    read -rp "  Opcao: " action
    action="${action// /}"
    [[ "$action" == "1" || "$action" == "2" ]] && break
    write_warn "Opcao invalida. Digite 1 ou 2."
done

# ===========================================================================
# CRIAR INSTÂNCIA
# ===========================================================================
if [[ "$action" == "1" ]]; then

    echo ""
    namespace=""
    while true; do
        read -rp "  Namespace: " namespace
        namespace="${namespace// /}"
        [[ -n "$namespace" ]] && break
    done

    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    write_success "Namespace '$namespace' pronto."

    all_instances="$(get_all_redis_instances)"
    instance_name=""
    while true; do
        read -rp "  Nome da instância Redis: " input_name
        input_name="${input_name// /}"
        input_name="${input_name,,}"
        [[ -z "$input_name" ]] && continue
        if printf '%s\n' "$all_instances" | grep -qP "^${namespace}\t${input_name}$"; then
            write_warn "Já existe uma instância '$input_name' no namespace '$namespace'. Escolha outro nome."
            continue
        fi
        instance_name="$input_name"
        break
    done

    password="$(new_random_password)"
    master_svc="${instance_name}-redis-master"

    # --- Helm install ---
    write_step "Instalando Redis '$instance_name' no namespace '$namespace'..."
    helm upgrade --install "$instance_name" bitnami/redis \
        --namespace "$namespace" \
        --set auth.password="$password" \
        --set replica.replicaCount=0 \
        --set master.resources.requests.cpu=100m \
        --set master.resources.requests.memory=128Mi \
        --set master.resources.limits.cpu=500m \
        --set master.resources.limits.memory=256Mi \
        --set master.persistence.size=512Mi \
        --set metrics.enabled=true
    write_success "Instância Redis '$instance_name' criada."

    # --- IngressRouteTCP ---
    write_step "Aplicando IngressRouteTCP para Redis (porta 6379)..."
    kubectl apply -f - << MANIFEST
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: redis-${instance_name}
  namespace: ${namespace}
  labels:
    app: ${instance_name}
    managed-by: 06.redis
spec:
  entryPoints:
    - redis
  routes:
    - match: HostSNI(\`*\`)
      services:
        - name: ${master_svc}
          port: 6379
MANIFEST
    if [[ $? -ne 0 ]]; then
        write_warn "IngressRouteTCP não aplicado. Porta 6379 pode já estar em uso por outra instância."
    else
        write_success "IngressRouteTCP aplicado. Redis acessível em localhost:6379."
    fi

    # --- ServiceMonitor ---
    # O bitnami/redis com metrics.enabled=true implanta o redis_exporter como sidecar.
    # O serviço de métricas é $instance_name-redis-metrics na porta 9121 (nome 'metrics').
    write_step "Criando ServiceMonitor para Redis '$instance_name'..."
    kubectl apply -f - << MANIFEST
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: redis-${instance_name}
  namespace: ${namespace}
  labels:
    app: ${instance_name}
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: redis
      app.kubernetes.io/instance: ${instance_name}
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
MANIFEST
    if [[ $? -ne 0 ]]; then
        write_warn "ServiceMonitor não aplicado. Métricas do Redis não serão coletadas."
    else
        write_success "ServiceMonitor criado. Métricas disponíveis no Grafana."
    fi

    echo ""
    echo -e "${GREEN}============================================${RESET}"
    echo -e "${GREEN}  Instância Redis criada com sucesso!${RESET}"
    echo -e "${GREEN}============================================${RESET}"
    echo ""
    echo "  Namespace : ${namespace}"
    echo "  Instância : ${instance_name}"
    echo "  Senha     : ${password}"
    echo ""
    echo -e "  ${YELLOW}Connection string interna:${RESET}"
    echo "    redis://:${password}@${master_svc}.${namespace}.svc.cluster.local:6379"
    echo ""
    echo -e "  ${YELLOW}REDIS_URL local (via Traefik):${RESET}"
    echo "    redis://:${password}@localhost:6379"
    echo ""
    write_warn "Nota: apenas uma instância Redis pode ser exposta na porta 6379 por vez."
    echo ""
fi

# ===========================================================================
# REMOVER INSTÂNCIA
# ===========================================================================
if [[ "$action" == "2" ]]; then

    mapfile -t instances < <(get_all_redis_instances)

    if [[ ${#instances[@]} -eq 0 ]]; then
        echo ""
        write_warn "Nenhuma instância Redis encontrada no cluster."
        exit 0
    fi

    echo ""
    echo -e "  ${CYAN}Instâncias Redis existentes:${RESET}"
    for i in "${!instances[@]}"; do
        ns=$(echo "${instances[$i]}"  | cut -f1)
        rel=$(echo "${instances[$i]}" | cut -f2)
        echo "    [$((i+1))]  ${ns} / ${rel}"
    done
    echo ""

    max="${#instances[@]}"
    sel=""
    while true; do
        read -rp "  Número da instância a remover (1-${max}): " sel
        sel="${sel// /}"
        [[ "$sel" =~ ^[0-9]+$ ]] && [[ "$sel" -ge 1 ]] && [[ "$sel" -le "$max" ]] && break
    done

    idx=$((sel - 1))
    ns=$(echo "${instances[$idx]}"  | cut -f1)
    release=$(echo "${instances[$idx]}" | cut -f2)

    write_step "Removendo instância Redis '$release' do namespace '$ns'..."
    helm uninstall "$release" --namespace "$ns"
    kubectl -n "$ns" delete ingressroutetcp "redis-${release}" --ignore-not-found >/dev/null
    kubectl -n "$ns" delete servicemonitor  "redis-${release}" --ignore-not-found >/dev/null

    write_warn "PVC do Redis pode ter ficado para trás. Para remover:"
    write_warn "  kubectl -n ${ns} delete pvc -l app.kubernetes.io/instance=${release}"
    write_success "Instância Redis '$release' removida do namespace '$ns'."
    echo ""
fi
