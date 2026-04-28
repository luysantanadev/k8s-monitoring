# INC007 — CNPG webhook service sem endpoints na instalação do cluster

**Status:** Resolved  
**Component:** PostgreSQL / CloudNativePG  
**Tags:** `#postgresql` `#operator` `#helm` `#install-order`  
**Detected:** 2026-04-27  
**Resolved:** 2026-04-27

---

## Sintoma

```
Release "pgsql" does not exist. Installing it now.
Error: Internal error occurred: failed calling webhook "mcluster.cnpg.io": failed to call webhook:
Post "https://cnpg-webhook-service.cnpg-system.svc:443/mutate-postgresql-cnpg-io-v1-cluster?timeout=10s":
no endpoints available for service "cnpg-webhook-service"
```

O `helm upgrade --install pgsql cnpg/cluster` falha porque o admission webhook do operador CNPG ainda não tem endpoints disponíveis — o pod do operador subiu, mas o webhook ainda não registrou endpoints prontos.

---

## Diagnóstico

```bash
kubectl -n cnpg-system get pods
# operator pod estava em Running mas endpoints do webhook estavam vazios

kubectl -n cnpg-system get endpoints cnpg-webhook-service
# NAME                    ENDPOINTS   AGE
# cnpg-webhook-service    <none>      8s
```

---

## Causa Raiz

O `helm upgrade --install cnpg cnpg/cloudnative-pg` retorna imediatamente após o deploy do manifesto, **sem aguardar** que o pod do operador esteja pronto e que o webhook service tenha endpoints registrados. O script seguia imediatamente para instalar o chart `cnpg/cluster`, que aciona o admission webhook `mcluster.cnpg.io` — que ainda não estava pronto.

---

## Resolução

Adicionar `--wait --timeout 3m` ao helm install do operador para que o Helm aguarde todos os pods do operador estarem `Ready` antes de continuar:

```powershell
# instalar.ps1 — antes
helm upgrade --install cnpg cnpg/cloudnative-pg `
    --namespace cnpg-system --create-namespace

# instalar.ps1 — depois
helm upgrade --install cnpg cnpg/cloudnative-pg `
    --namespace cnpg-system --create-namespace `
    --wait --timeout 3m
```

```bash
# instalar.sh — antes
helm upgrade --install cnpg cnpg/cloudnative-pg \
    --namespace cnpg-system --create-namespace \
    || fail "Falha ao instalar CNPG operator."

# instalar.sh — depois
helm upgrade --install cnpg cnpg/cloudnative-pg \
    --namespace cnpg-system --create-namespace \
    --wait --timeout 3m \
    || fail "Falha ao instalar CNPG operator."
```

**Verificação:** re-executar o script completo → todos os steps devem completar com `OK`.

---

## Prevenção

Todo `helm upgrade --install` de um **operador com admission webhooks** deve incluir `--wait` (e um `--timeout` razoável) para garantir que os CRDs e o webhook service estejam prontos antes de instalar charts que dependem deles. Ver também INC002 (MongoDB) — mesmo padrão.

---

## Arquivos Modificados

- [00.Infraestrutura/servicos/05.pgsql/instalar.ps1](../../../00.Infraestrutura/servicos/05.pgsql/instalar.ps1)
- [00.Infraestrutura/servicos/05.pgsql/instalar.sh](../../../00.Infraestrutura/servicos/05.pgsql/instalar.sh)
