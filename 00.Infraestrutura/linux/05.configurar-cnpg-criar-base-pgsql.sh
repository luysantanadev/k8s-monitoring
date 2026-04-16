#!/usr/bin/env bash
# ==============================================================================
# SYNOPSIS
#   Gerencia bases de dados PostgreSQL via CloudNativePG no cluster k3d.
#
# DESCRIPTION
#   - Instala o CNPG operator via Helm se ainda não estiver presente (idempotente).
#   - Modo interativo: cria ou remove clusters PostgreSQL.
#     Criação: solicita namespace e nome da base, gera usuário e senha aleatórios,
#              instala via Helm, cria IngressRouteTCP e ServiceMonitor.
#     Remoção: lista bases existentes por número e remove a selecionada.
#
# NOTES
#   Pré-requisito: cluster k3d 'monitoramento' em execução (03.setup-k3d-multi-node.sh)
#   monitoramento instalado (04.configurar-monitoramento.sh) — necessário para ServiceMonitor.
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

# Returns "namespace<TAB>release" for all CNPG clusters
get_all_clusters() {
    kubectl get cluster -A \
        --no-headers \
        -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name" \
        2>/dev/null | \
    awk '{ name=$2; sub(/-cluster$/, "", name); print $1"\t"name }' || true
}

# ---------------------------------------------------------------------------
# 1. Instalar / verificar CloudNativePG operator (idempotente)
# ---------------------------------------------------------------------------
write_step "Verificando CloudNativePG operator..."

helm repo add cnpg https://cloudnative-pg.github.io/charts 2>/dev/null || true
helm repo update >/dev/null

helm upgrade --install cnpg cnpg/cloudnative-pg \
    --namespace cnpg-system \
    --create-namespace \
    --wait \
    --timeout 120s

if [[ $? -ne 0 ]]; then
    write_fail "Falha ao instalar o CloudNativePG operator."
fi

cnpg_ready=$(kubectl -n cnpg-system get deployment cnpg-cloudnative-pg \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

if [[ "${cnpg_ready:-0}" -lt 1 ]]; then
    write_fail "CNPG operator não está pronto. Verifique: kubectl -n cnpg-system get pods"
fi

write_success "CNPG operator pronto (${cnpg_ready} réplica(s))."

# ---------------------------------------------------------------------------
# 2. Menu principal
# ---------------------------------------------------------------------------
echo ""
echo -e "  ${CYAN}O que deseja fazer?${RESET}"
echo "    [1] Criar base de dados"
echo "    [2] Remover base de dados"
echo ""

action=""
while true; do
    read -rp "  Opcao: " action
    action="${action// /}"
    [[ "$action" == "1" || "$action" == "2" ]] && break
    write_warn "Opcao invalida. Digite 1 ou 2."
done

# ===========================================================================
# CRIAR BASE
# ===========================================================================
if [[ "$action" == "1" ]]; then

    # --- Namespace ---
    echo ""
    namespace=""
    while true; do
        read -rp "  Namespace: " namespace
        namespace="${namespace// /}"
        [[ -n "$namespace" ]] && break
    done

    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    write_success "Namespace '$namespace' pronto."

    # --- Nome da base (único no namespace) ---
    all_clusters="$(get_all_clusters)"
    database=""
    while true; do
        read -rp "  Nome da base de dados: " db_name
        db_name="${db_name// /}"
        db_name="${db_name,,}"   # lowercase
        [[ -z "$db_name" ]] && continue
        if echo "$all_clusters" | grep -qP "^${namespace}\t${db_name}$"; then
            write_warn "Já existe uma base '$db_name' no namespace '$namespace'. Escolha outro nome."
            continue
        fi
        database="$db_name"
        break
    done

    # --- Derivar valores ---
    username="$database"
    password="$(new_random_password)"
    secret_name="${database}-credentials"
    rw_svc="${database}-cluster-rw"

    # --- Secret de credenciais ---
    write_step "Criando Secret de credenciais '${secret_name}'..."
    kubectl -n "$namespace" create secret generic "$secret_name" \
        --from-literal=username="$username" \
        --from-literal=password="$password" \
        --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    write_success "Secret criado."

    # --- Helm install ---
    write_step "Instalando cluster PostgreSQL '$database' no namespace '$namespace'..."
    helm upgrade --install "$database" cnpg/cluster \
        --namespace "$namespace" \
        --set cluster.instances=1 \
        --set cluster.storage.size=1Gi \
        --set cluster.initdb.database="$database" \
        --set cluster.initdb.owner="$username" \
        --set cluster.initdb.secret.name="$secret_name" \
        --set-string cluster.postgresql.parameters.max_connections=200 \
        --wait \
        --timeout 180s
    write_success "Cluster PostgreSQL pronto."

    # --- IngressRouteTCP ---
    write_step "Aplicando IngressRouteTCP para PostgreSQL (porta 5432)..."
    kubectl apply -f - << MANIFEST
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: postgres-${database}
  namespace: ${namespace}
  labels:
    app: ${database}
    managed-by: 05.configurar-cnpg-criar-base-pgsql
spec:
  entryPoints:
    - postgres
  routes:
    - match: HostSNI(\`*\`)
      services:
        - name: ${rw_svc}
          port: 5432
MANIFEST

    if [[ $? -ne 0 ]]; then
        write_warn "IngressRouteTCP não aplicado. Porta 5432 pode já estar em uso por outra instância."
    else
        write_success "IngressRouteTCP aplicado. PostgreSQL acessível em localhost:5432."
    fi

    # --- ServiceMonitor ---
    write_step "Criando ServiceMonitor para PostgreSQL '${database}'..."
    kubectl apply -f - << MANIFEST
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: postgres-${database}
  namespace: ${namespace}
  labels:
    app: ${database}
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      cnpg.io/cluster: ${database}-cluster
  endpoints:
    - port: metrics
      interval: 30s
      path: /metrics
MANIFEST

    if [[ $? -ne 0 ]]; then
        write_warn "ServiceMonitor não aplicado. Métricas não serão coletadas."
    else
        write_success "ServiceMonitor criado. Métricas disponíveis no Grafana."
    fi

    # --- Resumo ---
    echo ""
    echo -e "${GREEN}============================================${RESET}"
    echo -e "${GREEN}  Base de dados criada com sucesso!${RESET}"
    echo -e "${GREEN}============================================${RESET}"
    echo ""
    echo "  Namespace : ${namespace}"
    echo "  Base      : ${database}"
    echo "  Usuário   : ${username}"
    echo "  Senha     : ${password}"
    echo ""
    echo -e "  ${YELLOW}Connection string interna:${RESET}"
    echo "    postgresql://${username}:${password}@${rw_svc}.${namespace}.svc.cluster.local:5432/${database}"
    echo ""
    echo -e "  ${YELLOW}DATABASE_URL local (via Traefik):${RESET}"
    echo "    postgresql://${username}:${password}@localhost:5432/${database}"
    echo ""
    write_warn "Nota: apenas uma instância PostgreSQL pode ser exposta na porta 5432 por vez."
    echo ""
fi

# ===========================================================================
# REMOVER BASE
# ===========================================================================
if [[ "$action" == "2" ]]; then

    mapfile -t clusters < <(get_all_clusters)

    if [[ ${#clusters[@]} -eq 0 ]]; then
        echo ""
        write_warn "Nenhuma base de dados encontrada no cluster."
        exit 0
    fi

    echo ""
    echo -e "  ${CYAN}Bases de dados existentes:${RESET}"
    for i in "${!clusters[@]}"; do
        ns=$(echo "${clusters[$i]}"  | cut -f1)
        rel=$(echo "${clusters[$i]}" | cut -f2)
        echo "    [$((i+1))]  ${ns} / ${rel}"
    done
    echo ""

    max="${#clusters[@]}"
    sel=""
    while true; do
        read -rp "  Número da base a remover (1-${max}): " sel
        sel="${sel// /}"
        [[ "$sel" =~ ^[0-9]+$ ]] && [[ "$sel" -ge 1 ]] && [[ "$sel" -le "$max" ]] && break
    done

    idx=$((sel - 1))
    ns=$(echo "${clusters[$idx]}"  | cut -f1)
    release=$(echo "${clusters[$idx]}" | cut -f2)

    write_step "Removendo base '${release}' do namespace '${ns}'..."
    helm uninstall "$release" --namespace "$ns"
    kubectl -n "$ns" delete secret "${release}-credentials" --ignore-not-found >/dev/null
    kubectl -n "$ns" delete ingressroutetcp "postgres-${release}" --ignore-not-found >/dev/null
    kubectl -n "$ns" delete servicemonitor "postgres-${release}" --ignore-not-found >/dev/null

    write_success "Base '${release}' removida do namespace '${ns}'."
    echo ""
fi
