# INC004 — RavenDB: Helm chart incompatível com modo não-seguro + repo URL morta

**Status:** Resolved  
**Component:** RavenDB / Helm  
**Tags:** `#ravendb` `#helm` `#install-order`  
**Detected:** 2026-04-20  
**Resolved:** 2026-04-20

---

## Sintoma

Script `instalar.sh` saía com código 1 imediatamente:

```
Error: looks like "https://ravendb.github.io/helm-charts" is not a valid chart repository
or cannot be reached: failed to fetch https://ravendb.github.io/helm-charts/index.yaml : 404 Not Found
```

Após corrigir a URL do repo, o `helm upgrade --install` falhava silenciosamente porque o chart
`ravendb/ravendb-cluster` v2.1.0 exige:

- Setup Package (ZIP gerado pela ferramenta `rvn`)
- Certificados TLS
- Licença RavenDB

Todos incompatíveis com `Setup.Mode=None` e `Security.UnsecuredAccessAllowed=PublicNetwork` do workshop.

---

## Diagnóstico

```bash
# URL morta:
curl -sI https://ravendb.github.io/helm-charts/index.yaml
# HTTP 404

# URL correta (com /charts):
helm repo add ravendb https://ravendb.github.io/helm-charts/charts --force-update
helm show values ravendb/ravendb-cluster
# values exige: nodeTags, domain, email, setupMode=LetsEncrypt, license, package (ZIP)
# → chart requer TLS/setup package, não suporta modo None diretamente

# ArtifactHub — chart encontrado:
helm search hub ravendb
# ravendb-cluster v2.1.0 app 7.2
```

---

## Causa Raiz

Dois problemas independentes:

1. **URL do Helm repo estava errada**: `https://ravendb.github.io/helm-charts` não tem `index.yaml`.
   A URL correta é `https://ravendb.github.io/helm-charts/charts` (subdiretório `/charts`).

2. **Chart oficial incompatível com modo não-seguro**: `ravendb/ravendb-cluster` é projetado para
   clusters seguros com TLS. Requer setup package ZIP gerado pelo `rvn`, certificados e licença.
   O `values.yaml` do projeto usa estrutura de env vars (`ravendb.settings.*`) que não existe
   neste chart — é documentação desatualizada/alternativa.

---

## Resolução

Substituir o Helm chart por StatefulSet direto com a imagem oficial `ravendb/ravendb:latest`,
configurada via variáveis de ambiente para modo não-seguro:

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ravendb
  namespace: ravendb
spec:
  serviceName: ravendb
  replicas: 1
  selector:
    matchLabels:
      app: ravendb
  template:
    metadata:
      labels:
        app: ravendb
        app.kubernetes.io/instance: ravendb
    spec:
      containers:
        - name: ravendb
          image: ravendb/ravendb:latest
          env:
            - name: RAVEN_Security_UnsecuredAccessAllowed
              value: "PublicNetwork"
            - name: RAVEN_Setup_Mode
              value: "None"
          ports:
            - name: http
              containerPort: 8080
            - name: tcp
              containerPort: 38888
          readinessProbe:
            tcpSocket:
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 10
          volumeMounts:
            - name: data
              mountPath: /var/lib/ravendb/data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 2Gi
---
apiVersion: v1
kind: Service
metadata:
  name: ravendb
  namespace: ravendb
  labels:
    app.kubernetes.io/instance: ravendb
spec:
  selector:
    app: ravendb
  ports:
    - name: http
      port: 8080
    - name: tcp
      port: 38888
EOF
```

**Ponto de atenção — readinessProbe**: `/alive` retorna HTTP 400 no RavenDB v7.2.
Usar `tcpSocket` na porta 8080.

**Verificação:**

```bash
kubectl get pod -n ravendb
# NAME        READY   STATUS    RESTARTS   AGE
# ravendb-0   1/1     Running   0          ...

kubectl exec ravendb-0 -n ravendb -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/
# 302 (redireciona para /studio/index.html) — servidor OK
```

---

## Prevenção

- `instalar.sh` e `instalar.ps1` corrigidos: usam StatefulSet direto em vez de Helm chart.
- readinessProbe usa `tcpSocket:port:8080` (não httpGet `/alive`).
- Nota no script documenta incompatibilidade do chart para futuras referências.

---

## Arquivos Modificados

- [00.Infraestrutura/servicos/ravendb/instalar.sh](../../00.Infraestrutura/servicos/ravendb/instalar.sh)
- [00.Infraestrutura/servicos/ravendb/instalar.ps1](../../00.Infraestrutura/servicos/ravendb/instalar.ps1)
