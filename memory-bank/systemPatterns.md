# System Patterns — k8s-monitoring

## Architecture Overview

```
Developer Machine
└── Docker
    └── k3d cluster: monitoramento
        ├── Traefik (ingress controller, namespace: traefik)
        ├── Monitoring namespace
        │   ├── kube-prometheus-stack  (Grafana + Prometheus + Alertmanager)
        │   ├── Loki                   (log aggregation)
        │   ├── Tempo                  (distributed tracing)
        │   ├── Pyroscope              (continuous profiling)
        │   └── Alloy                  (OpenTelemetry collector / router)
        ├── cnpg-system namespace
        │   └── CloudNativePG operator
        └── default namespace
            ├── PostgreSQL cluster     (CloudNativePG)
            ├── Redis                  (Bitnami)
            ├── MongoDB Community      (Percona)
            ├── RavenDB
            ├── RabbitMQ
            ├── Keycloak
            ├── Vault
            ├── SonarQube
            └── Demo apps (nuxt-workshop, MonitoringDotNet)
```

## Signal Flow

```
App → OpenTelemetry SDK
           ↓
      Alloy (collector)
       ↙    ↓    ↘
  Loki  Tempo  Pyroscope
           ↓
     Grafana datasources
```

Prometheus scrapes Pods via `ServiceMonitor` CRDs (`release: kube-prometheus-stack`).

## Key Architectural Decisions

### ADR-001: k3d for local Kubernetes

Use k3d (k3s in Docker) instead of minikube or kind because it supports multi-node clusters, built-in load balancer port mapping, and local image registries.

### ADR-002: Numbered idempotent scripts

Scripts are numbered `01`→`09` and safe to re-run. Each script focuses on one concern. This makes partial re-runs safe and the order clear.

### ADR-003: Alloy as the OTel collector

Instead of sending traces/logs directly to Loki/Tempo, apps send to Alloy which routes to the right backend. This decouples apps from storage backends.

### ADR-004: ServiceMonitor on every data service

Every installed service (Redis, MongoDB, PostgreSQL, etc.) must have a `ServiceMonitor` so Prometheus auto-discovers it. Label: `release: kube-prometheus-stack`.

### ADR-005: Cross-platform parity

Every PowerShell script in `00.Infraestrutura/windows/` must have an exact Bash equivalent in `00.Infraestrutura/linux/`. Same logic, same ordering, different syntax.

### ADR-006: Service-per-folder structure

Each additional service has its own folder under `00.Infraestrutura/servicos/<service>/` with:

- `instalar.ps1` (Windows)
- `instalar.sh` (Linux)
- `values.yaml` or `manifest.yaml` (Helm/YAML overrides)

## Naming Conventions

| Resource          | Pattern                                 | Example                          |
| ----------------- | --------------------------------------- | -------------------------------- |
| k3d cluster       | `monitoramento`                         | —                                |
| Registry          | `monitoramento-registry.localhost:5001` | —                                |
| Ingress hostnames | `<service>.monitoramento.local`         | `grafana.monitoramento.local`    |
| App hostnames     | `<app>.local`                           | `nuxt-workshop.local`            |
| Helm releases     | match chart name                        | `kube-prometheus-stack`          |
| Script files      | `NN.verb-noun.ext`                      | `04.configurar-monitoramento.sh` |

## Label Conventions

All custom resources must have:

```yaml
labels:
  app: <service-name>
  version: "<semver>"
```

`ServiceMonitor` resources must have:

```yaml
labels:
  release: kube-prometheus-stack
```

## Namespace Map

| Namespace     | Contents                                             |
| ------------- | ---------------------------------------------------- |
| `monitoring`  | kube-prometheus-stack, Loki, Tempo, Pyroscope, Alloy |
| `traefik`     | Traefik ingress controller                           |
| `argocd`      | ArgoCD GitOps controller                             |
| `cnpg-system` | CloudNativePG operator                               |
| `default`     | All data services + demo apps                        |

## Resource Defaults (every container)

```yaml
resources:
  requests: { cpu: "100m", memory: "128Mi" }
  limits: { cpu: "500m", memory: "512Mi" }
```

## Pod Security Defaults

```yaml
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
securityContext:
  allowPrivilegeEscalation: false
  capabilities: { drop: [ALL] }
```
