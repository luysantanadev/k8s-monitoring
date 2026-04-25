# INC005 — RavenDB CrashLoopBackOff: binary path changed in latest image

**Tags:** `#ravendb` `#statefulset` `#crashloopbackoff` `#image`
**Date:** 2026-04-25
**Status:** Resolved

---

## Symptom

After running `instalar.ps1`, all 3 RavenDB pods (`ravendb-0/1/2`) entered `CrashLoopBackOff` immediately on startup. No previous restarts before the crash.

```
kubectl get pods -n ravendb
NAME        READY   STATUS             RESTARTS
ravendb-0   0/1     CrashLoopBackOff   3
ravendb-1   0/1     CrashLoopBackOff   3
ravendb-2   0/1     CrashLoopBackOff   3
```

---

## Diagnosis

```bash
kubectl logs ravendb-0 -n ravendb --previous
# Output:
# /bin/sh: 1: exec: /opt/RavenDB/Server/Raven.Server: not found
```

A probe pod was used to locate the correct binary path inside the current image:

```bash
kubectl run ravendb-probe --image=ravendb/ravendb:latest --restart=Never -- sleep 3600
kubectl exec ravendb-probe -- find / -name "Raven.Server" -type f 2>/dev/null
# Output:
# /usr/lib/ravendb/server/Raven.Server
```

---

## Root Cause

The `ravendb/ravendb:latest` image changed its installation layout in a recent update. The server binary moved from:

- **Old (broken):** `/opt/RavenDB/Server/Raven.Server`
- **New (correct):** `/usr/lib/ravendb/server/Raven.Server`

Both `instalar.ps1` and `instalar.sh` had the old path hardcoded in the StatefulSet container command.

---

## Fix

Updated the `command` field in the StatefulSet spec in both scripts:

**`instalar.ps1`** (PowerShell heredoc — backtick escapes `$HOSTNAME`):
```yaml
command:
  - /bin/sh
  - -c
  - exec /usr/lib/ravendb/server/Raven.Server --config-path /config/`$HOSTNAME
```

**`instalar.sh`** (Bash heredoc with `<<'EOF'` — single-quote prevents expansion):
```yaml
command:
  - /bin/sh
  - -c
  - exec /usr/lib/ravendb/server/Raven.Server --config-path /config/$HOSTNAME
```

---

## Lessons Learned

- Never pin to a floating tag like `latest` for stateful services without testing path assumptions after image updates.
- When diagnosing `CrashLoopBackOff`, always check `kubectl logs <pod> --previous` first — the exact error message usually points directly to the root cause.
- `.sh` files may be excluded by `.gitignore`/`files.exclude`; use `includeIgnoredFiles: true` in `grep_search` to find matches in them.
- PowerShell heredoc (`@"..."@`) requires backtick to escape `$HOSTNAME` → `` `$HOSTNAME ``. Bash `<<'EOF'` heredoc does not expand variables, so no escaping needed.
