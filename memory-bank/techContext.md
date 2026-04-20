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
| Tempo                               | `tempo` (grafana)                              | `05.03-tempo.yaml`                                                          |
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

| App              | Framework                       | Location                    | Observability             |
| ---------------- | ------------------------------- | --------------------------- | ------------------------- |
| MonitoringDotNet | ASP.NET Core 10, EF Core, Redis | `01.apps/MonitoringDotNet/` | OpenTelemetry SDK → Alloy |
| nuxt-workshop    | Nuxt 3, Prisma                  | `05.helm-chart/app/`        | OpenTelemetry SDK → Alloy |

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
| RavenDB       | `<name>-ravendb.k3d.localhost`  |
| nuxt-workshop | `nuxt-workshop.local`           |

## Credentials

| Service | Username | Password      |
| ------- | -------- | ------------- |
| Grafana | `admin`  | `workshop123` |

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
