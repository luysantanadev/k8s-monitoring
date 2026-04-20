# Product Context — k8s-monitoring

## Why This Project Exists

Kubernetes observability is intimidating to learn because it requires many tools that must work together. This project provides a **complete, ready-to-run lab** so developers can learn metrics, logs, traces, and profiling in a realistic environment without needing cloud access.

## Problems It Solves

| Problem                                                      | Solution                                                      |
| ------------------------------------------------------------ | ------------------------------------------------------------- |
| "I want to learn observability but cloud costs money"        | k3d cluster runs entirely on local Docker                     |
| "Each tool requires separate setup and docs are scattered"   | Numbered scripts install everything in order                  |
| "I need a real app to observe, not just hello-world"         | `MonitoringDotNet` and `nuxt-workshop` are fully instrumented |
| "Works on my machine but not my colleague's (Windows/Linux)" | Every script has both a `.ps1` and a `.sh` equivalent         |
| "The pieces don't talk to each other"                        | Alloy routes signals; datasources pre-configured in Grafana   |

## How It Should Work

1. Developer clones the repo
2. Runs scripts `01` → `09` in order (or `04` for the full monitoring stack)
3. Runs script `09` to update `/etc/hosts`
4. Accesses Grafana at `grafana.monitoramento.local` and sees live data
5. Deploys the demo app to generate real signals
6. Explores Grafana dashboards: metrics → Prometheus, logs → Loki, traces → Tempo, profiling → Pyroscope

## User Experience Goals

- **Zero manual YAML editing** for the base setup — all overrides live in `00.Infraestrutura/servicos/`
- **Single script per service** — easy to add/remove a component
- **Scripts print clear success/failure** messages at every step
- **Hostnames are human-readable** — `grafana.monitoramento.local`, `nuxt-workshop.local`, etc.
- **Dashboards are pre-built** — no Grafana config after first login
