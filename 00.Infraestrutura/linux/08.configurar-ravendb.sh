#!/usr/bin/env bash
# ==============================================================================
# SYNOPSIS
#   Gerencia instâncias RavenDB via Helm no cluster k3d.
#
# DESCRIPTION
#   - Adiciona o repositório ravendb (github.com/ravendb/helm-charts) e atualiza (idempotente).
#   - Modo interativo: cria ou remove instâncias RavenDB standalone.
#     Criação: solicita namespace e nome da instância, solicita JSON de licença,
#              faz deploy via Helm em modo não-seguro (workshop), cria Ingress Traefik
#              HTTP e ServiceMonitor.
#     Remoção: lista instâncias existentes por número e remove a selecionada.
#
# NOTES
#   Pré-requisito: cluster k3d 'monitoramento' em execução (03.setup-k3d-multi-node.sh)
#   kubectl e helm no PATH.
#   Chart utilizado: ravendb/ravendb-cluster.
#   Porta HTTP : 8080  (Management Studio + REST API)
#   Modo       : não-seguro (UnsecuredAccessAllowed=PublicNetwork) — apenas para workshop/dev.
#   Ingress    : <nome>-ravendb.k3d.localhost via Traefik (porta 80).
#   Adicionar ao /etc/hosts: 127.0.0.1  <nome>-ravendb.k3d.localhost
# ==============================================================================

set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

write_step()    { echo -e "\n${CYAN}==> $1${RESET}"; }
write_success() { echo -e "    ${GREEN}OK: $1${RESET}"; }
write_warn()    { echo -e "    ${YELLOW}AVISO: $1${RESET}"; }
write_fail()    { echo -e "\n    ${RED}ERRO: $1${RESET}"; exit 1; }

# Returns "namespace<TAB>release" for all RavenDB helm releases
get_all_raven_instances() {
    helm list -A -o json 2>/dev/null | \
    python3 -c "
import sys, json
for item in json.load(sys.stdin):
    if item.get('chart','').startswith('ravendb-cluster-'):
        print(item['namespace'] + '\t' + item['name'])" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 1. Repositório Helm (idempotente)
# ---------------------------------------------------------------------------
write_step "Configurando repositório ravendb/helm-charts..."
helm repo add ravendb https://ravendb.github.io/helm-charts 2>/dev/null || true
helm repo update >/dev/null
write_success "Repositório ravendb atualizado."

# ---------------------------------------------------------------------------
# 2. Menu principal
# ---------------------------------------------------------------------------
echo ""
echo -e "  ${CYAN}O que deseja fazer?${RESET}"
echo "    [1] Criar instância RavenDB"
echo "    [2] Remover instância RavenDB"
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

    all_instances="$(get_all_raven_instances)"
    instance_name=""
    while true; do
        read -rp "  Nome da instância RavenDB: " input_name
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

    # --- Licença RavenDB ---
    # O chart faz b64enc do campo license; se o valor for nil o Helm falha.
    # O usuário deve colar o JSON da licença (obtido em ravendb.net/buy).
    echo ""
    echo -e "  ${CYAN}Cole o JSON da licença RavenDB e pressione ENTER duas vezes.${RESET}"
    echo -e "  (Licença gratuita Developer: https://ravendb.net/buy)"
    echo ""

    license_lines=()
    while IFS= read -rp "  Licença: " line; do
        [[ -z "$line" ]] && break
        license_lines+=("$line")
    done
    license="${license_lines[*]:-}"

    if [[ -z "$license" ]]; then
        write_warn "Nenhuma licença informada. O deploy pode falhar ou o Studio ficará em modo limitado."
        license=""
    fi

    # --- Arquivo de valores Helm temporário ---
    # O JSON da licença contém aspas e chaves que quebram strings YAML inline.
    # Solução: bloco literal YAML (indicador '|') + arquivo temporário.
    # O bloco literal preserva o conteúdo exatamente como digitado, sem necessidade de escape.
    tmp_values="$(mktemp --suffix=.yaml)"
    trap 'rm -f "$tmp_values"' EXIT

    cat > "$tmp_values" << YAML
nodesCount: 1

ravendb:
  license: |
    ${license}
  settings:
    "Security.UnsecuredAccessAllowed": "PublicNetwork"
    "Setup.Mode": "None"

resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: "1"
    memory: 1Gi

storage:
  size: 2Gi
YAML

    # --- Deploy via Helm ---
    write_step "Fazendo deploy do RavenDB '$instance_name' no namespace '$namespace'..."
    helm upgrade --install "$instance_name" ravendb/ravendb-cluster \
        --namespace "$namespace" \
        --create-namespace \
        --values "$tmp_values"

    if [[ $? -ne 0 ]]; then
        write_fail "Helm install falhou. Verifique os logs acima."
    fi
    write_success "RavenDB '$instance_name' implantado."

    ingress_host="${instance_name}-ravendb.k3d.localhost"

    # --- Ingress HTTP (Traefik) ---
    # RavenDB é HTTP-nativo (porta 8080), então usa Ingress padrão em vez de IngressRouteTCP.
    # Isso permite múltiplas instâncias coexistindo no mesmo host :80 via host-header routing.
    write_step "Criando Ingress Traefik para '$ingress_host'..."
    kubectl apply -f - << MANIFEST
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ravendb-${instance_name}
  namespace: ${namespace}
  labels:
    app: ${instance_name}
    managed-by: 08.ravendb
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: ${ingress_host}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${instance_name}-ravendb-cluster
                port:
                  number: 8080
MANIFEST
    if [[ $? -ne 0 ]]; then
        write_warn "Ingress não aplicado. RavenDB acessível via port-forward."
    else
        write_success "Ingress criado para http://${ingress_host}."
    fi

    # --- ServiceMonitor ---
    # RavenDB expõe métricas Prometheus nativamente em /metrics na mesma porta HTTP (8080).
    write_step "Criando ServiceMonitor para RavenDB '$instance_name'..."
    kubectl apply -f - << MANIFEST
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ravendb-${instance_name}
  namespace: ${namespace}
  labels:
    app: ${instance_name}
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/instance: ${instance_name}
  endpoints:
    - port: http
      interval: 30s
      path: /metrics
MANIFEST
    if [[ $? -ne 0 ]]; then
        write_warn "ServiceMonitor não aplicado. Métricas do RavenDB não serão coletadas."
    else
        write_success "ServiceMonitor criado. Métricas disponíveis no Grafana."
    fi

    echo ""
    echo -e "${GREEN}============================================${RESET}"
    echo -e "${GREEN}  Instância RavenDB criada com sucesso!${RESET}"
    echo -e "${GREEN}============================================${RESET}"
    echo ""
    echo "  Namespace : ${namespace}"
    echo "  Instância : ${instance_name}"
    echo "  Modo      : Não-seguro (workshop/dev)"
    echo ""
    echo -e "  ${YELLOW}Aguardar o pod ficar pronto:${RESET}"
    echo "    kubectl -n ${namespace} get pods -l app.kubernetes.io/instance=${instance_name} -w"
    echo ""
    echo -e "  ${YELLOW}Adicionar ao /etc/hosts (ou executar sudo bash 09.atualizar-hosts.sh):${RESET}"
    echo "    127.0.0.1  ${ingress_host}"
    echo ""
    echo -e "  ${YELLOW}Management Studio (navegador):${RESET}"
    echo "    http://${ingress_host}"
    echo ""
    echo -e "  ${YELLOW}URL interna (dentro do cluster):${RESET}"
    echo "    http://${instance_name}-ravendb-cluster.${namespace}.svc.cluster.local:8080"
    echo ""
    write_warn "Modo não-seguro: use apenas para desenvolvimento/workshop."
    echo ""
    echo -e "  ${YELLOW}Licença gratuita (Community/Developer):${RESET}"
    echo "    https://ravendb.net/buy  →  'Developer' (gratuito)"
    echo "    Cole a licença no Management Studio em: About > Register"
    echo ""
fi

# ===========================================================================
# REMOVER INSTÂNCIA
# ===========================================================================
if [[ "$action" == "2" ]]; then

    mapfile -t instances < <(get_all_raven_instances)

    if [[ ${#instances[@]} -eq 0 ]]; then
        echo ""
        write_warn "Nenhuma instância RavenDB encontrada no cluster."
        exit 0
    fi

    echo ""
    echo -e "  ${CYAN}Instâncias RavenDB existentes:${RESET}"
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
    name=$(echo "${instances[$idx]}" | cut -f2)

    write_step "Removendo instância RavenDB '$name' do namespace '$ns'..."
    helm uninstall "$name" --namespace "$ns"
    kubectl -n "$ns" delete ingress      "ravendb-${name}" --ignore-not-found >/dev/null
    kubectl -n "$ns" delete servicemonitor "ravendb-${name}" --ignore-not-found >/dev/null

    write_warn "PVC do RavenDB pode ter ficado para trás. Para remover:"
    write_warn "  kubectl -n ${ns} delete pvc -l app.kubernetes.io/instance=${name}"
    write_success "Instância RavenDB '$name' removida do namespace '$ns'."
    echo ""
fi
