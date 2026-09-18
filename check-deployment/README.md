# Check Deployment Best Practices

Script che, autenticandosi con un **Service Account di sola lettura** (`cluster-reader`) tramite server, token e certificato CA espliciti, esporta il Deployment dell'applicazione Flask installata nello Step 4 e ne verifica la conformità ad alcune best practice Kubernetes: presenza di **Readiness/Liveness Probe** e di **Requests/Limits (CPU e memory)**.

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

### Autenticazione esplicita (server, token, CA)

Lo script non si affida al kubeconfig locale per l'identità (context/user), ma costruisce esplicitamente le tre credenziali richieste da `kubectl`, così da poter usare le sole credenziali del Service Account `cluster-reader`:

- **Token**: ottenuto con la TokenRequest API, a scadenza:
  ```sh
  kubectl create token cluster-reader -n formazione-sou
  ```

- **Server**: è l'indirizzo (URL) dell'API server Kubernetes a cui `kubectl` deve connettersi — senza specificarlo, `kubectl` non saprebbe *a quale cluster* inviare le richieste. Viene recuperato dal kubeconfig già attivo (serve solo per sapere *dove* contattare l'API, non per l'identità con cui ci si autentica):
  ```sh
  kubectl config view --minify -o jsonpath='{.clusters[].cluster.server}'
  ```
  `--minify` limita l'output al solo cluster del context corrente, evitando di concatenare più server se il kubeconfig ne contiene diversi.

- **Certificate Authority**: è il certificato che permette a `kubectl` di **verificare l'identità** dell'API server durante l'handshake TLS, cioè di controllare che il certificato presentato dal server sia firmato da una CA fidata e non stia parlando con un endpoint fasullo (protezione da attacchi man-in-the-middle). Senza specificarlo, kubectl rifiuta la connessione HTTPS con errore di certificato non verificato. Viene estratto e decodificato dallo stesso kubeconfig, e salvato su file:

  ```sh
  kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 --decode > ca.crt
  ```

  `--raw` è necessario perché senza di esso kubectl non restituisce i dati sensibili come `certificate-authority-data`.

Queste tre credenziali vengono poi passate direttamente sulla riga di comando (`--token`, `--server`, `--certificate-authority`), senza scrivere un context permanente nel kubeconfig.

## Script export.sh

```bash
#!/usr/bin/env bash

FILE=export.json
TOKEN=$(kubectl create token cluster-reader -n formazione-sou)
CA="./ca.crt"
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[].cluster.server}')

kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 --decode > ca.crt

if kubectl --token="$TOKEN" --server="$SERVER" --certificate-authority="$CA" get deployment flask-app -n formazione-sou -o json > "$FILE"; then
    echo "Export eseguito con successo"
else
    echo "Errore, export non riuscito"
    exit 1
fi

check_campi() {
    local campo="$1"
    local etichetta="$2"
    local exit_code="$3"

    if jq -e "[.spec.template.spec.containers[] | $campo] | any(. == null)" "$FILE" > /dev/null; then
        echo "Errore, manca $etichetta in almeno un container"
        exit "$exit_code"
    fi
}

check_campi ".readinessProbe" "la readinessProbe" 2
check_campi ".livenessProbe" "la livenessProbe" 3
check_campi ".resources.limits.cpu" "i limits cpu" 4
check_campi ".resources.limits.memory" "i limits memory" 5
check_campi ".resources.requests.cpu" "i requests cpu" 6
check_campi ".resources.requests.memory" "i requests memory" 7

echo "Tutti gli attributi sono presenti"
```

Logica:
1. Genera un token per il Service Account `cluster-reader`, e recupera server e CA dal kubeconfig attivo.
2. Esegue l'export del Deployment `flask-app` in `export.json` (formato **JSON**, necessario per l'analisi con `jq`), autenticandosi esplicitamente con token, server e CA.
3. La funzione `check_campi` verifica, per un dato campo, che **tutti** i container del Deployment lo abbiano valorizzato: raccoglie il valore del campo per ogni container in un array e controlla se **almeno uno** è `null` (campo mancante).
4. Vengono controllati in sequenza: `readinessProbe`, `livenessProbe`, `limits.cpu`, `limits.memory`, `requests.cpu`, `requests.memory`; al primo campo mancante in almeno un container, stampa l'errore e termina con un exit code dedicato.

### Codici di uscita

| Exit code | Significato |
|-----------|-------------|
| `0` | Tutti gli attributi presenti in tutti i container (Deployment conforme). |
| `1` | Export non riuscito (Deployment non trovato o permessi insufficienti). |
| `2` | Manca la `readinessProbe` in almeno un container. |
| `3` | Manca la `livenessProbe` in almeno un container. |
| `4` | Manca il `limits.cpu` in almeno un container. |
| `5` | Manca il `limits.memory` in almeno un container. |
| `6` | Manca il `requests.cpu` in almeno un container. |
| `7` | Manca il `requests.memory` in almeno un container. |