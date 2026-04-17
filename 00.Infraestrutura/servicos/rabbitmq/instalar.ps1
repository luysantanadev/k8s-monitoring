#Requires -Version 7.0
<#
.SYNOPSIS
    Instala RabbitMQ (Bitnami OCI) no namespace 'rabbitmq'.
.NOTES
    Namespace  : rabbitmq  | Release: rabbitmq
    Usuario    : user      | Senha: Workshop123rabbit
    AMQP TCP   : localhost:5672  (entrypoint 'amqp' no Traefik)
    UI         : http://rabbitmq.k3d.localhost  (adicionar ao /etc/hosts)
    Metricas   : ServiceMonitor porta 9419 (via values.yaml)
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
Write-Step "Criando namespace 'rabbitmq'..."
kubectl create namespace rabbitmq --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Success "Namespace pronto."

# ---------------------------------------------------------------------------
# 2. RabbitMQ (OCI chart — sem helm repo add)
# ---------------------------------------------------------------------------
Write-Step "Instalando RabbitMQ 'rabbitmq'..."
helm upgrade --install rabbitmq oci://registry-1.docker.io/bitnamicharts/rabbitmq `
    --namespace rabbitmq `
    --values "$scriptDir/values.yaml" `
    --wait --timeout 180s
if ($LASTEXITCODE -ne 0) { Write-Fail "Helm install falhou." }
Write-Success "RabbitMQ instalado."

# ---------------------------------------------------------------------------
# 3. IngressRouteTCP — expoe localhost:5672 (AMQP)
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
# Resumo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  RabbitMQ pronto!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Namespace  : rabbitmq"
Write-Host "  Usuario    : user"
Write-Host "  Senha      : Workshop123rabbit"
Write-Host "  AMQP       : amqp://user:Workshop123rabbit@localhost:5672"
Write-Host "  UI         : http://rabbitmq.k3d.localhost"
Write-Host ""
Write-Host "  Adicionar ao hosts (se necessario):" -ForegroundColor Yellow
Write-Host "    127.0.0.1  rabbitmq.k3d.localhost"
Write-Host ""
Write-Host "  Aguardar pronto:" -ForegroundColor Yellow
Write-Host "    kubectl -n rabbitmq get pods -w"
Write-Host ""
