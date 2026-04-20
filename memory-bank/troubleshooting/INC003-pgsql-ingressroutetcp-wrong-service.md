# INC003 — PostgreSQL: IngressRouteTCP aponta para serviço inexistente

**Tags**: `#postgresql` `#traefik` `#ingressroutetcp` `#cnpg` `#networking`
**Componente**: PostgreSQL (CloudNativePG) / Traefik  
**Data**: 2026-04-20  
**Status**: Resolvido

---

## Sintomas

- **DataGrip**: `SSL error: remote host terminated the handshake` ao conectar em `localhost:5432`
- **Aplicação .NET**: timeout na conexão com `PG_HOST=localhost` em debug local
- Internamente no cluster, `pgsql-cluster-rw.pgsql.svc.cluster.local:5432` funciona normalmente

## Diagnóstico

```bash
# Serviços existentes no namespace pgsql
kubectl get svc -n pgsql
# NAME               TYPE        CLUSTER-IP
# pgsql-cluster-r    ClusterIP   10.43.29.90
# pgsql-cluster-ro   ClusterIP   10.43.171.19
# pgsql-cluster-rw   ClusterIP   10.43.3.174

# IngressRouteTCP configurado
kubectl get ingressroutetcp -n pgsql pgsql -o jsonpath='{.spec.routes[0].services[0].name}'
# pgsql-rw   <-- serviço não existe!
```

## Causa Raiz

O CloudNativePG Helm chart (`cnpg/cluster`) cria serviços com o padrão `<release>-cluster-rw` (ex: `pgsql-cluster-rw`).

O `instalar.sh` / `instalar.ps1` aplicavam um `IngressRouteTCP` apontando para `pgsql-rw` (sem o sufixo `-cluster-`), que **não existe**. O Traefik não encontra o backend, encerra o TCP handshake abruptamente — o que clientes interpretam como falha de SSL/TLS.

> **Nota**: O `pg_hba.conf` aceita conexões sem SSL (`host ... scram-sha-256`), portanto o erro não é de SSL no servidor — é a queda da conexão TCP que o DataGrip confunde com "SSL error".

## Resolução

```bash
# Patch ao vivo
kubectl patch ingressroutetcp -n pgsql pgsql \
  --type='json' \
  -p='[{"op":"replace","path":"/spec/routes/0/services/0/name","value":"pgsql-cluster-rw"}]'
```

Verificação:

```bash
# Testar via pod temporário dentro do cluster
kubectl run pg-test --rm -it --restart=Never --image=postgres:16 -n default -- \
  psql "postgresql://workshop:Workshop123pgsql@pgsql-cluster-rw.pgsql.svc.cluster.local:5432/workshop?sslmode=disable" \
  -c "SELECT version();"
# PostgreSQL 16.13 ... 64-bit
```

## Prevenção

Scripts `instalar.sh` e `instalar.ps1` corrigidos — o IngressRouteTCP agora referencia `pgsql-cluster-rw`.

Arquivos modificados:

- `00.Infraestrutura/servicos/pgsql/instalar.sh`
- `00.Infraestrutura/servicos/pgsql/instalar.ps1`

## Configuração de conexão local (`.env`)

```env
PG_HOST=localhost
PG_PORT=5432
PG_DATABASE=workshop
PG_USER=workshop
PG_PASSWD=Workshop123pgsql
```

O `SslMode.Disable` no `DatabaseExtensions.cs` está correto — PostgreSQL aceita conexões sem TLS para usuários normais via `host ... scram-sha-256`.
