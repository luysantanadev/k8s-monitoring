# Active Context — k8s-monitoring

> **Update this file at the START and END of every session.**
> It is the first file read to resume work. Keep it focused on the present.

## Current Focus

Executar os scripts ArgoCD no cluster e validar os pods; depois rebuild + deploy do MonitoringDotNet e validação E2E dos 4 sinais (logs, métricas, traces, profiling).

## Recent Changes

- **2026-04-25** *(esta sessão)*: ArgoCD scripts completados — `instalar.sh` (Linux) criado do zero, `instalar.ps1` (PowerShell) preenchido (estava vazio), `values.yaml` criado. Paridade total Windows/Linux. Scripts prontos mas **ainda não executados** contra o cluster.
- **2026-04-25**: Pyroscope .NET SDK corrigido — `CORECLR_*`, `LD_PRELOAD`, `DOTNET_EnableDiagnostics_*` adicionados ao `Dockerfile`; `PYROSCOPE_*` movidos para ConfigMap. `SetEnvironmentVariable()` runtime removido.
- **2026-04-25**: Dashboard MonitoringDotNet bumped → v9 (Panel 80 Trace Explorer corrigido; datasource UIDs corrigidos).

## Next Steps

- [ ] **Instalar ArgoCD**: `bash 00.Infraestrutura/servicos/argocd/instalar.sh` (Linux) ou `.\instalar.ps1` (Windows); confirmar `kubectl get pods -n argocd` todos `Running`
- [ ] **Adicionar hostname**: confirmar que `argocd.monitoramento.local` está no script `09.atualizar-hosts`; executá-lo
- [ ] **Rebuild e push da imagem**: `docker build`, tag `0.1.0`, push para `monitoramento-registry.localhost:5001/dotnet/mvc`
- [ ] **Re-importar dashboard v9** no Grafana (`grafana.monitoramento.local` → Import → `monitoring-dotnet-mvc.json`)
- [ ] **Validar E2E completo**: logs `detected_level`, métricas RED, traces panel 80, profiling Pyroscope

## Active Decisions

- CLR profiler lê env vars antes do código gerenciado — configuração Pyroscope DEVE ser via `ENV` no Dockerfile ou ConfigMap, nunca via `Environment.SetEnvironmentVariable()` em runtime
- ArgoCD usa modo `--insecure` porque Traefik faz HTTP termination — não usar TLS interno
- Panel `type:"table"` + `queryType:"traceql"` + `tableType:"traces"` é o formato correto para Grafana 12.4.3
- UIDs de datasource hardcoded: `prometheus`, `loki`, `tempo`, `pyroscope`

## Blockers / Open Questions

- [ ] ArgoCD — scripts criados mas não executados; pods ainda não verificados
- [ ] Imagem MonitoringDotNet ainda não rebuilt após correção do Pyroscope
- [ ] Dashboard v9 ainda não re-importado no Grafana

## Active Decisions

- CLR profiler lê env vars antes do código gerenciado — configuração Pyroscope DEVE ser via `ENV` no Dockerfile ou ConfigMap, nunca via `Environment.SetEnvironmentVariable()` em runtime
- ArgoCD usa modo `--insecure` porque Traefik faz HTTP termination — não usar TLS interno
- Panel `type:"table"` + `queryType:"traceql"` + `tableType:"traces"` é o formato correto para Grafana 12.4.3
- UIDs de datasource hardcoded: `prometheus`, `loki`, `tempo`, `pyroscope`

## Blockers / Open Questions

- [ ] ArgoCD — confirmar se `instalar.ps1`/`.sh` foi executado com sucesso (status dos pods)
- [ ] Imagem MonitoringDotNet ainda não rebuilt após correção do Pyroscope
- [ ] Dashboard v9 ainda não re-importado no Grafana
