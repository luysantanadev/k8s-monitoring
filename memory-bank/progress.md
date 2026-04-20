# Progress — k8s-monitoring

> Track what's done, what works, what's pending, and known issues.
> Update after every significant change.

---

## What Works ✅

### Infrastructure Scripts (Windows)

| Script                         | Status    | Notes                                  |
| ------------------------------ | --------- | -------------------------------------- |
| `01.instalar-dependencias.ps1` | ✅ Exists | Installs k3d, kubectl, helm via winget |
| `02.verificar-instalacoes.ps1` | ✅ Exists | Sanity checks                          |
| `03.criar-cluster-k3d.ps1`     | ✅ Exists | Creates cluster + Traefik              |

### Infrastructure Scripts (Linux)

| Script                           | Status    | Notes                 |
| -------------------------------- | --------- | --------------------- |
| `01.instalar-dependencias.sh`    | ✅ Exists |                       |
| `02.verificar-instalacoes.sh`    | ✅ Exists |                       |
| `03.criar-cluster-k3d.sh`        | ✅ Exists |                       |
| `04.configurar-monitoramento.sh` | ✅ Exists | Full monitoring stack |
| `09.atualizar-hosts.sh`          | ✅ Exists |                       |

### Services (under `00.Infraestrutura/servicos/`)

| Service   | ps1 | sh  | values/manifest   |
| --------- | --- | --- | ----------------- |
| grafana   | ✅  | —   | ✅ (7 yaml files) |
| keycloak  | ✅  | ✅  | ✅ manifest.yaml  |
| mongodb   | ✅  | ✅  | ✅ manifest.yaml  |
| pgsql     | ✅  | ✅  | ✅ values.yaml    |
| rabbitmq  | ✅  | ✅  | ✅ values.yaml    |
| ravendb   | ✅  | ✅  | ✅ values.yaml    |
| redis     | ✅  | ✅  | ✅ values.yaml    |
| sonarqube | ✅  | ✅  | ✅ values.yaml    |
| vault     | ✅  | ✅  | ✅ values.yaml    |

### Demo Applications

| App                     | Status                        | Notes                                                                    |
| ----------------------- | ----------------------------- | ------------------------------------------------------------------------ |
| MonitoringDotNet (.NET) | ✅ Source exists              | `01.apps/MonitoringDotNet/` — Dockerfile, EF migrations, OTel configured |
| nuxt-workshop           | ✅ Source + Helm chart exists | `05.helm-chart/`                                                         |

### GitHub Copilot Skills

| Skill                        | Status                            |
| ---------------------------- | --------------------------------- |
| `acquire-codebase-knowledge` | ✅ Created                        |
| `progressive-commits`        | ✅ Created this session           |
| `session-handoff`            | ✅ Created this session           |
| All other skills (30+)       | ✅ Inherited from awesome-copilot |

---

## What's Left to Build ⏳

### Missing Linux Scripts

- `05.configurar-cnpg-criar-base-pgsql.sh` (only `.ps1` exists at top level)
- `06.configurar-redis.sh`
- `07.configurar-mongodb.sh`
- `08.configurar-ravendb.sh`
  > Note: Services now live under `00.Infraestrutura/servicos/` with `instalar.sh` — confirm if numbered scripts are still needed at top level

### Validation / Testing

- [ ] End-to-end test: run all scripts on fresh Linux environment
- [ ] Confirm Grafana dashboards receive data from all 4 signals (metrics, logs, traces, profiling)
- [ ] Validate MonitoringDotNet produces OTLP traces visible in Tempo
- [ ] Verify RabbitMQ and Keycloak `instalar.sh` work and ServiceMonitors are active

### Documentation

- [ ] README for MonitoringDotNet explaining endpoints and how to observe
- [ ] Architecture diagram in README

---

## Known Issues ⚠️

| Issue                                            | Severity | Notes                                      |
| ------------------------------------------------ | -------- | ------------------------------------------ |
| `00.Infraestrutura/linux/` missing scripts 05-08 | Medium   | May be in `servicos/*/instalar.sh` instead |
| `rtk` CLI must be installed separately           | Low      | Not in script 01                           |

---

## Current Status

**Phase**: Infrastructure baseline + tooling  
**Overall Progress**: ~60% — Core monitoring stack defined; service scripts present; apps exist but full E2E validation pending
