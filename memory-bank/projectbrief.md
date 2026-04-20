# Project Brief — k8s-monitoring

## Project Name

k8s-monitoring

## Goal

Build a full **Kubernetes observability platform** that runs on k3d (Kubernetes in Docker) with cross-platform support for Windows (PowerShell) and Linux (Bash). Content is produced for the YouTube channel [@luysantanadev](https://www.youtube.com/@luysantanadev).

## Core Scope

- Local Kubernetes cluster via k3d named `monitoramento`
- Full observability stack: metrics, logs, traces, continuous profiling
- Support for common backend services: PostgreSQL, Redis, MongoDB, RavenDB, RabbitMQ, Keycloak, Vault, SonarQube
- A demo application (`nuxt-workshop` / `MonitoringDotNet`) that exercises the full observability stack
- Idempotent, numbered setup scripts (`01` → `09`) that work on both Windows and Linux

## Out of Scope

- Production cloud deployments (this is a local lab environment)
- Authentication/SSO on the observability tools themselves (workshop simplification)

## Success Criteria

- All scripts run without errors on both Windows (PowerShell) and Linux (Bash)
- Every service is reachable via its Ingress hostname on the local machine
- Grafana shows data from Prometheus, Loki, Tempo, and Pyroscope
- The demo app produces traces, logs, and metrics visible in Grafana

## Stakeholders

- Solo developer: @luysantanadev
- YouTube audience: developers learning Kubernetes observability

## Key Constraints

- All infrastructure must run locally on developer hardware
- k3d cluster port map must include: 80, 443, 4317, 4318, 5432, 6379, 27017
- Scripts must be idempotent (safe to re-run)
- Every service needs a `ServiceMonitor` so Prometheus can scrape it automatically
