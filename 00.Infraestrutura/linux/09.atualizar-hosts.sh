#!/usr/bin/env bash
# ==============================================================================
# SYNOPSIS
#   Atualiza o /etc/hosts com todas as entradas de Ingress do cluster k3d.
#
# DESCRIPTION
#   Gerencia um bloco marcado no /etc/hosts com todas as entradas necessárias
#   para acessar os serviços do cluster via navegador.
#
#   Entradas ESTÁTICAS (sempre presentes quando o monitoramento estiver instalado):
#     127.0.0.1   grafana.monitoramento.local
#     127.0.0.1   loki.monitoramento.local
#     127.0.0.1   tempo.monitoramento.local
#     127.0.0.1   pyroscope.monitoramento.local
#
#   Entradas DINÂMICAS (descobertas consultando o cluster):
#     Todos os hosts de recursos Ingress existentes no cluster.
#     Ex: 127.0.0.1   minha-app-ravendb.k3d.localhost
#
#   O script é IDEMPOTENTE: re-executar substitui o bloco sem duplicar linhas.
#   Requer root/sudo para editar o /etc/hosts — auto-eleva via exec sudo.
#
# USAGE
#   sudo bash 09.atualizar-hosts.sh          # Atualiza entradas
#   sudo bash 09.atualizar-hosts.sh -r       # Remove o bloco gerenciado
#   sudo bash 09.atualizar-hosts.sh --remover
#
# NOTES
#   O bloco no hosts é delimitado por:
#     # --- k8s-monitoramento BEGIN ---
#     # --- k8s-monitoramento END ---
#   Não edite manualmente as linhas dentro do bloco.
# ==============================================================================

set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

write_step()    { echo -e "\n${CYAN}==> $1${RESET}"; }
write_success() { echo -e "    ${GREEN}OK: $1${RESET}"; }
write_warn()    { echo -e "    ${YELLOW}AVISO: $1${RESET}"; }
write_fail()    { echo -e "\n    ${RED}ERRO: $1${RESET}"; exit 1; }

# ---------------------------------------------------------------------------
# 0. Parse arguments
# ---------------------------------------------------------------------------
remover=false
for arg in "$@"; do
    [[ "$arg" == "-r" || "$arg" == "--remover" ]] && remover=true
done

# ---------------------------------------------------------------------------
# 1. Verificar / obter root
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}Este script precisa ser executado como root. Elevando com sudo...${RESET}"
    exec sudo "$0" "$@"
fi

# ---------------------------------------------------------------------------
# 2. Configurações
# ---------------------------------------------------------------------------
HOSTS_FILE="/etc/hosts"
BLOCK_BEGIN="# --- k8s-monitoramento BEGIN ---"
BLOCK_END="# --- k8s-monitoramento END ---"
IP="127.0.0.1"

STATIC_HOSTS=(
    "grafana.monitoramento.local"
    "loki.monitoramento.local"
    "tempo.monitoramento.local"
    "pyroscope.monitoramento.local"
)

# ---------------------------------------------------------------------------
# 3. Ler arquivo hosts
# ---------------------------------------------------------------------------
write_step "Lendo ${HOSTS_FILE} ..."

[[ -f "$HOSTS_FILE" ]] || write_fail "Arquivo hosts não encontrado: ${HOSTS_FILE}"

hosts_content="$(cat "$HOSTS_FILE")"

# ---------------------------------------------------------------------------
# 4. Modo remoção: apagar apenas o bloco gerenciado
# ---------------------------------------------------------------------------
if [[ "$remover" == "true" ]]; then
    if ! echo "$hosts_content" | grep -qF "$BLOCK_BEGIN"; then
        write_warn "Bloco gerenciado não encontrado no arquivo hosts. Nada a remover."
        exit 0
    fi

    backup="${HOSTS_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
    cp "$HOSTS_FILE" "$backup"
    write_warn "Backup salvo em ${backup}"

    # Remove o bloco entre os marcadores (incluindo linhas em branco antes/depois)
    perl -i -0pe 's/\n*\Q'"$BLOCK_BEGIN"'\E.*?\Q'"$BLOCK_END"'\E\n*//s' "$HOSTS_FILE"

    write_success "Bloco k8s-monitoramento removido do arquivo hosts."
    exit 0
fi

# ---------------------------------------------------------------------------
# 5. Descobrir hosts dinâmicos consultando o cluster
# ---------------------------------------------------------------------------
write_step "Consultando Ingresses no cluster k3d..."

declare -a dynamic_hosts=()

if ingress_json=$(kubectl get ingress -A -o json 2>/dev/null); then
    while IFS= read -r host; do
        [[ -z "$host" ]] && continue
        # Omit if already in static list
        skip=false
        for s in "${STATIC_HOSTS[@]}"; do
            [[ "$host" == "$s" ]] && skip=true && break
        done
        $skip && continue
        # Dedup
        for d in "${dynamic_hosts[@]:-}"; do
            [[ "$host" == "$d" ]] && skip=true && break
        done
        $skip && continue
        dynamic_hosts+=("$host")
    done < <(echo "$ingress_json" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data.get('items', []):
    for rule in item.get('spec', {}).get('rules', []):
        h = rule.get('host', '')
        if h:
            print(h)")
else
    write_warn "kubectl não retornou Ingresses (cluster pode estar desligado)."
    write_warn "Apenas as entradas estáticas serão adicionadas."
fi

# Merge and sort unique
all_hosts=("${STATIC_HOSTS[@]}" "${dynamic_hosts[@]:-}")
mapfile -t all_hosts < <(printf '%s\n' "${all_hosts[@]}" | sort -u)

# ---------------------------------------------------------------------------
# 6. Construir o novo bloco
# ---------------------------------------------------------------------------
timestamp="$(date '+%Y-%m-%d %H:%M')"
new_block="${BLOCK_BEGIN}
# Gerado automaticamente por 09.atualizar-hosts.sh em ${timestamp}
# Não edite manualmente as linhas dentro deste bloco.
"

for h in "${all_hosts[@]}"; do
    new_block+="${IP}	${h}
"
done
new_block+="${BLOCK_END}"

# ---------------------------------------------------------------------------
# 7. Substituir ou inserir o bloco
# ---------------------------------------------------------------------------
write_step "Atualizando ${HOSTS_FILE} ..."

backup="${HOSTS_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
cp "$HOSTS_FILE" "$backup"
write_warn "Backup salvo em ${backup}"

if echo "$hosts_content" | grep -qF "$BLOCK_BEGIN"; then
    # Bloco já existe: substituir
    perl -i -0pe 's/\Q'"$BLOCK_BEGIN"'\E.*?\Q'"$BLOCK_END"'\E/'"$(printf '%s' "$new_block" | sed 's/[\/&]/\\&/g')"'/s' "$HOSTS_FILE"
else
    # Bloco ainda não existe: acrescentar ao final
    printf '\n\n%s\n' "$new_block" >> "$HOSTS_FILE"
fi

# ---------------------------------------------------------------------------
# 8. Resumo
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}============================================${RESET}"
echo -e "${GREEN}  Arquivo hosts atualizado com sucesso!${RESET}"
echo -e "${GREEN}============================================${RESET}"
echo ""
echo -e "  ${CYAN}Entradas estáticas (monitoramento):${RESET}"
for h in "${STATIC_HOSTS[@]}"; do
    echo "    ${IP}  ${h}"
done

if [[ ${#dynamic_hosts[@]:-0} -gt 0 ]]; then
    echo ""
    echo -e "  ${CYAN}Entradas dinâmicas (descobertas no cluster):${RESET}"
    for h in "${dynamic_hosts[@]}"; do
        echo "    ${IP}  ${h}"
    done
else
    echo ""
    write_warn "Nenhuma entrada dinâmica encontrada (sem Ingresses extras no cluster)."
fi

echo ""
echo -e "  ${YELLOW}Para remover todas as entradas gerenciadas:${RESET}"
echo "    sudo bash 09.atualizar-hosts.sh --remover"
echo ""
