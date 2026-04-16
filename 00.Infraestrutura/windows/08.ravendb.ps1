#Requires -Version 7.0
<#
.SYNOPSIS
    Gerencia instancias RavenDB via Helm no cluster k3d.

.DESCRIPTION
    - Adiciona o repositorio ravendb (github.com/ravendb/helm-charts) e atualiza (idempotente).
    - Modo interativo: cria ou remove instancias RavenDB standalone.
      Criacao: solicita namespace e nome da instancia, faz deploy via Helm em modo
               nao-seguro (workshop), cria Ingress Traefik HTTP para
               <nome>-ravendb.k3d.localhost e exibe informacoes de acesso.
      Remocao: lista instancias existentes por numero e remove a selecionada.

.EXAMPLE
    .\08.ravendb.ps1
    Executa o assistente interativo de gerenciamento de instancias RavenDB.

.NOTES
    Pre-requisito: cluster k3d 'monitoramento' em execucao (03.criar-cluster-k3d.ps1),
    kubectl e helm no PATH.
    Chart utilizado: ravendb/ravendb-cluster (https://github.com/ravendb/helm-charts).
    Porta HTTP : 8080  (Management Studio + REST API)
    Modo       : nao-seguro (UnsecuredAccessAllowed=PublicNetwork) — apenas para workshop/dev.
    Ingress    : <nome>-ravendb.k3d.localhost via Traefik (porta 80).
    Adicionar ao hosts: 127.0.0.1  <nome>-ravendb.k3d.localhost
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step($msg)    { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg)    { Write-Host "    AVISO: $msg" -ForegroundColor Yellow }
function Write-Fail($msg)    { Write-Host "`n    ERRO: $msg" -ForegroundColor Red; exit 1 }

# Retorna todas as instancias RavenDB instaladas via Helm (chart ravendb-cluster).
function Get-AllRavenInstances {
    $raw = helm list -A -o json 2>&1
    if ($LASTEXITCODE -ne 0 -or -not $raw) { return @() }
    try {
        $json = $raw | ConvertFrom-Json
        if (-not $json -or $json.Count -eq 0) { return @() }
        return @($json | Where-Object { $_.chart -like 'ravendb-cluster-*' } | ForEach-Object {
            [PSCustomObject]@{
                Namespace = $_.namespace
                Release   = $_.name
            }
        })
    } catch {
        return @()
    }
}

# ---------------------------------------------------------------------------
# 1. Repositorio Helm (idempotente)
# ---------------------------------------------------------------------------
Write-Step "Configurando repositorio ravendb/helm-charts..."

helm repo add ravendb https://ravendb.github.io/helm-charts 2>&1 | Out-Null
helm repo update 2>&1 | Out-Null

Write-Success "Repositorio ravendb atualizado."

# ---------------------------------------------------------------------------
# 2. Menu principal
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  O que deseja fazer?" -ForegroundColor Cyan
Write-Host "    [1] Criar instancia RavenDB"
Write-Host "    [2] Remover instancia RavenDB"
Write-Host ""

do {
    $action = (Read-Host "  Opcao").Trim()
} while ($action -notin @('1', '2'))

# ===========================================================================
# CRIAR INSTANCIA
# ===========================================================================
if ($action -eq '1') {

    # --- Namespace ---
    Write-Host ""
    $Namespace = ''
    do {
        $Namespace = (Read-Host "  Namespace").Trim()
    } while (-not $Namespace)

    kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f - | Out-Null
    Write-Success "Namespace '$Namespace' pronto."

    # --- Nome da instancia (unico no namespace) ---
    $allInstances = Get-AllRavenInstances
    $InstanceName = ''
    do {
        $inputName = (Read-Host "  Nome da instancia RavenDB").Trim().ToLower()
        if (-not $inputName) { continue }

        $alreadyExists = $allInstances | Where-Object {
            $_.Namespace -eq $Namespace -and $_.Release -eq $inputName
        }
        if ($alreadyExists) {
            Write-Warn "Ja existe uma instancia '$inputName' no namespace '$Namespace'. Escolha outro nome."
            continue
        }
        $InstanceName = $inputName
    } while (-not $InstanceName)

    # --- Licenca RavenDB ---
    # O chart faz b64enc do campo license; se o valor for nil (nao declarado) o Helm falha.
    # O usuario deve colar o JSON da licenca (obtido em ravendb.net/buy).
    Write-Host ""
    Write-Host "  Cole o JSON da licenca RavenDB e pressione ENTER duas vezes." -ForegroundColor Cyan
    Write-Host "  (Licenca gratuita Developer: https://ravendb.net/buy)" -ForegroundColor Gray
    Write-Host ""

    $licenseLines = [System.Collections.Generic.List[string]]::new()
    do {
        $line = Read-Host "  Licenca"
        if ($line) { $licenseLines.Add($line) }
    } while ($line)

    $License = ($licenseLines -join '').Trim()

    if (-not $License) {
        Write-Warn "Nenhuma licenca informada. O deploy pode falhar ou o Studio ficara em modo limitado."
        $License = ""
    }

    # --- Arquivo de valores Helm temporario ---
    # O JSON da licenca contem aspas e chaves que quebram strings YAML inline.
    # Solucao: bloco literal YAML (indicador '|') + arquivo temporario em vez de stdin.
    # O bloco literal preserva o conteudo exatamente como digitado, sem necessidade de escape.
    $tmpValues = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.yaml'
    try {
        @"
nodesCount: 1

ravendb:
  license: |
    $License
  settings:
    "Security.UnsecuredAccessAllowed": "PublicNetwork"
    "Setup.Mode": "None"

resources:
  requests:
    cpu: 200m
    memory: 512Mi
  limits:
    cpu: "1"
    memory: 1Gi

storage:
  size: 2Gi
"@ | Set-Content $tmpValues -Encoding UTF8

    # --- Deploy via Helm ---
    Write-Step "Fazendo deploy do RavenDB '$InstanceName' no namespace '$Namespace'..."

    helm upgrade --install $InstanceName ravendb/ravendb-cluster `
        --namespace $Namespace `
        --create-namespace `
        --values $tmpValues

    if ($LASTEXITCODE -ne 0) { Write-Fail "Helm install falhou. Verifique os logs acima." }
    } finally {
        Remove-Item $tmpValues -ErrorAction SilentlyContinue
    }
    Write-Success "RavenDB '$InstanceName' implantado."

    # --- Ingress HTTP (Traefik) ---
    # RavenDB e HTTP-nativo (porta 8080), entao usa Ingress padrao em vez de IngressRouteTCP.
    # Isso permite multiplas instancias coexistindo no mesmo host :80 via host-header routing.
    $IngressHost = "$InstanceName-ravendb.k3d.localhost"

    Write-Step "Criando Ingress Traefik para '$IngressHost'..."

    $ingress = @"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ravendb-$InstanceName
  namespace: $Namespace
  labels:
    app: $InstanceName
    managed-by: 08.ravendb
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
spec:
  ingressClassName: traefik
  rules:
    - host: $IngressHost
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ${InstanceName}-ravendb-cluster
                port:
                  number: 8080
"@

    $ingress | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { Write-Warn "Ingress nao aplicado. RavenDB acessivel via port-forward." }
    else { Write-Success "Ingress criado para http://$IngressHost." }

    # --- ServiceMonitor (Prometheus) ---
    # RavenDB expoe metricas Prometheus nativamente em /metrics na mesma porta HTTP (8080).
    Write-Step "Criando ServiceMonitor para RavenDB '$InstanceName'..."
    $smRaven = @"
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ravendb-$InstanceName
  namespace: $Namespace
  labels:
    app: $InstanceName
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/instance: $InstanceName
  endpoints:
    - port: http
      interval: 30s
      path: /metrics
"@
    $smRaven | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { Write-Warn "ServiceMonitor nao aplicado. Metricas do RavenDB nao serao coletadas." }
    else { Write-Success "ServiceMonitor criado. Metricas disponiveis no Grafana." }

    # --- Resumo ---
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  Instancia RavenDB criada com sucesso!" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Namespace : $Namespace"
    Write-Host "  Instancia : $InstanceName"
    Write-Host "  Modo      : Nao-seguro (workshop/dev)"
    Write-Host ""
    Write-Host "  Aguardar o pod ficar pronto:" -ForegroundColor Yellow
    Write-Host "    kubectl -n $Namespace get pods -l app.kubernetes.io/instance=$InstanceName -w"
    Write-Host ""
    Write-Host "  Adicionar ao C:\Windows\System32\drivers\etc\hosts:" -ForegroundColor Yellow
    Write-Host "    127.0.0.1  $IngressHost"
    Write-Host ""
    Write-Host "  Management Studio (navegador):" -ForegroundColor Yellow
    Write-Host "    http://$IngressHost"
    Write-Host ""
    Write-Host "  URL de conexao (cliente .NET / HTTP):" -ForegroundColor Yellow
    Write-Host "    http://$IngressHost"
    Write-Host ""
    Write-Host "  URL interna (dentro do cluster):" -ForegroundColor Yellow
    Write-Host "    http://${InstanceName}-ravendb-cluster.${Namespace}.svc.cluster.local:8080"
    Write-Host ""
    Write-Warn "Modo nao-seguro: use apenas para desenvolvimento/workshop."
    Write-Host ""
    Write-Host "  Licenca gratuita (Community/Developer):" -ForegroundColor Yellow
    Write-Host "    https://ravendb.net/buy  →  'Developer' (gratuito)"
    Write-Host "    Cole a licenca no Management Studio em: About > Register"
    Write-Host ""
}

# ===========================================================================
# REMOVER INSTANCIA
# ===========================================================================
if ($action -eq '2') {

    $instances = @(Get-AllRavenInstances)

    if ($instances.Count -eq 0) {
        Write-Host ""
        Write-Warn "Nenhuma instancia RavenDB encontrada no cluster."
        exit 0
    }

    Write-Host ""
    Write-Host "  Instancias RavenDB existentes:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $instances.Count; $i++) {
        Write-Host "    [$($i + 1)]  $($instances[$i].Namespace) / $($instances[$i].Release)"
    }
    Write-Host ""

    $max = $instances.Count
    do {
        $sel = (Read-Host "  Numero da instancia a remover (1-$max)").Trim()
    } while ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $max)

    $chosen  = $instances[[int]$sel - 1]
    $ns      = $chosen.Namespace
    $name    = $chosen.Release

    Write-Step "Removendo instancia RavenDB '$name' do namespace '$ns'..."

    helm uninstall $name --namespace $ns
    if ($LASTEXITCODE -ne 0) { Write-Fail "Falha ao remover o release Helm '$name'." }

    kubectl -n $ns delete ingress "ravendb-$name" --ignore-not-found | Out-Null
    kubectl -n $ns delete servicemonitor "ravendb-$name" --ignore-not-found | Out-Null

    # O chart nao remove PVCs automaticamente para evitar perda acidental de dados.
    Write-Warn "PVC do RavenDB pode ter ficado para tras. Para remover:"
    Write-Warn "  kubectl -n $ns delete pvc -l app.kubernetes.io/instance=$name"

    Write-Success "Instancia RavenDB '$name' removida do namespace '$ns'."
    Write-Host ""
}
