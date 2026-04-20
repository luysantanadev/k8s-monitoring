#Requires -Version 7.0
<#
.SYNOPSIS
    Instala RavenDB no namespace 'ravendb'.
.NOTES
    Namespace  : ravendb   | Release: ravendb
    Modo       : Nao-seguro (workshop/dev) — sem TLS, sem autenticacao
    UI         : http://ravendb.monitoramento.local  (adicionar ao /etc/hosts)
    Metricas   : ServiceMonitor em /metrics porta 8080
    Licenca    : Editar services/ravendb/values.yaml (campo ravendb.license)
    Idempotente: re-executar e seguro.
#>
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

function Write-Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "`n    ERRO: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# 1. Namespace
# ---------------------------------------------------------------------------
Write-Step "Criando namespace 'ravendb'..."
kubectl create namespace ravendb --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Success "Namespace pronto."

# ---------------------------------------------------------------------------
# 2. RavenDB — StatefulSet + Service (modo nao-seguro/workshop)
# O chart oficial ravendb/ravendb-cluster exige setup package TLS + licenca,
# incompativel com Setup.Mode=None. Usamos manifest direto com a imagem oficial.
# ---------------------------------------------------------------------------
Write-Step "Implantando RavenDB (StatefulSet + Service)..."
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
"@ | kubectl apply -f -
if (`$LASTEXITCODE -ne 0) { Write-Fail "StatefulSet/Service nao aplicado." }

Write-Step "Aguardando RavenDB ficar pronto..."
kubectl rollout status statefulset/ravendb -n ravendb --timeout=180s
if (`$LASTEXITCODE -ne 0) { Write-Fail "RavenDB nao ficou pronto a tempo." }
Write-Success "RavenDB instalado."

# ---------------------------------------------------------------------------
# 4. Ingress HTTP (porta 8080 via porta 80)
# ---------------------------------------------------------------------------
Write-Step "Criando Ingress HTTP para ravendb.monitoramento.local..."
@"
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
"@ | kubectl apply -f -
if (`$LASTEXITCODE -ne 0) { Write-Warn "Ingress nao aplicado." }
else { Write-Success "RavenDB Studio em http://ravendb.monitoramento.local." }

# ---------------------------------------------------------------------------
# 5. ServiceMonitor (Prometheus — metricas nativas em /metrics)
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
if (`$LASTEXITCODE -ne 0) { Write-Warn "ServiceMonitor nao aplicado." }
else { Write-Success "ServiceMonitor criado." }

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  RavenDB pronto!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Namespace  : ravendb"
Write-Host "  Modo       : Nao-seguro (dev/workshop)"
Write-Host "  UI         : http://ravendb.monitoramento.local"
Write-Host ""
Write-Host "  Adicionar ao hosts (se necessario):" -ForegroundColor Yellow
Write-Host "    127.0.0.1  ravendb.monitoramento.local"
Write-Host ""
Write-Host "  Aguardar pronto:" -ForegroundColor Yellow
Write-Host "    kubectl -n ravendb get pods -w"
Write-Host ""
Write-Host "  NOTA: Para adicionar licenca, edite values.yaml (campo ravendb.license)" -ForegroundColor Yellow
Write-Host "        e re-execute este script." -ForegroundColor Yellow
Write-Host ""
