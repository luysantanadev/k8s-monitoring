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

# 1. Namespace
step "Criando namespace 'ravendb'..."
kubectl create namespace ravendb --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "Namespace pronto."

# 2. RavenDB — StatefulSet + Service (modo nao-seguro/workshop)
# O chart oficial ravendb/ravendb-cluster exige setup package TLS + licenca,
# incompativel com Setup.Mode=None. Usamos manifest direto com a imagem oficial.
step "Implantando RavenDB (StatefulSet + Service)..."
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ravendb
  namespace: ravendb
  labels:
    app: ravendb
spec:
  serviceName: ravendb
  replicas: 1
  selector:
    matchLabels:
      app: ravendb
  template:
    metadata:
      labels:
        app: ravendb
        app.kubernetes.io/instance: ravendb
    spec:
      securityContext:
        runAsNonRoot: false
      containers:
        - name: ravendb
          image: ravendb/ravendb:latest
          imagePullPolicy: IfNotPresent
          env:
            - name: RAVEN_Security_UnsecuredAccessAllowed
              value: "PublicNetwork"
            - name: RAVEN_Setup_Mode
              value: "None"
          ports:
            - name: http
              containerPort: 8080
            - name: tcp
              containerPort: 38888
          resources:
            requests:
              cpu: 200m
              memory: 512Mi
            limits:
              cpu: "1"
              memory: 1Gi
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10
          volumeMounts:
            - name: data
              mountPath: /var/lib/ravendb/data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 2Gi
---
apiVersion: v1
kind: Service
metadata:
  name: ravendb
  namespace: ravendb
  labels:
    app: ravendb
    app.kubernetes.io/instance: ravendb
spec:
  selector:
    app: ravendb
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: tcp
      port: 38888
      targetPort: 38888
EOF

step "Aguardando RavenDB ficar pronto..."
kubectl rollout status statefulset/ravendb -n ravendb --timeout=180s \
    || fail "RavenDB nao ficou pronto a tempo."
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
                name: ravendb
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
  namespaceSelector:
    matchNames:
      - ravendb
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
