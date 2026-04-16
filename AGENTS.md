# k8s-monitoring — Agent Instructions

This project builds a full **Kubernetes observability platform** running on k3d (Kubernetes in Docker) with cross-platform support for **Windows (PowerShell)** and **Linux (Bash)**. The stack covers metrics, logs, traces and continuous profiling, deployed via Helm, with GitHub Actions as CI/CD. Content is produced for the YouTube channel [@luysantanadev](https://www.youtube.com/@luysantanadev).

---

## Project Layout

```
00.Infraestrutura/   # Setup automation (windows/ + linux/ + yamls/)
01.docker-images/    # Static nginx image (workshop-nginx)
02.docker-envs/      # Node.js client+server Docker example
03.docker-compose/   # Local docker-compose reference env
04.fundamentos-kubernetes/  # Educational raw manifests (01→05)
05.helm-chart/       # Production app: nuxt-workshop (app/ + helm/)
06.explorando/       # Scratch / exploration scripts
```

See [`00.Infraestrutura/yamls/`](00.Infraestrutura/yamls/) for every Helm values override used in the monitoring stack.

---

## Environment Setup

Run scripts **in order**. Every script is idempotent — re-running is safe.

### Windows

```powershell
.\00.Infraestrutura\windows\01.instalar-dependencias.ps1         # winget: k3d, kubectl, helm
.\00.Infraestrutura\windows\02.verificar-instalacoes.ps1         # sanity check
.\00.Infraestrutura\windows\03.criar-cluster-k3d.ps1             # cluster + Traefik
.\00.Infraestrutura\windows\04.configurar-monitoramento.ps1      # stack completo de observabilidade
.\00.Infraestrutura\windows\05.configurar-cnpg-criar-base-pgsql.ps1  # PostgreSQL via CloudNativePG
.\00.Infraestrutura\windows\06.configurar-redis.ps1              # Redis + ServiceMonitor
.\00.Infraestrutura\windows\07.configurar-mongodb.ps1            # MongoDB Community + ServiceMonitor
.\00.Infraestrutura\windows\08.configurar-ravendb.ps1            # RavenDB + Ingress
.\00.Infraestrutura\windows\09.atualizar-hosts.ps1               # /etc/hosts automático
```

### Linux

```bash
bash 00.Infraestrutura/linux/01.instalar-dependencias.sh
bash 00.Infraestrutura/linux/02.verificar-instalacoes.sh
bash 00.Infraestrutura/linux/03.criar-cluster-k3d.sh
bash 00.Infraestrutura/linux/04.configurar-monitoramento.sh
bash 00.Infraestrutura/linux/05.configurar-cnpg-criar-base-pgsql.sh
bash 00.Infraestrutura/linux/06.configurar-redis.sh
bash 00.Infraestrutura/linux/07.configurar-mongodb.sh
bash 00.Infraestrutura/linux/08.configurar-ravendb.sh
bash 00.Infraestrutura/linux/09.atualizar-hosts.sh
```

### k3d Cluster Specs

- **Name**: `monitoramento`
- **Agents**: 2 worker nodes
- **Ports expostos no LoadBalancer**: 80, 443, 4317 (OTLP gRPC), 4318 (OTLP HTTP), 5432 (PostgreSQL), 6379 (Redis), 27017 (MongoDB)
- **Registry**: `monitoramento-registry.localhost:5001` (push local images here)
- **Ingress**: Traefik (instalado via Helm com entrypoints customizados para cada porta TCP)

---

## Monitoring Stack

| Component | Namespace | Acesso |
|-----------|-----------|--------|
| Grafana (kube-prometheus-stack) | `monitoring` | `grafana.monitoramento.local`, senha: `workshop123` |
| Prometheus | `monitoring` | Interno |
| Loki | `monitoring` | `loki.monitoramento.local` — datasource no Grafana |
| Tempo | `monitoring` | `tempo.monitoramento.local` — OTLP gRPC `4317`, HTTP `4318` |
| Pyroscope | `monitoring` | `pyroscope.monitoramento.local` — datasource no Grafana |
| Alloy (OTel collector) | `monitoring` | `alloy.monitoring.svc.cluster.local:4318` |

**Observability flow**: App → OpenTelemetry SDK → Alloy → {Loki, Tempo, Pyroscope} ← Grafana

Helmvalues de cada componente em [`00.Infraestrutura/yamls/`](00.Infraestrutura/yamls/).

## Bancos de Dados

| Banco | Namespace | Porta Externa | Ingress |
|-------|-----------|---------------|---------|
| PostgreSQL (CloudNativePG) | `default` | `5432` (IngressRouteTCP) | — |
| Redis (Bitnami) | `default` | `6379` (IngressRouteTCP) | — |
| MongoDB Community | `default` | `27017` (IngressRouteTCP) | — |
| RavenDB | `default` | — | `<nome>-ravendb.k3d.localhost` |

Cada banco é instalado com `ServiceMonitor` (`release: kube-prometheus-stack`) para scrape automático pelo Prometheus.

---

## Helm Chart (nuxt-workshop)

- Chart: [`05.helm-chart/helm/`](05.helm-chart/helm/)
- App source: [`05.helm-chart/app/`](05.helm-chart/app/) (Nuxt 3 + Prisma + OpenTelemetry)
- Image: `monitoramento-registry.localhost:5001/nuxt-workshop:<tag>`

Key values — see [`05.helm-chart/helm/values.yaml`](05.helm-chart/helm/values.yaml):
- `configMap.data.OTEL_EXPORTER_OTLP_ENDPOINT` → aponta para Alloy
- `ingress.hosts[0].host` → `nuxt-workshop.local` (adicionar ao `/etc/hosts` via script `09`)
- `podAnnotations` incluem anotações de scrape do Pyroscope

---

## Conventions

### Naming
- Resources use the `monitoramento-` prefix: `monitoramento-registry`, `monitoramento-cluster`
- Helm release names match chart names

### Labels (required on all resources)
```yaml
labels:
  app: <service-name>
  version: "<semver>"
```

### Namespaces
| Namespace | Workloads |
|-----------|-----------|
| `monitoring` | Prometheus, Grafana, Loki, Tempo, Pyroscope, Alloy |
| `traefik` | Ingress controller |
| `cnpg-system` | CloudNativePG operator |
| `default` | Application workloads |

### Resources (apply to every container)
```yaml
resources:
  requests: { cpu: "100m", memory: "128Mi" }
  limits:   { cpu: "500m", memory: "512Mi" }
```

### Security Context (apply to all Pods)
```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
securityContext:
  allowPrivilegeEscalation: false
  capabilities: { drop: [ALL] }
```

### Image Pull Policy
- `Always` — development / any tag mutable
- `IfNotPresent` — production / immutable tags

---

## Cross-Platform Rules

- Every script in `00.Infraestrutura/windows/` must have an equivalent in `00.Infraestrutura/linux/`.
- PowerShell scripts use `winget` for installs (no `choco`, no admin required for user-scoped tools).
- Bash scripts use the distro package manager or official install scripts.
- Avoid Windows-only paths in YAML/Helm — keep manifests OS-agnostic.
- Script `09` (`atualizar-hosts`) manages `/etc/hosts` automatically — do not ask users to edit it manually.

---

## Related Instructions

- [Monitoring stack](.github/instructions/monitoring-stack.instructions.md)
- [Kubernetes & Helm conventions](.github/instructions/kubernetes-manifests.instructions.md)
- [CI/CD & ArgoCD](.github/instructions/cicd-argocd.instructions.md)

## Skills Disponíveis

| Skill | Uso |
|-------|-----|
| `kubernetes-expert` | Manifests, Helm, ArgoCD |
| `shell-scripting-expert` | Scripts Windows/Linux com paridade |
| `devops-expert` | Ciclo DevOps completo, DORA metrics |
| `github-actions-expert` | Workflows CI/CD seguros |
| `terraform-expert` | IaC com HCP Terraform |
| `adr-generator` | Registros de decisão arquitetural |
| `context7-expert` | Docs atualizadas de libs/frameworks |
| `devils-advocate` | Stress-test de ideias |
