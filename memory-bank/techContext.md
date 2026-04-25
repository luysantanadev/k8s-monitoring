# Tech Context — k8s-monitoring

## Runtime & Orchestration

| Tool             | Version/Notes                             |
| ---------------- | ----------------------------------------- |
| Docker           | Required — runs k3d containers            |
| k3d              | v5.x — `k3d cluster create monitoramento` |
| kubectl          | Matches cluster version                   |
| Helm             | v3.x — used for all chart installs        |
| k3s (inside k3d) | Kubernetes 1.30+                          |

## Observability Stack (all in `monitoring` namespace)

| Component                           | Helm Chart                                     | Values File                                                                 |
| ----------------------------------- | ---------------------------------------------- | --------------------------------------------------------------------------- |
| Grafana + Prometheus + Alertmanager | `kube-prometheus-stack` (prometheus-community) | `00.Infraestrutura/servicos/grafana/yamls/05.01-kube-prometheus-stack.yaml` |
| Loki                                | `loki` (grafana)                               | `05.02-loki.yaml`                                                           |
| Tempo                               | `tempo` (grafana)                              | `05.03-tempo.yaml` — metrics-generator + spanMetrics + serviceGraphs habilitados (REVISION 3) |
| Pyroscope                           | `pyroscope` (grafana)                          | `05.04-pyroscope.yaml`                                                      |
| Alloy                               | `alloy` (grafana)                              | `05.05-alloy.yaml`                                                          |
| Grafana datasources                 | `grafana-datasource` (ConfigMap)               | `05.06-grafana-datasource.yaml`                                             |
| Ingresses                           | raw YAML                                       | `05.07-ingresses.yaml`                                                      |

## Data Services

| Service           | Install Method         | Namespace | External Port           |
| ----------------- | ---------------------- | --------- | ----------------------- |
| PostgreSQL        | CloudNativePG operator | `default` | 5432 (IngressRouteTCP)  |
| Redis             | Bitnami Helm chart     | `default` | 6379 (IngressRouteTCP)  |
| MongoDB Community | Percona Helm chart     | `default` | 27017 (IngressRouteTCP) |
| RavenDB           | Helm chart             | `default` | Ingress HTTP            |
| RabbitMQ          | Bitnami Helm chart     | `default` | —                       |
| Keycloak          | Bitnami Helm chart     | `default` | —                       |
| Vault             | HashiCorp Helm chart   | `default` | —                       |
| SonarQube         | Bitnami Helm chart     | `default` | —                       |

## Demo Applications

| App              | Framework                          | Location                          | Observability                        |
| ---------------- | ---------------------------------- | --------------------------------- | ------------------------------------ |
| MonitoringDotNet | ASP.NET Core 10 MVC, EF Core, Redis | `01.apps/MonitoringDotNet/src/Mvc/` | Serilog→Loki + OpenTelemetry SDK→Alloy |
| nuxt-workshop    | Nuxt 3, Prisma                     | `05.helm-chart/app/`              | OpenTelemetry SDK → Alloy            |

## OTLP Endpoints

| Protocol           | Address                                   |
| ------------------ | ----------------------------------------- |
| OTLP gRPC          | `alloy.monitoring.svc.cluster.local:4317` |
| OTLP HTTP          | `alloy.monitoring.svc.cluster.local:4318` |
| External OTLP gRPC | `localhost:4317` (via k3d LoadBalancer)   |
| External OTLP HTTP | `localhost:4318` (via k3d LoadBalancer)   |

## Ingress Hostnames (add to /etc/hosts → run script 09)

| Service       | Hostname                        |
| ------------- | ------------------------------- |
| Grafana       | `grafana.monitoramento.local`   |
| Loki          | `loki.monitoramento.local`      |
| Tempo         | `tempo.monitoramento.local`     |
| Pyroscope     | `pyroscope.monitoramento.local` |
| Alloy         | `alloy.monitoramento.local`     |
| ArgoCD        | `argocd.monitoramento.local`    |
| RavenDB       | `<name>-ravendb.k3d.localhost`  |
| nuxt-workshop | `nuxt-workshop.local`           |

## Credentials

| Service | Username | Password                                            |
| ------- | -------- | --------------------------------------------------- |
| Grafana | `admin`  | `workshop123`                                       |
| ArgoCD  | `admin`  | `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` |

## Development Tools

| Tool       | Purpose                                                |
| ---------- | ------------------------------------------------------ |
| winget     | Windows package manager for installs (script 01)       |
| apt / brew | Linux/macOS package manager                            |
| rtk        | Token-optimized CLI proxy — prefix commands with `rtk` |

## Repository Registry

- Push local Docker images to: `monitoramento-registry.localhost:5001/<image>:<tag>`
- Pull from cluster: same address

## Cross-Platform Rule

Every script has two versions:

- `00.Infraestrutura/windows/*.ps1` — PowerShell (winget, Windows paths)
- `00.Infraestrutura/linux/*.sh` — Bash (apt/brew, POSIX paths)
  Both must maintain identical behavior.

## Loki Sink — Gotchas Conhecidos

| Item | Detalhe |
|------|---------|
| **Biblioteca** | `Serilog.Sinks.Grafana.Loki` v8.x |
| **Stream label** | NÃO cria `level`. Loki auto-detecta `detected_level` a partir do campo `"level"` no JSON |
| **Valores de nível** | `debug`, `info`, `warn`, `error`, `fatal` — NÃO `information` nem `warning` |
| **Tenant** | `auth_enabled: false` mas gateway exige `X-Scope-OrgID: workshop`. Usar `WorkshopLokiHttpClient` |
| **`WorkshopLokiHttpClient`** | Implementa `ILokiHttpClient`; adiciona header no construtor; localizado em `ObservabilityExtensions.cs` |
| **`.env` local** | `DotNetEnv` → `Env.TraversePath().Load()` em `src/Mvc/` — arquivo DEVE existir |

## MonitoringDotNet — Service Identifiers

| Chave | Valor atual |
|-------|-------------|
| `Observability:ServiceName` | `monitoring-dotnet-mvc` |
| Loki stream label `app` | `monitoring-dotnet-mvc` |
| Dashboard UID | `monitoring-dotnet-mvc-v1` |
| Dashboard file | `grafana/dashboards/monitoring-dotnet-mvc.json` |

## MonitoringDotNet — Pyroscope Native CLR Profiler

> **CRÍTICO**: o CLR profiler lê vars de ambiente ANTES do código gerenciado (.NET) iniciar. `Environment.SetEnvironmentVariable()` em `Program.cs` chega tarde demais — o profiler já foi configurado (ou não).

| Variável | Onde definida | Valor / Detalhe |
|----------|---------------|-----------------|
| `CORECLR_ENABLE_PROFILING` | `Dockerfile ENV` | `1` |
| `CORECLR_PROFILER` | `Dockerfile ENV` | `{BD1A650D-AC5D-4896-B64F-D6FA25D6B26A}` |
| `CORECLR_PROFILER_PATH` | `Dockerfile ENV` | `/dotnet/Pyroscope.Profiler.Native.so` |
| `LD_PRELOAD` | `Dockerfile ENV` | `/dotnet/Pyroscope.Linux.ApiWrapper.x64.so` |
| `LD_LIBRARY_PATH` | `Dockerfile ENV` | `/dotnet` |
| `DOTNET_EnableDiagnostics` | `Dockerfile ENV` | `1` (necessário no .NET 8+; `=0` desativa o profiler) |
| `DOTNET_EnableDiagnostics_IPC` | `Dockerfile ENV` | `0` (desativa socket IPC — segurança) |
| `DOTNET_EnableDiagnostics_Debugger` | `Dockerfile ENV` | `0` |
| `DOTNET_EnableDiagnostics_Profiler` | `Dockerfile ENV` | `1` |
| `PYROSCOPE_PROFILING_LOG_DIR` | `Dockerfile ENV` | `/tmp/pyroscope` (writable por non-root) |
| `PYROSCOPE_APPLICATION_NAME` | `helm/values.yaml` configMap | `monitoring-dotnet-mvc` |
| `PYROSCOPE_SERVER_ADDRESS` | `helm/values.yaml` configMap | `http://pyroscope.monitoring.svc.cluster.local:4040` |
| `PYROSCOPE_PROFILING_ENABLED` | `helm/values.yaml` configMap | `1` (ausente no Dockerfile — default `false`; habilitado via ConfigMap) |
| `PYROSCOPE_PROFILING_CPU_ENABLED` | `helm/values.yaml` configMap | `true` |
| Demais `PYROSCOPE_PROFILING_*` | `helm/values.yaml` configMap | `walltime`, `allocation`, `lock`, `exception`, `heap` = `true` |

Fonte `.so`: `pyroscope/pyroscope-dotnet:0.14.5-musl` → copiado para `/dotnet/` no Dockerfile.
