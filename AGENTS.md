# k8s-monitoring — Agent Instructions

This project builds a full **Kubernetes observability platform** running on k3d (Kubernetes in Docker) with cross-platform support for **Windows (PowerShell)** and **Linux (Bash)**. The stack covers metrics, logs, traces and continuous profiling, deployed via Helm and managed by ArgoCD, with GitHub Actions as CI/CD.

---

## Project Layout

```
00.scripts/          # Setup automation (windows/ + linux/ + yamls/)
01.docker-images/    # Static nginx image (workshop-nginx)
02.docker-envs/      # Node.js client+server Docker example
03.docker-compose/   # Local docker-compose reference env
04.fundamentos-kubernetes/  # Educational raw manifests (01→05)
05.helm-chart/       # Production app: nuxt-workshop (app/ + helm/)
06.explorar*/        # Scratch / exploration scripts
```

See [`00.scripts/yamls/`](00.scripts/yamls/) for every Helm values override used in the monitoring stack.

---

## Environment Setup

Run scripts **in order**. Every script is idempotent — re-running is safe.

### Windows

```powershell
.\00.scripts\windows\01.install-dependencies.ps1   # winget: k3d, kubectl, helm
.\00.scripts\windows\02.verify-installs.ps1        # sanity check
.\00.scripts\windows\03.setup-k3d-multi-node.ps1   # create cluster + Traefik + CloudNativePG
.\00.Infraestrutura\windows\04.configurar-monitoramento.ps1        # full observability stack
.\00.Infraestrutura\windows\05.configurar-cnpg-criar-base-pgsql.ps1  # PostgreSQL via CloudNativePG
```

### Linux

```bash
bash 00.scripts/linux/01.install-dependencies.sh
bash 00.scripts/linux/02.verify-installs.sh
bash 00.scripts/linux/03.setup-k3d-multi-node.sh
bash 00.scripts/linux/04.setup-database.sh
bash 00.scripts/linux/05.setup-monitoring.sh
```

### k3d Cluster Specs

- **Name**: `workshop`
- **Agents**: 2 worker nodes
- **Ports**: 80 → LoadBalancer, 443 → LoadBalancer
- **Registry**: `workshop-registry.localhost:5001` (push local images here)
- **Ingress**: Traefik (default k3d Traefik disabled, re-installed via Helm with 1 replica)

---

## Monitoring Stack

| Component | Namespace | Access |
|-----------|-----------|--------|
| Grafana (kube-prometheus-stack) | `monitoring` | `localhost:3000` (port-forward), password: `workshop123` |
| Prometheus | `monitoring` | Internal only |
| Loki | `monitoring` | Datasource in Grafana |
| Tempo | `monitoring` | OTLP gRPC `4317`, HTTP `4318` |
| Pyroscope | `monitoring` | Datasource in Grafana |
| Alloy (OTel collector) | `monitoring` | `alloy.monitoring.svc.cluster.local:4318` |

**Observability flow**: App → OpenTelemetry SDK → Alloy → {Loki, Tempo, Pyroscope} ← Grafana

Full Helm values for each component live in [`00.scripts/yamls/`](00.scripts/yamls/).

---

## Helm Chart (nuxt-workshop)

- Chart: [`05.helm-chart/helm/`](05.helm-chart/helm/)
- App source: [`05.helm-chart/app/`](05.helm-chart/app/) (Nuxt 3 + Prisma + OpenTelemetry)
- Image: `workshop-registry.localhost:5001/nuxt-workshop:<tag>`

Key values to know — see [`05.helm-chart/helm/values.yaml`](05.helm-chart/helm/values.yaml):
- `configMap.data.OTEL_EXPORTER_OTLP_ENDPOINT` → points to Alloy
- `ingress.hosts[0].host` → `nuxt-workshop.local` (add to `/etc/hosts` / `C:\Windows\System32\drivers\etc\hosts`)
- `podAnnotations` include Pyroscope scrape annotations

---

## Conventions

### Naming
- Resources use the `workshop-` prefix: `workshop-registry`, `workshop-pod`, `workshop-deployment-completo`
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

- Every script in `00.scripts/windows/` must have an equivalent in `00.scripts/linux/`.
- PowerShell scripts use `winget` for installs (no `choco`, no admin required for user-scoped tools).
- Bash scripts use the distro package manager or official install scripts.
- Avoid Windows-only paths in YAML/Helm — keep manifests OS-agnostic.

---

## Related Instructions

- [Monitoring stack details](.github/instructions/monitoring-stack.instructions.md)
- [Kubernetes & Helm conventions](.github/instructions/kubernetes-manifests.instructions.md) *(existing)*
- [CI/CD & ArgoCD](.github/instructions/cicd-argocd.instructions.md)
