# Troubleshooting Memory — Index

> Searchable registry of all known issues, root causes, and fixes.
> Before diagnosing any problem, search here first.
> After resolving any problem, record it here.

---

## How to Search

| You see...                                     | Look for tag             |
| ---------------------------------------------- | ------------------------ |
| Pod restarts, `FailedCreatePodSandBox`         | `#cni` `#k3d`            |
| StatefulSet `0/N ready`, `FailedCreate`        | `#statefulset`           |
| `serviceaccount "X" not found`                 | `#rbac` `#operator`      |
| Helm install failing with ownership error      | `#helm`                  |
| All pods restarting at the same time           | `#wsl2` `#k3d`           |
| Liveness/readiness probe failures on startup   | `#probe`                 |
| MongoDB not starting                           | `#mongodb`               |
| PostgreSQL `SSL error` / timeout via localhost | `#postgresql` `#traefik` |
| RavenDB helm 404 / chart exige TLS + licença   | `#ravendb` `#helm`       |

---

## Open

_(none)_

---

## Resolved

| ID                                                                 | Component            | Symptom (short)                                       | Root Cause (short)                                                                        | Resolved   |
| ------------------------------------------------------------------ | -------------------- | ----------------------------------------------------- | ----------------------------------------------------------------------------------------- | ---------- |
| [INC001](INC001-flannel-wsl2-restart.md)                           | k3d / CNI            | All pods restart in cascade after host reboot         | WSL2/Docker restart clears Flannel subnet.env                                             | 2026-04-20 |
| [INC002](INC002-mongodb-statefulset-orphan.md)                     | MongoDB              | StatefulSet `0/1` forever, `FailedCreate` loop        | manifest.yaml applied before operator install                                             | 2026-04-20 |
| [INC003](INC003-pgsql-ingressroutetcp-wrong-service.md)            | PostgreSQL / Traefik | `SSL error` no DataGrip, timeout na app via localhost | IngressRouteTCP apontava para `pgsql-rw` (inexistente) em vez de `pgsql-cluster-rw`       | 2026-04-20 |
| [INC004](INC004-ravendb-helm-chart-incompativel-modo-unsecured.md) | RavenDB / Helm       | `helm repo add` 404 + chart exige setup package TLS   | URL do repo errada (`/charts` faltando); chart oficial incompatível com `Setup.Mode=None` | 2026-04-20 |
| [INC005](INC005-ravendb-binary-path-changed.md)                    | RavenDB / StatefulSet | Todos os pods em `CrashLoopBackOff` imediatamente    | `ravendb/ravendb:latest` moveu binário de `/opt/RavenDB/` para `/usr/lib/ravendb/`        | 2026-04-25 |

---

## Recurring Patterns

- **WSL2 reboots** always cause a cascade restart wave (~3–6 restarts/pod). All pods recover automatically. No action needed.
- **Helm operators** must be installed **before** applying CRs/manifests that depend on them (ServiceAccounts, CRDs, webhooks).
