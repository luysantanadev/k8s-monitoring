# youtube-cloud-native-journey — Agent Instructions

This project is a practical journey for building and operating **modern cloud-native applications on Kubernetes**, starting from a local k3d lab and evolving through security, performance, efficiency, DevOps, and CI/CD practices. Observability remains a core pillar (metrics, logs, traces, profiling), but it is part of a broader application platform strategy. Content is produced for the YouTube channel [@luysantanadev](https://www.youtube.com/@luysantanadev).

---

## Project Layout

```
00.Infraestrutura/        # Setup automation (windows/ + linux/ + servicos/)
01.Aplicacoes/            # Application code and cloud-native experiments
.github/memory-bank/      # Persistent project context, tasks, and troubleshooting history
```

See [`00.Infraestrutura/servicos/01.grafana/yamls/`](00.Infraestrutura/servicos/01.grafana/yamls/) for monitoring stack values and manifests.

---

## Environment Setup

Run scripts **in order**. Every script is idempotent — re-running is safe.

### Base cluster bootstrap (required first)

### Windows

```powershell
.\00.Infraestrutura\windows\01.instalar-dependencias.ps1         # winget: k3d, kubectl, helm
.\00.Infraestrutura\windows\02.verificar-instalacoes.ps1         # sanity check
.\00.Infraestrutura\windows\03.criar-cluster-k3d.ps1             # cluster + Traefik
```

### Linux

```bash
bash 00.Infraestrutura/linux/01.instalar-dependencias.sh
bash 00.Infraestrutura/linux/02.verificar-instalacoes.sh
bash 00.Infraestrutura/linux/03.criar-cluster-k3d.sh
bash 00.Infraestrutura/linux/04.configurar-monitoramento.sh
bash 00.Infraestrutura/linux/09.atualizar-hosts.sh
```

### Platform services (install as needed after bootstrap)

Use service-specific scripts in `00.Infraestrutura/servicos/<NN.nome>/`:

- `instalar.ps1` for Windows
- `instalar.sh` for Linux
- `values.yaml` or `manifest.yaml` for Helm/Kubernetes resources

### k3d Cluster Specs

- **Name**: `monitoramento`
- **Agents**: 2 worker nodes
- **Ports expostos no LoadBalancer**: 80, 443, 4317 (OTLP gRPC), 4318 (OTLP HTTP), 5432 (PostgreSQL), 6379 (Redis), 27017 (MongoDB)
- **Registry**: `monitoramento-registry.localhost:5001` (push local images here)
- **Ingress**: Traefik (instalado via Helm com entrypoints customizados para cada porta TCP)

---

## Platform and Observability Stack

| Component                       | Namespace    | Acesso                                                      |
| ------------------------------- | ------------ | ----------------------------------------------------------- |
| Grafana (kube-prometheus-stack) | `monitoring` | `grafana.monitoramento.local`, senha: `workshop123`         |
| Prometheus                      | `monitoring` | Interno                                                     |
| Loki                            | `monitoring` | `loki.monitoramento.local` — datasource no Grafana          |
| Tempo                           | `monitoring` | `tempo.monitoramento.local` — OTLP gRPC `4317`, HTTP `4318` |
| Pyroscope                       | `monitoring` | `pyroscope.monitoramento.local` — datasource no Grafana     |
| Alloy (OTel collector)          | `monitoring` | `alloy.monitoring.svc.cluster.local:4318`                   |

**Observability flow**: App → OpenTelemetry SDK → Alloy → {Loki, Tempo, Pyroscope} ← Grafana

Helm values/manifests de observabilidade em [`00.Infraestrutura/servicos/01.grafana/yamls/`](00.Infraestrutura/servicos/01.grafana/yamls/).

## Bancos de Dados

| Banco                      | Namespace | Porta Externa             | Ingress                        |
| -------------------------- | --------- | ------------------------- | ------------------------------ |
| PostgreSQL (CloudNativePG) | `default` | `5432` (IngressRouteTCP)  | —                              |
| Redis (Bitnami)            | `default` | `6379` (IngressRouteTCP)  | —                              |
| MongoDB Community          | `default` | `27017` (IngressRouteTCP) | —                              |
| RavenDB                    | `default` | —                         | `<nome>-ravendb.k3d.localhost` |

Cada banco é instalado com `ServiceMonitor` (`release: kube-prometheus-stack`) para scrape automático pelo Prometheus.

## Serviços Adicionais

| Serviço                  | Namespace   | Acesso                                    | Credenciais                                              | Script                                              |
| ------------------------ | ----------- | ----------------------------------------- | -------------------------------------------------------- | --------------------------------------------------- |
| RabbitMQ (Operator)      | `rabbitmq`  | `rabbitmq.monitoramento.local`            | `user` / `Workshop123rabbit`                             | `00.Infraestrutura/servicos/08.rabbitmq/instalar.ps1` (ou `.sh`) |
| HashiCorp Vault          | `vault`     | `vault.monitoramento.local`               | Root token em Secret `vault-unseal-keys` (namespace `vault`) | `00.Infraestrutura/servicos/10.vault/instalar.ps1` (ou `.sh`) |
| ArgoCD                   | `argocd`    | `argocd.monitoramento.local`              | `admin` / `kubectl -n argocd get secret argocd-initial-admin-secret` | `00.Infraestrutura/servicos/02.argocd/instalar.ps1` (ou `.sh`) |
| SonarQube                | `default`   | `sonarqube.monitoramento.local`           | `admin` / `admin` (alterar no primeiro login)            | `00.Infraestrutura/servicos/09.sonarqube/instalar.ps1` (ou `.sh`) |
| Keycloak                 | `default`   | —                                         | —                                                        | `00.Infraestrutura/servicos/03.keycloak/instalar.ps1` (ou `.sh`) |

Cada serviço é instalado individualmente via seu script dedicado em `00.Infraestrutura/servicos/<NN.nome>/`.

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

| Namespace     | Workloads                                          |
| ------------- | -------------------------------------------------- |
| `monitoring`  | Prometheus, Grafana, Loki, Tempo, Pyroscope, Alloy |
| `traefik`     | Ingress controller                                 |
| `cnpg-system` | CloudNativePG operator                             |
| `default`     | Application workloads                              |

### Resources (apply to every container)

```yaml
resources:
  requests: { cpu: "100m", memory: "128Mi" }
  limits: { cpu: "500m", memory: "512Mi" }
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
- [Troubleshooting Memory](.github/instructions/troubleshooting-memory.instructions.md)
- [Memory Bank](.github/instructions/memory-bank.instructions.md)

## Skills Disponíveis

| Skill                    | Uso                                                                                 |
| ------------------------ | ----------------------------------------------------------------------------------- |
| `kubernetes-expert`      | Manifests, Helm, ArgoCD                                                             |
| `shell-scripting-expert` | Scripts Windows/Linux com paridade                                                  |
| `devops-expert`          | Ciclo DevOps completo, DORA metrics                                                 |
| `github-actions-expert`  | Workflows CI/CD seguros                                                             |
| `terraform-expert`       | IaC com HCP Terraform                                                               |
| `adr-generator`          | Registros de decisão arquitetural                                                   |
| `context7-expert`        | Docs atualizadas de libs/frameworks                                                 |
| `devils-advocate`        | Stress-test de ideias                                                               |
| `progressive-commits`       | Commits pequenos e atômicos por etapa concluída com sucesso                                              |
| `session-handoff`           | Lê e grava o Memory Bank para continuar o projeto entre sessões sem perder contexto                      |
| `troubleshooting-memory`    | Consulta e registra incidentes resolvidos; impede rediagnosticar problemas já conhecidos                 |
