#Requires -Version 7.0
<#
.SYNOPSIS
    Instala RabbitMQ via RabbitMQ Cluster Operator (oficial) no namespace 'rabbitmq'.
.NOTES
    Operator   : rabbitmq-system (instalado via manifest oficial do GitHub)
    Namespace  : rabbitmq
    Usuario    : user      | Senha: Workshop123rabbit
    AMQP TCP   : localhost:5672  (entrypoint 'amqp' no Traefik)
    UI         : http://rabbitmq.monitoramento.local
    Metricas   : ServiceMonitor porta prometheus (15692)
    Idempotente: re-executar e seguro.
#>
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

function Write-Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "`n    ERRO: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# 1. RabbitMQ Cluster Operator
# ---------------------------------------------------------------------------
Write-Step "Instalando RabbitMQ Cluster Operator..."
kubectl apply -f "https://github.com/rabbitmq/cluster-operator/releases/latest/download/cluster-operator.yml"
if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao aplicar cluster-operator.yml." }

Write-Step "Aguardando operator ficar pronto..."
kubectl rollout status deployment/rabbitmq-cluster-operator -n rabbitmq-system --timeout=120s
if ($LASTEXITCODE -ne 0) { Write-Fail "Operator nao ficou pronto a tempo." }
Write-Success "Operator pronto."

# ---------------------------------------------------------------------------
# 2. Namespace
# ---------------------------------------------------------------------------
Write-Step "Criando namespace 'rabbitmq'..."
kubectl create namespace rabbitmq --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Success "Namespace pronto."

# ---------------------------------------------------------------------------
# 3. RabbitmqCluster
# ---------------------------------------------------------------------------
Write-Step "Aplicando RabbitmqCluster (manifest.yaml)..."
kubectl apply -f "$scriptDir/manifest.yaml"
if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao aplicar manifest.yaml." }

Write-Step "Aguardando StatefulSet rabbitmq-server ficar pronto..."
kubectl rollout status statefulset/rabbitmq-server -n rabbitmq --timeout=180s
if ($LASTEXITCODE -ne 0) { Write-Fail "RabbitmqCluster nao ficou pronto a tempo." }
Write-Success "RabbitmqCluster pronto."

# ---------------------------------------------------------------------------
# 4. Ingress — UI de gerenciamento (porta 15672)
# ---------------------------------------------------------------------------
Write-Step "Aplicando Ingress para management UI..."
@"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rabbitmq-management
  namespace: rabbitmq
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  rules:
    - host: rabbitmq.monitoramento.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: rabbitmq
                port:
                  number: 15672
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "Ingress management nao aplicado." }
else { Write-Success "UI acessivel em http://rabbitmq.monitoramento.local" }

# ---------------------------------------------------------------------------
# 5. IngressRouteTCP — expoe localhost:5672 (AMQP)
# ---------------------------------------------------------------------------
Write-Step "Aplicando IngressRouteTCP AMQP (porta 5672)..."
@"
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: rabbitmq-amqp
  namespace: rabbitmq
spec:
  entryPoints:
    - amqp
  routes:
    - match: HostSNI(``*``)
      services:
        - name: rabbitmq
          port: 5672
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "IngressRouteTCP AMQP nao aplicado." }
else { Write-Success "RabbitMQ AMQP acessivel em localhost:5672." }

# ---------------------------------------------------------------------------
# 6. ServiceMonitor — Prometheus scrape (porta prometheus/15692)
# ---------------------------------------------------------------------------
Write-Step "Aplicando ServiceMonitor..."
@"
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rabbitmq
  namespace: rabbitmq
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: rabbitmq
  endpoints:
    - port: prometheus
      interval: 30s
      path: /metrics
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "ServiceMonitor nao aplicado." }
else { Write-Success "ServiceMonitor aplicado." }

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  RabbitMQ pronto!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Namespace  : rabbitmq"
Write-Host "  Operator   : rabbitmq-system"
Write-Host "  Usuario    : user"
Write-Host "  Senha      : Workshop123rabbit"
Write-Host "  AMQP       : amqp://user:Workshop123rabbit@localhost:5672"
Write-Host "  UI         : http://rabbitmq.monitoramento.local"
Write-Host "  Metricas   : porta prometheus (15692)"
Write-Host ""
Write-Host "  Adicionar ao hosts (se necessario):" -ForegroundColor Yellow
Write-Host "    127.0.0.1  rabbitmq.monitoramento.local"
Write-Host ""
Write-Host "  Verificar cluster:" -ForegroundColor Yellow
Write-Host "    kubectl -n rabbitmq get rabbitmqcluster rabbitmq"
Write-Host "    kubectl -n rabbitmq get pods -w"
Write-Host ""
