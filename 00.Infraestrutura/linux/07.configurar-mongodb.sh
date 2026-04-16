#!/usr/bin/env bash
# ==============================================================================
# SYNOPSIS
#   Gerencia instâncias MongoDB via Community Operator no cluster k3d.
#
# DESCRIPTION
#   - Instala o MongoDB Community Operator via Helm se ainda não estiver presente (idempotente).
#   - Modo interativo: cria ou remove instâncias MongoDB (ReplicaSet com 1 membro).
#     Criação: solicita namespace e nome, gera usuário e senha aleatórios,
#              aplica os manifestos via kubectl, cria IngressRouteTCP e ServiceMonitor.
#     Remoção: lista instâncias existentes por número e remove a selecionada.
#
# NOTES
#   Pré-requisito: cluster k3d 'monitoramento' em execução (03.setup-k3d-multi-node.sh)
#   kubectl e helm no PATH.
#   Chart utilizado: mongodb/community-operator (MongoDB Inc., open-source Apache 2.0).
#   CRD criado: MongoDBCommunity  |  Porta: 27017  |  Service: <nome>-svc
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

# Returns "namespace<TAB>name" for all MongoDBCommunity instances
get_all_mongo_instances() {
    kubectl get mongodbcommunity -A \
        --no-headers \
        -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name" \
        2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 1. Instalar / verificar MongoDB Community Operator (idempotente)
# ---------------------------------------------------------------------------
write_step "Verificando MongoDB Community Operator..."

helm repo add mongodb https://mongodb.github.io/helm-charts 2>/dev/null || true
helm repo update >/dev/null

helm upgrade --install community-operator mongodb/community-operator \
    --namespace mongodb-operator \
    --create-namespace \
    --set operator.watchNamespace="*" \
    --wait \
    --timeout 120s

if [[ $? -ne 0 ]]; then
    write_fail "Falha ao instalar o MongoDB Community Operator."
fi

op_ready=$(kubectl -n mongodb-operator get deployment mongodb-kubernetes-operator \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

if [[ "${op_ready:-0}" -lt 1 ]]; then
    write_fail "MongoDB Community Operator não está pronto. Verifique: kubectl -n mongodb-operator get pods"
fi

write_success "MongoDB Community Operator pronto (${op_ready} réplica(s))."

# ---------------------------------------------------------------------------
# 2. Menu principal
# ---------------------------------------------------------------------------
echo ""
echo -e "  ${CYAN}O que deseja fazer?${RESET}"
echo "    [1] Criar instância MongoDB"
echo "    [2] Remover instância MongoDB"
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

    all_instances="$(get_all_mongo_instances)"
    instance_name=""
    while true; do
        read -rp "  Nome da instância MongoDB: " input_name
        input_name="${input_name// /}"
        input_name="${input_name,,}"
        [[ -z "$input_name" ]] && continue
        if printf '%s\n' "$all_instances" | grep -qP "^${namespace}\s+${input_name}$"; then
            write_warn "Já existe uma instância '$input_name' no namespace '$namespace'. Escolha outro nome."
            continue
        fi
        instance_name="$input_name"
        break
    done

    username="$instance_name"
    password="$(new_random_password)"
    metrics_password="$(new_random_password)"
    svc="${instance_name}-svc"

    # --- Manifestos: Secrets + MongoDBCommunity ---
    write_step "Aplicando Secret e MongoDBCommunity '$instance_name' no namespace '$namespace'..."

    kubectl apply -f - << MANIFEST
apiVersion: v1
kind: Secret
metadata:
  name: ${instance_name}-password
  namespace: ${namespace}
type: Opaque
stringData:
  password: "${password}"
---
apiVersion: v1
kind: Secret
metadata:
  name: ${instance_name}-metrics-password
  namespace: ${namespace}
type: Opaque
stringData:
  password: "${metrics_password}"
---
apiVersion: mongodbcommunity.mongodb.com/v1
kind: MongoDBCommunity
metadata:
  name: ${instance_name}
  namespace: ${namespace}
spec:
  members: 1
  type: ReplicaSet
  version: "7.0.14"
  security:
    authentication:
      modes: ["SCRAM"]
  users:
    - name: ${username}
      db: admin
      passwordSecretRef:
        name: ${instance_name}-password
      roles:
        - name: readWriteAnyDatabase
          db: admin
        - name: dbAdminAnyDatabase
          db: admin
      scramCredentialsSecretName: ${instance_name}-scram
  prometheus:
    passwordSecretRef:
      name: ${instance_name}-metrics-password
  statefulSet:
    spec:
      template:
        spec:
          containers:
            - name: mongod
              resources:
                requests:
                  cpu: 100m
                  memory: 256Mi
                limits:
                  cpu: 500m
                  memory: 512Mi
MANIFEST

    if [[ $? -ne 0 ]]; then
        write_fail "kubectl apply falhou. Verifique os logs acima."
    fi
    write_success "Manifesto aplicado. O operator vai provisionar o pod em background."

    # --- IngressRouteTCP ---
    write_step "Aplicando IngressRouteTCP para MongoDB (porta 27017)..."
    kubectl apply -f - << MANIFEST
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: mongodb-${instance_name}
  namespace: ${namespace}
  labels:
    app: ${instance_name}
    managed-by: 07.mongodb
spec:
  entryPoints:
    - mongodb
  routes:
    - match: HostSNI(\`*\`)
      services:
        - name: ${svc}
          port: 27017
MANIFEST
    if [[ $? -ne 0 ]]; then
        write_warn "IngressRouteTCP não aplicado. Porta 27017 pode já estar em uso por outra instância."
    else
        write_success "IngressRouteTCP aplicado. MongoDB acessível em localhost:27017."
    fi

    # --- ServiceMonitor ---
    # O Community Operator com spec.prometheus habilita o mongodb_exporter na porta 9216.
    # O port name no Service é 'prometheus' (convenção do operator).
    write_step "Criando ServiceMonitor para MongoDB '$instance_name'..."
    kubectl apply -f - << MANIFEST
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mongodb-${instance_name}
  namespace: ${namespace}
  labels:
    app: ${instance_name}
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: ${instance_name}
  endpoints:
    - port: prometheus
      interval: 30s
      path: /metrics
MANIFEST
    if [[ $? -ne 0 ]]; then
        write_warn "ServiceMonitor não aplicado. Métricas do MongoDB não serão coletadas."
    else
        write_success "ServiceMonitor criado. Métricas disponíveis no Grafana."
    fi

    echo ""
    echo -e "${GREEN}============================================${RESET}"
    echo -e "${GREEN}  Instância MongoDB criada com sucesso!${RESET}"
    echo -e "${GREEN}============================================${RESET}"
    echo ""
    echo "  Namespace : ${namespace}"
    echo "  Instância : ${instance_name}"
    echo "  Usuário   : ${username}"
    echo "  Senha     : ${password}"
    echo ""
    echo -e "  ${YELLOW}Aguardar o pod ficar pronto:${RESET}"
    echo "    kubectl -n ${namespace} get mongodbcommunity ${instance_name} -w"
    echo ""
    echo -e "  ${YELLOW}Connection string interna:${RESET}"
    echo "    mongodb://${username}:${password}@${svc}.${namespace}.svc.cluster.local:27017/admin?authSource=admin"
    echo ""
    echo -e "  ${YELLOW}MONGODB_URL local (via Traefik):${RESET}"
    echo "    mongodb://${username}:${password}@localhost:27017/admin?authSource=admin&directConnection=true"
    echo ""
    write_warn "Nota: apenas uma instância MongoDB pode ser exposta na porta 27017 por vez."
    echo ""
fi

# ===========================================================================
# REMOVER INSTÂNCIA
# ===========================================================================
if [[ "$action" == "2" ]]; then

    mapfile -t instances < <(get_all_mongo_instances)

    if [[ ${#instances[@]} -eq 0 ]]; then
        echo ""
        write_warn "Nenhuma instância MongoDB encontrada no cluster."
        exit 0
    fi

    echo ""
    echo -e "  ${CYAN}Instâncias MongoDB existentes:${RESET}"
    for i in "${!instances[@]}"; do
        echo "    [$((i+1))]  ${instances[$i]}"
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
    ns=$(echo "${instances[$idx]}"   | awk '{print $1}')
    name=$(echo "${instances[$idx]}" | awk '{print $2}')

    write_step "Removendo instância MongoDB '$name' do namespace '$ns'..."

    kubectl -n "$ns" delete mongodbcommunity "$name" --ignore-not-found
    kubectl -n "$ns" delete secret \
        "${name}-password" "${name}-scram" "${name}-metrics-password" \
        --ignore-not-found >/dev/null
    kubectl -n "$ns" delete ingressroutetcp "mongodb-${name}" --ignore-not-found >/dev/null
    kubectl -n "$ns" delete servicemonitor  "mongodb-${name}" --ignore-not-found >/dev/null

    write_warn "PVC do MongoDB pode ter ficado para trás. Para remover:"
    write_warn "  kubectl -n ${ns} delete pvc -l app=${name}"
    write_success "Instância MongoDB '$name' removida do namespace '$ns'."
    echo ""
fi
