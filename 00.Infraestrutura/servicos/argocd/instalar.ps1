#Requires -Version 7.0
<#
.SYNOPSIS
    Instala o ArgoCD no cluster monitoramento (k3d + Traefik).
.DESCRIPTION
    O servidor roda em modo --insecure para que o Traefik realize a terminacao
    HTTP no Ingress padrao. Um Ingress networking.k8s.io/v1 e criado ao final
    expondo a UI em http://argocd.monitoramento.local.
.NOTES
    Prereqs : cluster monitoramento em execucao (03.criar-cluster-k3d.ps1)
    Proximo : adicionar entrada no hosts via 09.atualizar-hosts.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ValuesFile  = Join-Path $PSScriptRoot 'values.yaml'
$ArgoCdNs    = 'argocd'
$ArgoCdHost  = 'argocd.monitoramento.local'

# ── 0. Pre-checks ─────────────────────────────────────────────────────────────
Write-Host "`n[0/5] Verificando pre-requisitos..." -ForegroundColor Cyan

foreach ($cmd in @('kubectl', 'helm')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "'$cmd' nao encontrado no PATH. Instale antes de continuar."
        exit 1
    }
}

kubectl cluster-info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "kubectl nao consegue conectar ao cluster. Execute 03.criar-cluster-k3d.ps1 primeiro."
    exit 1
}

Write-Host "    OK: kubectl, helm encontrados e cluster acessivel." -ForegroundColor Green

# ── 1. Namespace ──────────────────────────────────────────────────────────────
Write-Host "`n[1/5] Criando namespace ${ArgoCdNs}..." -ForegroundColor Cyan
kubectl create namespace $ArgoCdNs --dry-run=client -o yaml | kubectl apply -f -

# ── 2. Helm repo ──────────────────────────────────────────────────────────────
Write-Host "`n[2/5] Adicionando repositorio Helm do ArgoCD..." -ForegroundColor Cyan
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# ── 3. Instalar ArgoCD ────────────────────────────────────────────────────────
Write-Host "`n[3/5] Instalando ArgoCD via Helm..." -ForegroundColor Cyan

helm upgrade --install argocd argo/argo-cd `
    --namespace $ArgoCdNs `
    --values $ValuesFile `
    --wait `
    --timeout 5m

if ($LASTEXITCODE -ne 0) {
    Write-Error "Falha ao instalar o ArgoCD."
    exit 1
}
Write-Host "    OK: ArgoCD instalado." -ForegroundColor Green

# ── 4. Ingress (Traefik) ──────────────────────────────────────────────────────
Write-Host "`n[4/5] Criando Ingress para o ArgoCD UI..." -ForegroundColor Cyan

$IngressYaml = @"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: $ArgoCdNs
  labels:
    app: argocd
    version: "1.0.0"
spec:
  ingressClassName: traefik
  rules:
    - host: $ArgoCdHost
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
"@

$IngressYaml | kubectl apply -f -

if ($LASTEXITCODE -ne 0) {
    Write-Error "Falha ao criar o Ingress."
    exit 1
}
Write-Host "    OK: Ingress criado." -ForegroundColor Green

# ── 5. Aguardar pods prontos ───────────────────────────────────────────────────
Write-Host "`n[5/5] Aguardando pods do ArgoCD ficarem prontos (timeout: 2m)..." -ForegroundColor Cyan
kubectl wait --for=condition=Ready pods --all -n $ArgoCdNs --timeout=120s

if ($LASTEXITCODE -ne 0) {
    Write-Error "Pods nao ficaram prontos a tempo. Verifique: kubectl get pods -n $ArgoCdNs"
    exit 1
}

# ── Senha inicial do admin ─────────────────────────────────────────────────────
try {
    $EncodedPassword = kubectl -n $ArgoCdNs get secret argocd-initial-admin-secret `
        -o jsonpath='{.data.password}'
    $InitialPassword = [System.Text.Encoding]::UTF8.GetString(
        [System.Convert]::FromBase64String($EncodedPassword)
    )
} catch {
    $InitialPassword = '<nao disponivel>'
}

# ── Resumo ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " ArgoCD instalado com sucesso!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host " Adicione a entrada abaixo no arquivo" -NoNewline
Write-Host " C:\Windows\System32\drivers\etc\hosts" -ForegroundColor White
Write-Host " (ou execute 09.atualizar-hosts.ps1):"
Write-Host ""
Write-Host "   127.0.0.1   $ArgoCdHost" -ForegroundColor White
Write-Host ""
Write-Host " Acesso via browser:" -ForegroundColor Cyan
Write-Host "   ArgoCD UI  http://$ArgoCdHost" -ForegroundColor Cyan
Write-Host ""
Write-Host " Credenciais iniciais:"
Write-Host "   Usuario : admin" -ForegroundColor White
Write-Host "   Senha   : $InitialPassword" -ForegroundColor White
Write-Host ""
Write-Host "AVISO: Altere a senha inicial apos o primeiro acesso:" -ForegroundColor Yellow
Write-Host "   argocd login $ArgoCdHost --username admin --password '$InitialPassword' --insecure" -ForegroundColor Yellow
Write-Host "   argocd account update-password" -ForegroundColor Yellow
Write-Host ""
