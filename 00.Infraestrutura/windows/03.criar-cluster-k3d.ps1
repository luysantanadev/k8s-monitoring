<#
.SYNOPSIS
    Cria o cluster k3d 'monitoramento' com Traefik para o laboratório local de Kubernetes.

.DESCRIPTION
    - Remove cluster anterior 'monitoramento' se existir.
    - Cria cluster k3d multi-node com loadbalancer nas portas 80/443.
    - Cria o registry local junto com o cluster (--registry-create), conforme
      o padrao da documentacao k3d. O k3d configura automaticamente o
      registries.yaml em todos os nos — nenhum passo manual necessario.
    - Instala Traefik (ingress) via Helm.
    - Idempotente: pode ser reexecutado a qualquer momento para resetar o ambiente.

.NOTES
    Pré-requisito: Docker Desktop em execução, k3d, kubectl e helm no PATH.
    Execute após 02.verificar-instalacoes.ps1 confirmar tudo verde.
#>

$ErrorActionPreference = "Stop"

function Write-Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "`n    ERRO: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# 0. Pre-checks
# ---------------------------------------------------------------------------
Write-Step "Verificando pre-requisitos..."

@("docker", "k3d", "kubectl", "helm") | ForEach-Object {
    if (-not (Get-Command $_ -ErrorAction SilentlyContinue)) {
        Write-Fail "$_ nao encontrado. Instale antes de continuar."
    }
}

docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Docker Desktop nao esta rodando. Abra o Docker Desktop e tente novamente."
}

Write-Success "Todos os pre-requisitos encontrados."

# ---------------------------------------------------------------------------
# Hardware detection — calcula o budget recomendado para o Docker Desktop
# e as reservas do kubelet proporcionais ao hardware real da maquina.
# ---------------------------------------------------------------------------
$sysInfo     = Get-CimInstance Win32_ComputerSystem
$totalCpus   = [int]$sysInfo.NumberOfLogicalProcessors
$totalRamGb  = [math]::Floor($sysInfo.TotalPhysicalMemory / 1GB)

# Deixa 1 CPU e 2 GB para o sistema operacional (minimos absolutos)
$dockerCpus  = [math]::Max(2, $totalCpus - 1)
$dockerRamGb = [math]::Max(4, $totalRamGb - 2)

# system-reserved escala com a RAM total: mais RAM => mais folga para o OS
$sysReservedMem = switch ($true) {
    ($totalRamGb -ge 24) { '1024Mi'; break }
    ($totalRamGb -ge 12) { '512Mi';  break }
    default              { '256Mi' }
}

Write-Host ""
Write-Host "  Hardware detectado: $totalCpus CPUs  /  ${totalRamGb} GB RAM" -ForegroundColor Cyan
Write-Warn "Recomendado no Docker Desktop (Settings > Resources):"
Write-Warn "  CPUs   : $dockerCpus  (de $totalCpus)"
Write-Warn "  Memoria: ${dockerRamGb} GB  (de ${totalRamGb} GB)"

# ---------------------------------------------------------------------------
# 1. Limpar cluster anterior (se existir)
# ---------------------------------------------------------------------------
Write-Step "Verificando cluster existente..."

$existing = k3d cluster list -o json | ConvertFrom-Json | Where-Object { $_.name -eq "monitoramento" }
if ($existing) {
    Write-Host "    Cluster 'monitoramento' encontrado. Deletando..." -ForegroundColor Yellow
    k3d cluster delete monitoramento
    if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao deletar o cluster anterior." }
}

# ---------------------------------------------------------------------------
# 2. Criar cluster
# ---------------------------------------------------------------------------
Write-Step "Criando cluster k3d 'monitoramento'..."

k3d cluster create monitoramento `
    --port "80:80@loadbalancer" `
    --port "443:443@loadbalancer" `
    --port "4317:4317@loadbalancer" `
    --port "4318:4318@loadbalancer" `
    --port "5432:5432@loadbalancer" `
    --port "6379:6379@loadbalancer" `
    --port "27017:27017@loadbalancer" `
    --port "5672:5672@loadbalancer" `
    --agents 2 `
    --k3s-arg "--disable=traefik@server:0" `
    --k3s-arg "--kubelet-arg=system-reserved=cpu=100m,memory=${sysReservedMem}@server:0" `
    --k3s-arg "--kubelet-arg=kube-reserved=cpu=100m,memory=128Mi@server:0" `
    --k3s-arg "--kubelet-arg=eviction-hard=memory.available<300Mi@server:0" `
    --k3s-arg "--kubelet-arg=system-reserved=cpu=100m,memory=${sysReservedMem}@agent:*" `
    --k3s-arg "--kubelet-arg=kube-reserved=cpu=100m,memory=128Mi@agent:*" `
    --k3s-arg "--kubelet-arg=eviction-hard=memory.available<300Mi@agent:*" `
    --registry-create monitoramento-registry.localhost:0.0.0.0:5001 `
    --kubeconfig-update-default `
    --kubeconfig-switch-context `
    --wait

if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao criar o cluster." }
Write-Success "Cluster criado."

# ---------------------------------------------------------------------------
# 3. Corrigir kubeconfig
# ---------------------------------------------------------------------------
Write-Step "Corrigindo endpoint do kubeconfig..."

$currentServer = kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
if ($currentServer -match ':(\d+)$') {
    $apiPort = $Matches[1]
} else {
    Write-Fail "Nao foi possivel extrair a porta do API server. Server: $currentServer"
}

$newServer = "https://127.0.0.1:$apiPort"
kubectl config set-cluster k3d-monitoramento --server=$newServer

if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao corrigir o kubeconfig." }
Write-Success "Kubeconfig corrigido: $newServer"

# ---------------------------------------------------------------------------
# 4. Aguardar nodes ficarem prontos
# ---------------------------------------------------------------------------
Write-Step "Aguardando nodes ficarem prontos (timeout: 90s)..."

kubectl wait --for=condition=Ready nodes --all --timeout=90s

if ($LASTEXITCODE -ne 0) { Write-Fail "Nodes nao ficaram prontos a tempo." }
Write-Success "Todos os nodes prontos."

# ---------------------------------------------------------------------------
# 5. Instalar Traefik via Helm
# ---------------------------------------------------------------------------
Write-Step "Adicionando repo do Traefik..."

helm repo add traefik https://traefik.github.io/charts | Out-Null
helm repo update | Out-Null

Write-Step "Instalando Traefik..."

helm upgrade --install traefik traefik/traefik `
    --namespace traefik `
    --create-namespace `
    --set deployment.replicas=1 `
    --set ports.web.hostPort=80 `
    --set ports.websecure.hostPort=443 `
    --set providers.kubernetesCRD.enabled=true `
    --set providers.kubernetesCRD.allowCrossNamespace=true `
    --set providers.kubernetesIngress.enabled=true `
    --set service.type=ClusterIP `
    --set "ports.otlpgrpc.port=4317" `
    --set "ports.otlpgrpc.hostPort=4317" `
    --set "ports.otlpgrpc.expose.default=true" `
    --set "ports.otlpgrpc.exposedPort=4317" `
    --set "ports.otlphttp.port=4318" `
    --set "ports.otlphttp.hostPort=4318" `
    --set "ports.otlphttp.expose.default=true" `
    --set "ports.otlphttp.exposedPort=4318" `
    --set "ports.postgres.port=5432" `
    --set "ports.postgres.hostPort=5432" `
    --set "ports.postgres.expose.default=true" `
    --set "ports.postgres.exposedPort=5432" `
    --set "ports.redis.port=6379" `
    --set "ports.redis.hostPort=6379" `
    --set "ports.redis.expose.default=true" `
    --set "ports.redis.exposedPort=6379" `
    --set "ports.mongodb.port=27017" `
    --set "ports.mongodb.hostPort=27017" `
    --set "ports.mongodb.expose.default=true" `
    --set "ports.mongodb.exposedPort=27017" `
    --set "ports.amqp.port=5672" `
    --set "ports.amqp.hostPort=5672" `
    --set "ports.amqp.expose.default=true" `
    --set "ports.amqp.exposedPort=5672" `
    --wait `
    --timeout 120s

if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao instalar o Traefik." }
Write-Success "Traefik instalado."

# ---------------------------------------------------------------------------
# 6. Verificação final do cluster
# ---------------------------------------------------------------------------
Write-Step "Verificando cluster..."

kubectl get nodes
Write-Host ""
kubectl get pods -n traefik

# ---------------------------------------------------------------------------
# 7. Resumo final
# ---------------------------------------------------------------------------
$nodeCount = @(kubectl get nodes --no-headers).Count

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " Cluster pronto para o laboratorio!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Nodes:        $nodeCount node(s) prontos"
Write-Host "API Server:   $newServer"
Write-Host "Traefik:      http://localhost  (porta 80)"
Write-Host "              https://localhost (porta 443)"
Write-Host "              otlp-grpc         (porta 4317)"
Write-Host "              otlp-http         (porta 4318)"
Write-Host "              postgres          (porta 5432)"
Write-Host "              redis             (porta 6379)"
Write-Host "              mongodb           (porta 27017)"
Write-Host "              amqp              (porta 5672)"
Write-Host ""
Write-Host "Reservas por node (kubelet):"
Write-Host "  system-reserved : cpu=100m, memory=$sysReservedMem"
Write-Host "  kube-reserved   : cpu=100m, memory=128Mi"
Write-Host "  eviction-hard   : memory.available < 300Mi"
Write-Host ""
Write-Host "Registry local:"
Write-Host "  Push do host    : localhost:5001"
Write-Host "  Dentro dos pods : monitoramento-registry.localhost:5001"
Write-Host "  Sem autenticacao. Sem alteracao no daemon.json."
Write-Host ""
Write-Host "Proximo passo:"
Write-Host "  kubectl apply -f scripts/teste.yaml"
Write-Host ""
Write-Host "Para resetar o cluster a qualquer momento:"
Write-Host "  .\03.criar-cluster-k3d.ps1"
Write-Host ""