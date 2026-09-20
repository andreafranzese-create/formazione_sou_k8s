# Check Deployment Best Practices

Script che, autenticandosi con un **Service Account di sola lettura** (`cluster-reader`) tramite server, token e certificato CA espliciti, esporta il Deployment dell'applicazione Flask installata nello Step 4 e ne verifica la conformità ad alcune best practice Kubernetes: presenza di **Readiness/Liveness Probe** e di **Requests/Limits**.

## RBAC – Service Account `cluster-reader`

Il file `cluster-reader-serviceaccount` applica il principio del **least privilege**: l'identità usata per l'export può **solo leggere** i Deployment, niente scrittura né accesso ad altre risorse.

Definisce tre oggetti:

- **ServiceAccount** `cluster-reader` (namespace `formazione-sou`): l'identità con cui ci si autentica.
- **ClusterRole** `cluster-reader`: concede `get`, `list`, `watch` sulle risorse `deployments` dell'apiGroup `apps`.
- **ClusterRoleBinding** `cluster-reader-binding`: lega il ServiceAccount al ClusterRole.

### ClusterRole vs Role

Si è scelto un **ClusterRole** (con ClusterRoleBinding) e non un Role di namespace: così il Service Account è un vero "reader" a livello di cluster e la stessa identità può leggere Deployment anche in altri namespace, se in futuro servisse.

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

  I tre flag coprono tre esigenze diverse:

  - `--raw` restituisce i dati sensibili in chiaro; senza di esso kubectl li maschera con `DATA+OMITTED` e il file risultante è inutilizzabile.
  - `--minify` limita l'output al cluster del context corrente, per cui `.clusters[]` contiene un solo elemento.
  - `--flatten` converte in dati inline gli eventuali riferimenti a file esterni. Nel kubeconfig il certificato può comparire come path su disco (`certificate-authority`) oppure come base64 embedded (`certificate-authority-data`): `--flatten` normalizza il primo caso nel secondo, così il comando funziona con entrambe le forme.

## Script export.sh

```bash
#!/usr/bin/env bash

check_campi() {
    campo="$1"
    etichetta="$2"
    container=$(jq -r "[.spec.template.spec.containers[] | select($campo == null) | .name] | join(\", \")" "$FILE")

    if [[ -n "$container" ]]; then
        errori+=("$etichetta nei container: $container")
    fi
}

checks=( ".readinessProbe readinessProbe" ".livenessProbe livenessProbe" ".resources.limits limits" ".resources.requests requests" )
errori=()

FILE=export.json
TOKEN=$(kubectl create token cluster-reader -n formazione-sou)
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[].cluster.server}')
CA="./ca.crt"

kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 --decode > ca.crt

if kubectl --token="$TOKEN" --server="$SERVER" --certificate-authority="$CA" get deployment flask-app -n formazione-sou -o json > "$FILE"; then
    echo "Export eseguito con successo"
else
    echo "Errore, export non riuscito"
    exit 1
fi

for i in "${checks[@]}"; do
    check_campi $i
done

if [ ${#errori[@]} -eq 0 ]; then
    echo "Tutti gli attributi sono presenti"
else
    echo "Non è presente l'attributo:"
    for e in "${errori[@]}"; do
        echo "- $e"
    done
    exit 2
fi
```

Logica:

1. Genera un token per il Service Account `cluster-reader`, e recupera server e CA dal kubeconfig attivo.
2. Esegue l'export del Deployment `flask-app` in `export.json` (formato **JSON**, necessario per l'analisi con `jq`), autenticandosi esplicitamente con token, server e CA. Se l'export fallisce lo script termina subito con exit code `1`: senza il file non c'è niente da verificare.
3. L'array `checks` elenca i controlli da eseguire, una riga per controllo con i due argomenti da passare alla funzione (campo jq ed etichetta per i messaggi). Il ciclo `for` li scorre e invoca `check_campi` su ciascuno: `$i` viene passato **senza virgolette** in modo che bash lo divida sugli spazi nei due argomenti attesi.
4. `check_campi` individua i container a cui il campo manca e, se ce n'è almeno uno, registra una voce nell'array `errori`. Non interrompe l'esecuzione: tutti e quattro i controlli vengono eseguiti sempre.
5. Alla fine, il numero di elementi in `errori` decide l'esito: array vuoto significa Deployment conforme, altrimenti viene stampato l'elenco delle voci raccolte e lo script esce con `2`.

### Il comando jq

```bash
container=$(jq -r "[.spec.template.spec.containers[] | select($campo == null) | .name] | join(\", \")" "$FILE")
```

- **`jq`** interroga il JSON: legge un file, gli applica un filtro, stampa il risultato.
- **`-r`** (*raw output*) stampa le stringhe senza le virgolette JSON. Senza il flag il risultato sarebbe `"flask-app"` con gli apici, che finirebbero nel messaggio di errore.
- **`"$FILE"`** è il file da leggere, cioè `export.json`.
- Il **filtro** è racchiuso in doppi apici, necessari perché bash possa espandere `$campo` (con gli apici singoli arriverebbe a jq la stringa letterale `$campo`). Le virgolette interne di `join(", ")` vanno quindi protette con il backslash, altrimenti bash chiuderebbe la stringa in anticipo; i backslash vengono rimossi da bash e jq riceve il filtro pulito.

**1. `.spec.template.spec.containers[]`** scende nel JSON seguendo le chiavi e, con `[]`, apre l'array estraendone gli elementi uno per uno. Non produce una lista ma uno *stream*: due valori distinti, che i filtri successivi riceveranno uno alla volta.

```
{ "name": "flask-app", "livenessProbe": {...} }
{ "name": "container" }
```

**2. `select($campo == null)`** filtra lo stream, lasciando passare solo gli elementi che soddisfano la condizione e scartando gli altri. Non trasforma i valori: quello che passa esce identico a come è entrato. Il primo container ha la probe, quindi la condizione è falsa e viene scartato; il secondo non ce l'ha, jq restituisce `null` per la chiave assente, la condizione è vera e passa.

```
{ "name": "container" }
```

**3. `.name`** estrae il nome da ciò che è rimasto.

```
"container"
```

**4. Le parentesi quadre** attorno al filtro raccolgono lo stream in un array — `["sidecar-proxy"]` — e **`join(", ")`** lo converte in una stringa unica, inserendo il separatore solo *tra* gli elementi:

```
container
```

Il `join` ha a due funzioni. La prima è produrre testo inseribile in una frase: senza di esso jq stamperebbe l'array in forma JSON, su più righe e con parentesi e virgolette. La seconda, più importante, riguarda il caso in cui tutti i container hanno il campo: `select` scarta tutto, l'array è vuoto, e `join` su un array vuoto restituisce la **stringa vuota**. Senza `join`, jq stamperebbe `[]` — due caratteri, quindi una stringa non vuota — e il test `[[ -n "$container" ]]` risulterebbe vero anche quando non manca niente, segnalando come mancanti tutti gli attributi.

### L'array `errori` e il controllo finale

```bash
errori=()
```

`errori` viene inizializzato come **array vuoto** prima dei controlli e fa da accumulatore: ogni volta che `check_campi` trova un attributo mancante ci aggiunge una voce con `+=`, indicando anche i container interessati.

```bash
errori+=("$etichetta nei container: $container")
```

L'esito finale si decide contando gli elementi accumulati:

```bash
if [ ${#errori[@]} -eq 0 ]; then
```

- `${...}` espande la variabile
- `#` chiede la **quantità** invece del contenuto
- `[@]` indica **tutti** gli elementi dell'array

`${#errori[@]}` è quindi il numero di elementi raccolti. Se è `0` nessun controllo ha registrato problemi e il Deployment è conforme; altrimenti un ciclo stampa le voci raccolte, una per riga, e lo script esce con `2`.

### Esempio di output

Deployment non conforme:

```
Export eseguito con successo
Non è presente l'attributo:
- limits nei container: flask-app
- requests nei container: flask-app
```

Deployment conforme:

```
Export eseguito con successo
Tutti gli attributi sono presenti
```

### Codici di uscita

| Exit code | Significato |
|-----------|-------------|
| `0` | Tutti gli attributi presenti in tutti i container (Deployment conforme). |
| `1` | Export non riuscito (Deployment non trovato o permessi insufficienti). |
| `2` | Almeno un attributo mancante; l'elenco completo è nell'output. |