# Check Deployment Best Practices

Script che, autenticandosi con un **Service Account di sola lettura** (`cluster-reader`), esporta il Deployment dell'applicazione Flask installata nello Step 4 e ne verifica la conformità ad alcune best practice Kubernetes: presenza di **Readiness/Liveness Probe** e di **Requests/Limits**. Se uno di questi attributi manca, lo script termina con un **codice di errore** dedicato.

## RBAC – Service Account `cluster-reader`

Il file `cluster-reader-serviceaccount` applica il principio del **least privilege**: l'identità usata per l'export può **solo leggere** i Deployment, niente scrittura né accesso ad altre risorse.

Definisce tre oggetti:

- **ServiceAccount** `cluster-reader` (namespace `formazione-sou`): l'identità con cui ci si autentica.
- **ClusterRole** `cluster-reader`: concede `get`, `list`, `watch` sulle risorse `deployments` dell'apiGroup `apps`.
- **ClusterRoleBinding** `cluster-reader-binding`: lega il ServiceAccount al ClusterRole.

```sh
kubectl apply -f cluster-reader-serviceaccount
```

### ClusterRole vs Role

Si è scelto un **ClusterRole** (con ClusterRoleBinding) e non un Role di namespace: così il Service Account è un vero "reader" a livello di cluster e la stessa identità può leggere Deployment anche in altri namespace, se in futuro servisse. Per limitare la lettura al solo `formazione-sou` sarebbe sufficiente sostituire ClusterRole/ClusterRoleBinding con Role/RoleBinding nello stesso namespace.

### Token

Lo script ottiene un token **temporaneo** del Service Account con:

```sh
kubectl create token cluster-reader -n formazione-sou
```

È il metodo consigliato (TokenRequest API, K8s ≥ 1.24): il token è a scadenza e non viene persistito. Su cluster più vecchi si può invece leggere il token dal Secret associato al Service Account.

## Script export.sh

```bash
#!/usr/bin/env bash

FILE=export.yaml
TOKEN=$(kubectl create token cluster-reader -n formazione-sou)

if kubectl --token="$TOKEN" get deployment flask-app -n formazione-sou -o yaml > "$FILE"; then
    echo "Export eseguito con successo"
else
    echo "Errore, export non riuscito"
    exit 1
fi

if ! grep -q "readinessProbe" "$FILE"; then
    echo "Errore, non è presente la readinessProbe" 
    exit 2
fi

if ! grep -q "livenessProbe" "$FILE"; then
    echo "Errore, non è presente la livenessProbe" 
    exit 3
fi

if ! grep -q "limits" "$FILE"; then
    echo "Errore, non sono presenti i limits"
    exit 4
fi

if ! grep -q "requests" "$FILE"; then
    echo "Errore, non sono presenti i requests" 
    exit 5
fi

echo "Tutti gli attributi sono presenti"
```

Logica:
1. Genera un token per il Service Account `cluster-reader`.
2. Esegue l'export del Deployment `flask-app` in `export.yaml`, autenticandosi con quel token.
3. Verifica in sequenza la presenza di `readinessProbe`, `livenessProbe`, `limits`, `requests`; al primo mancante stampa l'errore e termina con un exit code dedicato.

### Codici di uscita

| Exit code | Significato |
|-----------|-------------|
| `0` | Tutti gli attributi presenti (Deployment conforme). |
| `1` | Export non riuscito (Deployment non trovato o permessi insufficienti). |
| `2` | Manca la `readinessProbe`. |
| `3` | Manca la `livenessProbe`. |
| `4` | Mancano i `limits`. |
| `5` | Mancano i `requests`. |