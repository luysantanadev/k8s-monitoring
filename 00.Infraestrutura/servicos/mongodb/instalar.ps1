#Requires -Version 7.0
<#
.SYNOPSIS
    Instala MongoDB Community Operator + instancia no namespace 'mongodb'.
.NOTES
    Namespace  : mongodb   | Resource: mongodb
    Usuario    : workshop  | Banco: admin
    Senha      : Workshop123mongo
    Acesso TCP : localhost:27017  (entrypoint 'mongodb' no Traefik)
    Metricas   : ServiceMonitor porta 9216
    Idempotente: re-executar e seguro.
#>
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot

function Write-Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "`n    ERRO: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# 1. Namespace (precisa existir antes do operator para watchNamespace)
# ---------------------------------------------------------------------------
Write-Step "Criando namespace 'mongodb'..."
kubectl create namespace mongodb --dry-run=client -o yaml | kubectl apply -f - | Out-Null
Write-Success "Namespace pronto."

# ---------------------------------------------------------------------------
# 2. Remover StatefulSet orfao (criado sem operator, causa backoff infinito)
#    Se o manifest.yaml foi aplicado antes do operator, o StatefulSet fica
#    preso em FailedCreate porque a ServiceAccount nao existe ainda.
# ---------------------------------------------------------------------------
Write-Step "Verificando StatefulSet orfao (sem operator)..."
$stsPresent  = kubectl get statefulset -n mongodb mongodb 2>$null
$helmPresent = helm list -n mongodb -q 2>$null | Where-Object { $_ -eq 'community-operator' }
if ($stsPresent -and -not $helmPresent) {
    Write-Warn "StatefulSet mongodb encontrado sem operator instalado — removendo para evitar backoff..."
    kubectl delete statefulset -n mongodb mongodb 2>$null | Out-Null
    Write-Success "StatefulSet orfao removido."
} else {
    Write-Success "Nenhum StatefulSet orfao encontrado."
}

# ---------------------------------------------------------------------------
# 3. Limpeza de release anterior em namespace diferente
#    O CRD carrega anotacao do namespace antigo; helm nao consegue importar
# ---------------------------------------------------------------------------
Write-Step "Verificando instalacao anterior do operator..."
$oldRelease = helm list -n mongodb-operator -q 2>$null | Where-Object { $_ -eq 'community-operator' }
if ($oldRelease) {
    Write-Warn "Release encontrado em mongodb-operator — removendo antes de reinstalar..."
    helm uninstall community-operator -n mongodb-operator 2>&1 | Out-Null
    # Reanotar CRDs para que o novo helm release possa assumir ownership
    $crds = @(
        'mongodbcommunity.mongodbcommunity.mongodb.com',
        'mongodbusers.mongodbcommunity.mongodb.com'
    )
    foreach ($crd in $crds) {
        kubectl annotate crd $crd `
            'meta.helm.sh/release-name=community-operator' `
            'meta.helm.sh/release-namespace=mongodb' `
            --overwrite 2>$null | Out-Null
        kubectl label crd $crd 'app.kubernetes.io/managed-by=Helm' --overwrite 2>$null | Out-Null
    }
    Write-Success "Release antigo removido e CRDs reannotados."
} else {
    Write-Success "Nenhum release antigo encontrado."
}

# ---------------------------------------------------------------------------
# 3. MongoDB Community Operator (instalado no mesmo namespace do banco)
#    operator.watchNamespace=mongodb evita problemas de RBAC cross-namespace
# ---------------------------------------------------------------------------
Write-Step "Instalando MongoDB Community Operator..."
helm repo add mongodb https://mongodb.github.io/helm-charts --force-update 2>&1 | Out-Null
helm repo update mongodb 2>&1 | Out-Null
helm upgrade --install community-operator mongodb/community-operator `
    --namespace mongodb `
    --set operator.watchNamespace='mongodb'
if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao instalar MongoDB Community Operator." }
Write-Success "Operator pronto."

Write-Step "Aplicando Secrets e MongoDBCommunity..."
kubectl apply -f "$scriptDir/manifest.yaml"
if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao aplicar manifest.yaml." }
Write-Success "Secrets e MongoDBCommunity aplicados."

# Aguarda StatefulSet ser criado pelo operator (pode levar 1-2 min)
Write-Step "Aguardando StatefulSet mongodb ser criado pelo operator..."
$timeout = 180
$elapsed = 0
do {
    Start-Sleep 5
    $elapsed += 5
    $phase = kubectl -n mongodb get mongodbcommunity mongodb -o jsonpath='{.status.phase}' 2>$null
    Write-Host "    phase: $phase (${elapsed}s)" -ForegroundColor DarkGray
} while ($phase -ne 'Running' -and $elapsed -lt $timeout)

if ($phase -ne 'Running') {
    Write-Warn "MongoDB ainda nao ficou Running. Verifique: kubectl -n mongodb describe mongodbcommunity mongodb"
} else {
    Write-Success "MongoDB cluster Running."
}

# ---------------------------------------------------------------------------
# 3. IngressRouteTCP — expoe localhost:27017
# ---------------------------------------------------------------------------
Write-Step "Aplicando IngressRouteTCP (porta 27017)..."
@"
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: mongodb
  namespace: mongodb
spec:
  entryPoints:
    - mongodb
  routes:
    - match: HostSNI(``*``)
      services:
        - name: mongodb-svc
          port: 27017
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "IngressRouteTCP nao aplicado." }
else { Write-Success "MongoDB acessivel em localhost:27017." }

# ---------------------------------------------------------------------------
# 4. ServiceMonitor (Prometheus)
# ---------------------------------------------------------------------------
Write-Step "Criando ServiceMonitor..."
@"
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
"@ | kubectl apply -f -
if ($LASTEXITCODE -ne 0) { Write-Warn "ServiceMonitor nao aplicado." }
else { Write-Success "ServiceMonitor criado." }

# ---------------------------------------------------------------------------
# Resumo
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  MongoDB pronto!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Namespace  : mongodb"
Write-Host "  Usuario    : workshop"
Write-Host "  Senha      : Workshop123mongo"
Write-Host "  Host local : localhost:27017"
Write-Host "  URI        : mongodb://workshop:Workshop123mongo@localhost:27017/?authSource=admin"
Write-Host ""
Write-Host "  Aguardar cluster pronto (pode levar 2-3 min):" -ForegroundColor Yellow
Write-Host "    kubectl -n mongodb get mongodbcommunity mongodb -w"
Write-Host ""
