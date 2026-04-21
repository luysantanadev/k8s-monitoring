#!/usr/bin/env bash
# Instala MongoDB Community Operator + instancia no namespace 'mongodb'.
#
# Namespace  : mongodb   | Resource: mongodb
# Usuario    : workshop  | Banco: admin
# Senha      : Workshop123mongo
# Acesso TCP : localhost:27017  (entrypoint 'mongodb' no Traefik)
# Metricas   : ServiceMonitor porta 9216
# Idempotente: re-executar e seguro.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==> $1${NC}"; }
ok()   { echo -e "    ${GREEN}OK: $1${NC}"; }
warn() { echo -e "    ${YELLOW}AVISO: $1${NC}"; }
fail() { echo -e "\n    ${RED}ERRO: $1${NC}"; exit 1; }

# 1. Namespace (precisa existir antes do operator para watchNamespace)
step "Criando namespace 'mongodb'..."
kubectl create namespace mongodb --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "Namespace pronto."

# 2. Remover StatefulSet orfao (criado sem operator, causa backoff infinito)
#    Se o manifest.yaml foi aplicado antes do operator, o StatefulSet fica
#    preso em FailedCreate porque a ServiceAccount nao existe ainda.
step "Verificando StatefulSet orfao (sem operator)..."
if kubectl get statefulset -n mongodb mongodb &>/dev/null && \
   ! helm list -n mongodb -q 2>/dev/null | grep -q '^community-operator$'; then
    warn "StatefulSet mongodb encontrado sem operator instalado — removendo para evitar backoff..."
    kubectl delete statefulset -n mongodb mongodb 2>/dev/null || true
    ok "StatefulSet orfao removido."
else
    ok "Nenhum StatefulSet orfao encontrado."
fi

# 3. Limpeza de release anterior em namespace diferente
#    O CRD carrega anotacao do namespace antigo; helm nao consegue importar
step "Verificando instalacao anterior do operator..."
if helm list -n mongodb-operator -q 2>/dev/null | grep -q '^community-operator$'; then
    warn "Release encontrado em mongodb-operator — removendo antes de reinstalar..."
    helm uninstall community-operator -n mongodb-operator 2>/dev/null || true
    # Reanotar CRDs para que o novo helm release possa assumir ownership
    for crd in mongodbcommunity.mongodbcommunity.mongodb.com mongodbusers.mongodbcommunity.mongodb.com; do
        kubectl annotate crd "$crd" \
            'meta.helm.sh/release-name=community-operator' \
            'meta.helm.sh/release-namespace=mongodb' \
            --overwrite 2>/dev/null || true
        kubectl label crd "$crd" 'app.kubernetes.io/managed-by=Helm' --overwrite 2>/dev/null || true
    done
    ok "Release antigo removido e CRDs reannotados."
else
    ok "Nenhum release antigo encontrado."
fi

# 3. MongoDB Community Operator (instalado no mesmo namespace do banco)
#    operator.watchNamespace=mongodb evita problemas de RBAC cross-namespace
step "Instalando MongoDB Community Operator..."
helm repo add mongodb https://mongodb.github.io/helm-charts --force-update 2>/dev/null || true
helm repo update mongodb 2>/dev/null
helm upgrade --install community-operator mongodb/community-operator \
    --namespace mongodb \
    --set 'operator.watchNamespace=mongodb' \
    || fail "Falha ao instalar MongoDB Community Operator."
ok "Operator pronto."

step "Aplicando Secrets e MongoDBCommunity..."
kubectl apply -f "$SCRIPT_DIR/manifest.yaml" || fail "Falha ao aplicar manifest.yaml."
ok "Secrets e MongoDBCommunity aplicados."

# Aguarda cluster ficar Running (operator cria StatefulSet em background)
step "Aguardando MongoDBCommunity ficar Running (pode levar 2-3 min)..."
elapsed=0
while [[ $elapsed -lt 180 ]]; do
    phase=$(kubectl -n mongodb get mongodbcommunity mongodb -o jsonpath='{.status.phase}' 2>/dev/null || true)
    echo -e "    phase: ${phase:-unknown} (${elapsed}s)"
    [[ "$phase" == 'Running' ]] && break
    sleep 5
    elapsed=$((elapsed + 5))
done
[[ "$phase" == 'Running' ]] && ok "MongoDB cluster Running." \
    || warn "MongoDB ainda nao ficou Running. Verifique: kubectl -n mongodb describe mongodbcommunity mongodb"

# 3. IngressRouteTCP — expoe localhost:27017
step "Aplicando IngressRouteTCP (porta 27017)..."
kubectl apply -f - <<'EOF'
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: mongodb
  namespace: mongodb
spec:
  entryPoints:
    - mongodb
  routes:
    - match: HostSNI(`*`)
      services:
        - name: mongodb-svc
          port: 27017
EOF
ok "MongoDB acessivel em localhost:27017."

# 4. ServiceMonitor
step "Criando ServiceMonitor..."
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: mongodb
  namespace: mongodb
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: mongodb
  endpoints:
    - port: prometheus
      interval: 30s
EOF
ok "ServiceMonitor criado."

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  MongoDB pronto!${NC}"
echo -e "${GREEN}============================================${NC}"
echo "  Namespace  : mongodb"
echo "  Usuario    : workshop"
echo "  Senha      : Workshop123mongo"
echo "  Host local : localhost:27017"
echo "  URI        : mongodb://workshop:Workshop123mongo@localhost:27017/?authSource=admin"
echo ""
echo -e "  ${YELLOW}Aguardar cluster pronto (pode levar 2-3 min):${NC}"
echo "    kubectl -n mongodb get mongodbcommunity mongodb -w"
echo ""
