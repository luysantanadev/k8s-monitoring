#Requires -Version 7.0
<#
.SYNOPSIS
    Implanta RavenDB como cluster de 3 nos no namespace 'ravendb'.
.NOTES
    Namespace  : ravendb   | Nos: ravendb-0, ravendb-1, ravendb-2
    Modo       : Nao-seguro (workshop/dev) — sem TLS, sem autenticacao
    No A       : http://a.ravendb.monitoramento.local
    No B       : http://b.ravendb.monitoramento.local
    No C       : http://c.ravendb.monitoramento.local
    Metricas   : ServiceMonitor em /metrics porta 8080 (servico headless)
    Licenca    : Adicionar via Studio apos implantacao (Manage Server > License)
    Idempotente: re-executar e seguro.

    Apos implantacao:
      1. Acesse http://a.ravendb.monitoramento.local e ative a licenca Developer
      2. Va em Manage Server > Cluster > Add Node e adicione:
            No B: http://ravendb-1.ravendb.ravendb.svc.cluster.local:8080
            No C: http://ravendb-2.ravendb.ravendb.svc.cluster.local:8080
#>
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

function Write-Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "`n    ERRO: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# 0. Limpeza de deploy existente
# Se o StatefulSet ja existe, remove todos os recursos do namespace antes de
# reaplicar para garantir configuracao limpa (evita conflitos de PVC/config).
# ---------------------------------------------------------------------------
$existingStatefulSet = kubectl get statefulset ravendb -n ravendb --ignore-not-found -o name 2>$null
if ($existingStatefulSet) {
    Write-Warn "Deploy existente detectado. Removendo recursos anteriores..."
    kubectl delete statefulset ravendb -n ravendb --ignore-not-found | Out-Null

    Write-Warn "Aguardando pods encerrarem..."
    kubectl wait pod -l app=ravendb -n ravendb --for=delete --timeout=120s 2>$null | Out-Null

    kubectl delete pvc -l app=ravendb -n ravendb --ignore-not-found | Out-Null
    kubectl delete service ravendb ravendb-0 ravendb-1 ravendb-2 -n ravendb --ignore-not-found 2>$null | Out-Null
    kubectl delete configmap ravendb-config -n ravendb --ignore-not-found | Out-Null
    kubectl delete ingress ravendb ravendb-a ravendb-b ravendb-c -n ravendb --ignore-not-found 2>$null | Out-Null
    kubectl delete servicemonitor ravendb -n ravendb --ignore-not-found 2>$null | Out-Null
    Write-Success "Recursos anteriores removidos."
}

# ---------------------------------------------------------------------------
# 1. Namespace
# ---------------------------------------------------------------------------
Write-Step "Criando namespace 'ravendb'..."
kubectl create namespace ravendb --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Success "Namespace pronto."

# ---------------------------------------------------------------------------
# 2. ConfigMap — configuracao por no
# Cada pod usa $HOSTNAME (ravendb-0/1/2) para carregar o arquivo de config
# correto montado em /config. O PublicServerUrl aponta para o DNS headless do
# respectivo pod, permitindo comunicacao inter-nos no cluster RavenDB.
# ---------------------------------------------------------------------------
Write-Step "Criando ConfigMap de configuracao por no..."
@"
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
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Fail "ConfigMap nao aplicado." }
Write-Success "ConfigMap criado."

# ---------------------------------------------------------------------------
# 3. RavenDB — StatefulSet (3 nos) + Services
# Servico headless 'ravendb' (clusterIP: None) fornece o DNS estavel para
# comunicacao inter-nos: ravendb-N.ravendb.ravendb.svc.cluster.local.
# Servicos individuais 'ravendb-0/1/2' permitem roteamento direto via Ingress.
# ---------------------------------------------------------------------------
Write-Step "Implantando cluster RavenDB (3 nos)..."
@"
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
            - exec /usr/lib/ravendb/server/Raven.Server --config-path /config/`$HOSTNAME
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
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Fail "StatefulSet/Services nao aplicados." }

Write-Step "Aguardando os 3 nos ficarem prontos (pode demorar ~3 min)..."
kubectl rollout status statefulset/ravendb -n ravendb --timeout=300s
if ($LASTEXITCODE -ne 0) { Write-Fail "RavenDB cluster nao ficou pronto a tempo." }
Write-Success "Cluster RavenDB (3 nos) instalado."

# ---------------------------------------------------------------------------
# 4. Ingress HTTP — um host por no para acesso individual ao Studio
# ---------------------------------------------------------------------------
Write-Step "Criando Ingresses para os 3 nos (a/b/c.ravendb.monitoramento.local)..."
@"
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
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "Ingresses nao aplicados." }
else { Write-Success "Ingresses criados (nos A, B, C)." }

# ---------------------------------------------------------------------------
# 5. ServiceMonitor (Prometheus — scrape em todos os pods via servico headless)
# ---------------------------------------------------------------------------
Write-Step "Criando ServiceMonitor..."
@"
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
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "ServiceMonitor nao aplicado." }
else { Write-Success "ServiceMonitor criado." }

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  RavenDB cluster (3 nos) pronto!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Namespace  : ravendb"
Write-Host "  Modo       : Nao-seguro (dev/workshop)"
Write-Host "  No A       : http://a.ravendb.monitoramento.local"
Write-Host "  No B       : http://b.ravendb.monitoramento.local"
Write-Host "  No C       : http://c.ravendb.monitoramento.local"
Write-Host ""
Write-Host "  Adicionar ao /etc/hosts (ou re-executar o script 09):" -ForegroundColor Yellow
Write-Host "    127.0.0.1  a.ravendb.monitoramento.local"
Write-Host "    127.0.0.1  b.ravendb.monitoramento.local"
Write-Host "    127.0.0.1  c.ravendb.monitoramento.local"
Write-Host ""
Write-Host "  Passos apos implantacao:" -ForegroundColor Yellow
Write-Host "  1. Acesse http://a.ravendb.monitoramento.local"
Write-Host "     Manage Server > License > Activate License (Developer)"
Write-Host "  2. Adicione os outros nos ao cluster RavenDB:"
Write-Host "     Manage Server > Cluster > Add Node"
Write-Host "     No B: http://ravendb-1.ravendb.ravendb.svc.cluster.local:8080"
Write-Host "     No C: http://ravendb-2.ravendb.ravendb.svc.cluster.local:8080"
Write-Host ""
Write-Host "  Verificar pods:" -ForegroundColor Yellow
Write-Host "    kubectl -n ravendb get pods -w"
Write-Host ""
