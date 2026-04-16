# k8s-monitoring

> Repositório de apoio ao canal **[@luysantanadev](https://www.youtube.com/@luysantanadev)** no YouTube.
> Cada pasta do projeto corresponde a um módulo de vídeos sobre Kubernetes, observabilidade e DevOps na prática.

---

## Sobre o Projeto

Este repositório constrói uma **plataforma de observabilidade completa** rodando em Kubernetes local (k3d), com suporte cross-platform para **Windows (PowerShell)** e **Linux (Bash)**. O stack cobre métricas, logs, traces e continuous profiling, com todos os bancos de dados monitorados automaticamente via Prometheus.

O objetivo é mostrar na prática como times de engenharia constroem ambientes de observabilidade reais — do cluster local até dashboards no Grafana — usando as ferramentas que o mercado usa hoje.

---

## Tech Stack

| Camada | Tecnologia |
|--------|-----------|
| Cluster local | [k3d](https://k3d.io) (Kubernetes in Docker) |
| Ingress | [Traefik](https://traefik.io) |
| Métricas | [Prometheus](https://prometheus.io) + [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts) |
| Logs | [Loki](https://grafana.com/oss/loki/) |
| Traces | [Tempo](https://grafana.com/oss/tempo/) |
| Profiling | [Pyroscope](https://grafana.com/oss/pyroscope/) |
| OTel Collector | [Grafana Alloy](https://grafana.com/oss/alloy/) |
| Visualização | [Grafana](https://grafana.com) |
| PostgreSQL | [CloudNativePG](https://cloudnative-pg.io) |
| Redis | [Bitnami Redis](https://github.com/bitnami/charts/tree/main/bitnami/redis) |
| MongoDB | [MongoDB Community Operator](https://github.com/mongodb/mongodb-kubernetes-operator) |
| RavenDB | [RavenDB Helm Chart](https://ravendb.net) |
| App demo | [Nuxt 3](https://nuxt.com) + [Prisma](https://prisma.io) + OpenTelemetry |

---

## Estrutura do Repositório

```
00.Infraestrutura/          # Scripts de setup (windows/ + linux/ + yamls/)
01.docker-images/           # Imagem nginx estática (workshop-nginx)
02.docker-envs/             # Exemplo Docker com Node.js client+server
03.docker-compose/          # Ambiente local de referência com docker-compose
04.fundamentos-kubernetes/  # Manifests educacionais raw (01→05)
05.helm-chart/              # App de produção: nuxt-workshop (app/ + helm/)
06.explorando/              # Scripts de exploração e experimentos
```

---

## Infraestrutura — Setup Rápido

Execute os scripts **em ordem**. Todos são idempotentes — pode re-executar sem efeitos colaterais.

### Windows (PowerShell 7+)

```powershell
.\00.Infraestrutura\windows\01.instalar-dependencias.ps1         # winget: k3d, kubectl, helm
.\00.Infraestrutura\windows\02.verificar-instalacoes.ps1         # verifica todas as ferramentas
.\00.Infraestrutura\windows\03.criar-cluster-k3d.ps1             # cluster k3d + Traefik
.\00.Infraestrutura\windows\04.configurar-monitoramento.ps1      # Prometheus, Grafana, Loki, Tempo, Pyroscope, Alloy
.\00.Infraestrutura\windows\05.configurar-cnpg-criar-base-pgsql.ps1  # PostgreSQL via CloudNativePG
.\00.Infraestrutura\windows\06.configurar-redis.ps1              # Redis + ServiceMonitor
.\00.Infraestrutura\windows\07.configurar-mongodb.ps1            # MongoDB Community + ServiceMonitor
.\00.Infraestrutura\windows\08.configurar-ravendb.ps1            # RavenDB + Ingress
.\00.Infraestrutura\windows\09.atualizar-hosts.ps1               # /etc/hosts automático
```

### Linux (Bash)

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

### Cluster k3d

| Configuração | Valor |
|---|---|
| Nome | `monitoramento` |
| Worker nodes | 2 |
| Registry local | `monitoramento-registry.localhost:5001` |
| Portas expostas | `80`, `443`, `4317` (OTLP gRPC), `4318` (OTLP HTTP), `5432`, `6379`, `27017` |

---

## Stack de Observabilidade

Após executar o script `04`, o seguinte stack estará disponível:

| Componente | Acesso |
|-----------|--------|
| Grafana | <http://grafana.monitoramento.local> · senha: `workshop123` |
| Loki | datasource no Grafana |
| Tempo | `tempo.monitoramento.local` · OTLP: `4317` (gRPC) / `4318` (HTTP) |
| Pyroscope | `pyroscope.monitoramento.local` · datasource no Grafana |
| Alloy | `alloy.monitoring.svc.cluster.local:4318` (interno) |

**Fluxo de dados**: App → OpenTelemetry SDK → Alloy → {Loki, Tempo, Pyroscope} ← Grafana

### Bancos de Dados Monitorados

| Banco | Acesso externo | Ingress |
|-------|----------------|---------|
| PostgreSQL | `localhost:5432` | IngressRouteTCP |
| Redis | `localhost:6379` | IngressRouteTCP |
| MongoDB | `localhost:27017` | IngressRouteTCP |
| RavenDB | `<nome>-ravendb.k3d.localhost` | Ingress HTTP |

> Todos os bancos incluem `ServiceMonitor` para scrape automático pelo Prometheus.

---

## Pré-requisitos

- Docker Desktop (Windows) ou Docker Engine (Linux)
- 8 GB RAM disponível para o cluster k3d
- Windows: PowerShell 7+ (`winget install Microsoft.PowerShell`)
- Linux: Bash 4+, `curl`, `python3`

---

## Roadmap

> Módulos planejados para os próximos vídeos do canal.

### Em Desenvolvimento

- [ ] **App demo com OpenTelemetry** — Nuxt 3 + Prisma instrumentado com traces, logs e métricas enviados via Alloy
- [ ] **Dashboards Grafana** — dashboards prontos para cada banco de dados e para a aplicação demo

### Próximos Módulos

- [ ] **CI/CD com GitHub Actions** — pipeline completo: build, push de imagem para o registry local, deploy no k3d
- [ ] **GitOps com ArgoCD** — sync automático do Helm chart via ArgoCD, gestão de secrets com Sealed Secrets
- [ ] **Alertas com Prometheus Alertmanager** — regras de alerta para SLOs, notificações via webhook
- [ ] **Escalabilidade** — HPA, VPA e KEDA com métricas customizadas do Prometheus
- [ ] **Segurança** — Network Policies, Pod Security Admission, Falco para runtime security
- [ ] **Terraform** — provisionamento de infraestrutura cloud com HCP Terraform integrado ao CI/CD

---

## Licença

[MIT](LICENSE) · Conteúdo produzido por [@luysantanadev](https://www.youtube.com/@luysantanadev)