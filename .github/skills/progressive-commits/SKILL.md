---
name: progressive-commits
description: 'Make small, atomic commits tied to the successful execution of each script, setup step, or project milestone, following the Conventional Commits specification. Use when setting up infrastructure, running installation scripts (01→09), deploying services, adding Helm charts, or implementing app features incrementally. Triggers on requests like "commit as we go", "commit each step", "commit after script succeeds", "incremental commits", or "progressive commits".'
license: MIT
allowed-tools: Bash
---

# Progressive Commits — Incremental, Verified, Conventional

## Overview

Commit **one logical unit at a time**, only after verifying the step actually worked.
Each commit captures a single, stable state of the project so the history reads like a changelog of working milestones.

---

## When to Use This Skill

- Running numbered infrastructure scripts (`01` → `09`) sequentially
- Installing or configuring a new service (Helm chart, operator, database)
- Adding or editing Kubernetes manifests / Helm values
- Implementing a feature inside `01.apps/` step by step
- Any workflow where "commit as each piece is proven to work" was requested

---

## Core Principles

| Principle                  | Rule                                                                                               |
| -------------------------- | -------------------------------------------------------------------------------------------------- |
| **Verify first**           | Only commit after the step produces a successful outcome (exit 0, pod Running, endpoint reachable) |
| **One concern per commit** | Never mix unrelated changes; if two files belong to different logical steps, use two commits       |
| **Small is safe**          | Prefer 5 lines changed per commit over 500; small commits are easy to revert                       |
| **Imperative mood**        | "add loki values file" not "added loki values file"                                                |
| **Present tense**          | Describes what the commit _does_, not what you _did_                                               |

---

## Conventional Commit Format

```
<type>(<scope>): <description>

[optional body — explain WHY, not WHAT]

[optional footer — Closes #N, BREAKING CHANGE: …]
```

### Types

| Type       | Use for                                                             |
| ---------- | ------------------------------------------------------------------- |
| `feat`     | New capability added (new service, new endpoint, new script)        |
| `fix`      | Corrects a broken state (wrong port, bad image tag, failing probe)  |
| `chore`    | Maintenance that doesn't change behavior (dependency bump, comment) |
| `ci`       | GitHub Actions workflow changes                                     |
| `docs`     | README, ADR, or inline documentation only                           |
| `refactor` | Restructure without changing behavior                               |
| `perf`     | Optimisation (resource limits tuning, caching)                      |
| `test`     | New or updated tests                                                |
| `build`    | Dockerfile, build scripts, image push                               |
| `revert`   | Undo a previous commit                                              |

### Scopes for This Project

Map the scope to the directory or service being touched:

| Scope        | Covers                                                |
| ------------ | ----------------------------------------------------- |
| `infra`      | `00.Infraestrutura/` scripts and shared cluster setup |
| `cluster`    | k3d cluster creation / Traefik / registry             |
| `monitoring` | kube-prometheus-stack, Loki, Tempo, Pyroscope, Alloy  |
| `grafana`    | Dashboards, datasources, ingress for Grafana          |
| `loki`       | Loki Helm values / ingress                            |
| `tempo`      | Tempo Helm values / ingress                           |
| `pyroscope`  | Pyroscope Helm values                                 |
| `alloy`      | Alloy (OTel collector) config                         |
| `pgsql`      | CloudNativePG / PostgreSQL                            |
| `redis`      | Redis Helm chart + ServiceMonitor                     |
| `mongodb`    | MongoDB Community + ServiceMonitor                    |
| `ravendb`    | RavenDB Helm values + Ingress                         |
| `keycloak`   | Keycloak manifests                                    |
| `rabbitmq`   | RabbitMQ Helm values                                  |
| `sonarqube`  | SonarQube values                                      |
| `vault`      | HashiCorp Vault values                                |
| `app`        | `01.apps/` — application code                         |
| `helm`       | `05.helm-chart/helm/` — nuxt-workshop chart           |
| `ci`         | `.github/workflows/`                                  |
| `hosts`      | `/etc/hosts` automation (script `09`)                 |

---

## Step-by-Step Workflow

### 1. Execute the step

Run the script or make the change:

```bash
# Example: infrastructure script
bash 00.Infraestrutura/linux/03.criar-cluster-k3d.sh
```

### 2. Verify success before committing

Do not commit if the step failed. Common verification commands:

```bash
# Cluster / nodes
kubectl get nodes

# Pod status
kubectl get pods -n <namespace>

# Helm release
helm status <release> -n <namespace>

# Service reachable
curl -sf http://<host>/healthz

# Script exit code
echo $?   # must be 0
```

Only proceed to step 3 if the verification passes.

### 3. Stage only the files changed in this step

```bash
# See what changed
git status --short
git diff --stat

# Stage related files only (never use `git add .` blindly)
git add 00.Infraestrutura/linux/03.criar-cluster-k3d.sh
```

**Never stage** unrelated files, generated artefacts (`bin/`, `obj/`, `*.lock` unless intentional), or secrets (`.env`, credentials).

### 4. Construct the commit message

Combine type + scope + one-line description:

```
feat(cluster): add k3d cluster creation script with Traefik ingress
```

Add a body only when the _why_ is non-obvious:

```
feat(monitoring): install kube-prometheus-stack v65 with persistent storage

Switched from emptyDir to PVC so metrics survive pod restarts.
Grafana admin password stored in monitoring/grafana-secret.
```

### 5. Commit

```bash
git commit -m "feat(cluster): add k3d cluster creation script with Traefik ingress"
```

Multi-line commit (body + footer):

```bash
git commit -m "$(cat <<'EOF'
feat(monitoring): install kube-prometheus-stack v65 with persistent storage

Switched from emptyDir to PVC so metrics survive pod restarts.
Grafana admin password stored in monitoring/grafana-secret.
EOF
)"
```

### 6. Repeat for the next step

Move to the next script or task and repeat steps 1–5.

---

## Commit Boundary Decision Guide

Use this decision tree to decide when to split or merge:

```
Did this change affect more than one service or namespace?
  YES → split into one commit per service
  NO  → Is the change self-contained and verifiable alone?
         YES → single commit
         NO  → wait until it can be verified, then commit
```

### Examples of correct splits

| Bad (too broad)                                | Good (atomic)                                                                                                                                                       |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `feat(infra): install all monitoring services` | `feat(loki): add Loki Helm values with S3 storage`<br>`feat(tempo): add Tempo Helm values with OTLP ingress`<br>`feat(grafana): add datasources for Loki and Tempo` |
| `fix: fix several issues`                      | `fix(redis): correct ServiceMonitor selector label`<br>`fix(pgsql): increase memory limit to 512Mi`                                                                 |

---

## Milestone Commit Map for Infrastructure Scripts

When executing the numbered scripts in order, one commit per script is the baseline — split further only if the script installs multiple independent components:

| Script                        | Suggested commit                                               |
| ----------------------------- | -------------------------------------------------------------- |
| `01.instalar-dependencias`    | `chore(infra): install k3d, kubectl, helm dependencies`        |
| `02.verificar-instalacoes`    | `chore(infra): add installation verification script`           |
| `03.criar-cluster-k3d`        | `feat(cluster): create k3d cluster monitoramento with Traefik` |
| `04.configurar-monitoramento` | `feat(monitoring): deploy full observability stack via Helm`   |
| `05.configurar-cnpg`          | `feat(pgsql): deploy CloudNativePG and create database`        |
| `06.configurar-redis`         | `feat(redis): deploy Redis with ServiceMonitor`                |
| `07.configurar-mongodb`       | `feat(mongodb): deploy MongoDB Community with ServiceMonitor`  |
| `08.configurar-ravendb`       | `feat(ravendb): deploy RavenDB with Ingress`                   |
| `09.atualizar-hosts`          | `chore(hosts): automate /etc/hosts entries for local ingress`  |

---

## Gotchas

- **Never commit a failing state.** If a pod is in `CrashLoopBackOff`, fix it first. Commits document working milestones, not broken ones.
- **Never use `git add .`** without reviewing `git status` first — build artefacts (`bin/`, `obj/`) and generated lock files can pollute the commit.
- **Scope is not the namespace.** Scope is the _project area_; a `feat(monitoring)` commit may touch files in `00.Infraestrutura/linux/` and `00.Infraestrutura/servicos/grafana/`.
- **Don't skip the verification step** just because the script printed no errors — check pod status or the actual resource with `kubectl`.
- **Breaking changes** (e.g., renaming a Helm release) must use `feat!` or include `BREAKING CHANGE:` in the footer so the history is searchable.
- **Do not amend commits** that have already been pushed. Create a new `fix:` commit instead.

---

## Troubleshooting

| Issue                               | Solution                                                                                                   |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `git status` shows unexpected files | Run `git diff --stat HEAD` to audit; add missing entries to `.gitignore`                                   |
| Commit message rejected by hook     | Fix the format — common mistakes: missing scope separator `:`, uppercase type                              |
| Need to undo last (unpushed) commit | `git reset --soft HEAD~1` — keeps files staged for re-commit                                               |
| Accidentally staged wrong file      | `git restore --staged <file>`                                                                              |
| Not sure which type to use          | Default to `chore` for infrastructure/tooling; use `feat` only when a new user-visible capability is added |

---

## References

- [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
- [git-commit skill](../git-commit/SKILL.md) — for executing individual commits interactively
- [conventional-commit skill](../conventional-commit/SKILL.md) — message format reference
