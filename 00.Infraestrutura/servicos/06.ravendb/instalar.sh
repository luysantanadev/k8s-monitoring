#!/usr/bin/env bash
# Implanta RavenDB como cluster de 3 nos no namespace 'ravendb'.
#
# Namespace  : ravendb   | Nos: ravendb-0, ravendb-1, ravendb-2
# Modo       : Nao-seguro (workshop/dev) — sem TLS, sem autenticacao
# No A       : http://a.ravendb.monitoramento.local
# No B       : http://b.ravendb.monitoramento.local
# No C       : http://c.ravendb.monitoramento.local
# Metricas   : ServiceMonitor em /metrics porta 8080 (servico headless)
# Licenca    : Adicionar via Studio apos implantacao (Manage Server > License)
# Idempotente: re-executar e seguro.
#
# Apos implantacao:
#   1. Acesse http://a.ravendb.monitoramento.local e ative a licenca Developer
#   2. Va em Manage Server > Cluster > Add Node e adicione:
#         No B: http://ravendb-1.ravendb.ravendb.svc.cluster.local:8080
#         No C: http://ravendb-2.ravendb.ravendb.svc.cluster.local:8080
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==> $1${NC}"; }
ok()   { echo -e "    ${GREEN}OK: $1${NC}"; }
warn() { echo -e "    ${YELLOW}AVISO: $1${NC}"; }
fail() { echo -e "\n    ${RED}ERRO: $1${NC}"; exit 1; }

# 0. Limpeza de deploy existente
# Se o StatefulSet ja existe, remove todos os recursos do namespace antes de
# reaplicar para garantir configuracao limpa (evita conflitos de PVC/config).
if kubectl get statefulset ravendb -n ravendb --ignore-not-found -o name 2>/dev/null | grep -q .; then
    warn "Deploy existente detectado. Removendo recursos anteriores..."
    kubectl delete statefulset ravendb -n ravendb --ignore-not-found

    warn "Aguardando pods encerrarem..."
    kubectl wait pod -l app=ravendb -n ravendb --for=delete --timeout=120s 2>/dev/null || true

    kubectl delete pvc -l app=ravendb -n ravendb --ignore-not-found
    kubectl delete service ravendb ravendb-0 ravendb-1 ravendb-2 -n ravendb --ignore-not-found 2>/dev/null || true
    kubectl delete configmap ravendb-config -n ravendb --ignore-not-found
    kubectl delete ingress ravendb ravendb-a ravendb-b ravendb-c -n ravendb --ignore-not-found 2>/dev/null || true
    kubectl delete servicemonitor ravendb -n ravendb --ignore-not-found 2>/dev/null || true
    ok "Recursos anteriores removidos."
fi

# 1. Namespace
step "Criando namespace 'ravendb'..."
kubectl create namespace ravendb --dry-run=client -o yaml | kubectl apply -f - >/dev/null
ok "Namespace pronto."

# 2. ConfigMap — configuracao por no
# Cada pod usa $HOSTNAME (ravendb-0/1/2) para carregar o arquivo de config
# correto montado em /config. O PublicServerUrl aponta para o DNS headless do
# respectivo pod, permitindo comunicacao inter-nos no cluster RavenDB.
step "Criando ConfigMap de configuracao por no..."
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: ravendb-config
  namespace: ravendb
  labels:
    app: ravendb
data:
  ravendb-0: |
    {
      "Setup.Mode": "None",
      "DataDir": "/var/lib/ravendb/data",
      "ServerUrl": "http://0.0.0.0:8080",
      "ServerUrl.Tcp": "tcp://0.0.0.0:38888",
      "PublicServerUrl": "http://ravendb-0.ravendb.ravendb.svc.cluster.local:8080",
      "PublicServerUrl.Tcp": "tcp://ravendb-0.ravendb.ravendb.svc.cluster.local:38888",
      "Security.UnsecuredAccessAllowed": "PublicNetwork",
      "License.Eula.Accepted": "true"
    }
  ravendb-1: |
    {
      "Setup.Mode": "None",
      "DataDir": "/var/lib/ravendb/data",
      "ServerUrl": "http://0.0.0.0:8080",
      "ServerUrl.Tcp": "tcp://0.0.0.0:38888",
      "PublicServerUrl": "http://ravendb-1.ravendb.ravendb.svc.cluster.local:8080",
      "PublicServerUrl.Tcp": "tcp://ravendb-1.ravendb.ravendb.svc.cluster.local:38888",
      "Security.UnsecuredAccessAllowed": "PublicNetwork",
      "License.Eula.Accepted": "true"
    }
  ravendb-2: |
    {
      "Setup.Mode": "None",
      "DataDir": "/var/lib/ravendb/data",
      "ServerUrl": "http://0.0.0.0:8080",
      "ServerUrl.Tcp": "tcp://0.0.0.0:38888",
      "PublicServerUrl": "http://ravendb-2.ravendb.ravendb.svc.cluster.local:8080",
      "PublicServerUrl.Tcp": "tcp://ravendb-2.ravendb.ravendb.svc.cluster.local:38888",
      "Security.UnsecuredAccessAllowed": "PublicNetwork",
      "License.Eula.Accepted": "true"
    }
EOF
ok "ConfigMap criado."

# 3. RavenDB — StatefulSet (3 nos) + Services
# Servico headless 'ravendb' (clusterIP: None) fornece o DNS estavel para
# comunicacao inter-nos: ravendb-N.ravendb.ravendb.svc.cluster.local.
# Servicos individuais 'ravendb-0/1/2' permitem roteamento direto via Ingress.
step "Implantando cluster RavenDB (3 nos)..."
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
  replicas: 3
  podManagementPolicy: OrderedReady
  updateStrategy:
    type: RollingUpdate
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
      terminationGracePeriodSeconds: 120
      containers:
        - name: ravendb
          image: ravendb/ravendb:latest
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - exec /usr/lib/ravendb/server/Raven.Server --config-path /config/$HOSTNAME
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
            initialDelaySeconds: 20
            periodSeconds: 10
            failureThreshold: 6
          livenessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 60
            periodSeconds: 20
            failureThreshold: 3
          volumeMounts:
            - name: data
              mountPath: /var/lib/ravendb/data
            - name: config
              mountPath: /config
      volumes:
        - name: config
          configMap:
            name: ravendb-config
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
  clusterIP: None
  selector:
    app: ravendb
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: tcp
      port: 38888
      targetPort: 38888
---
apiVersion: v1
kind: Service
metadata:
  name: ravendb-0
  namespace: ravendb
  labels:
    app: ravendb
spec:
  selector:
    statefulset.kubernetes.io/pod-name: ravendb-0
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: tcp
      port: 38888
      targetPort: 38888
---
apiVersion: v1
kind: Service
metadata:
  name: ravendb-1
  namespace: ravendb
  labels:
    app: ravendb
spec:
  selector:
    statefulset.kubernetes.io/pod-name: ravendb-1
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: tcp
      port: 38888
      targetPort: 38888
---
apiVersion: v1
kind: Service
metadata:
  name: ravendb-2
  namespace: ravendb
  labels:
    app: ravendb
spec:
  selector:
    statefulset.kubernetes.io/pod-name: ravendb-2
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: tcp
      port: 38888
      targetPort: 38888
EOF

step "Aguardando os 3 nos ficarem prontos (pode demorar ~3 min)..."
kubectl rollout status statefulset/ravendb -n ravendb --timeout=300s \
    || fail "RavenDB cluster nao ficou pronto a tempo."
ok "Cluster RavenDB (3 nos) instalado."

# 4. Ingress HTTP — um host por no para acesso individual ao Studio
step "Criando Ingresses para os 3 nos (a/b/c.ravendb.monitoramento.local)..."
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ravendb-a
  namespace: ravendb
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: a.ravendb.monitoramento.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ravendb-0
                port:
                  number: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ravendb-b
  namespace: ravendb
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: b.ravendb.monitoramento.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ravendb-1
                port:
                  number: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ravendb-c
  namespace: ravendb
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: c.ravendb.monitoramento.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ravendb-2
                port:
                  number: 8080
EOF
ok "Ingresses criados (nos A, B, C)."

# 5. ServiceMonitor (Prometheus — scrape em todos os pods via servico headless)
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
echo -e "${GREEN}  RavenDB cluster (3 nos) pronto!${NC}"
echo -e "${GREEN}============================================${NC}"
echo "  Namespace  : ravendb"
echo "  Modo       : Nao-seguro (dev/workshop)"
echo "  No A       : http://a.ravendb.monitoramento.local"
echo "  No B       : http://b.ravendb.monitoramento.local"
echo "  No C       : http://c.ravendb.monitoramento.local"
echo ""
echo -e "  ${YELLOW}Adicionar ao /etc/hosts (ou re-executar o script 09):${NC}"
echo "    127.0.0.1  a.ravendb.monitoramento.local"
echo "    127.0.0.1  b.ravendb.monitoramento.local"
echo "    127.0.0.1  c.ravendb.monitoramento.local"
echo ""
echo -e "  ${YELLOW}Passos apos implantacao:${NC}"
echo "  1. Acesse http://a.ravendb.monitoramento.local"
echo "     Manage Server > License > Activate License (Developer)"
echo "  2. Adicione os outros nos ao cluster RavenDB:"
echo "     Manage Server > Cluster > Add Node"
echo "     No B: http://ravendb-1.ravendb.ravendb.svc.cluster.local:8080"
echo "     No C: http://ravendb-2.ravendb.ravendb.svc.cluster.local:8080"
echo ""
echo -e "  ${YELLOW}Verificar pods:${NC}"
echo "    kubectl -n ravendb get pods -w"
echo ""
