# Kubernetes Lab — Secret, Basic Auth e Ingress

### Creare il Secret con `--from-literal`

`--from-literal` passa le coppie `chiave=valore` da riga di comando; è
Kubernetes a codificarle in base64.

```bash
kubectl create secret generic db-cred \
  --from-literal=username=andrea \
  --from-literal=password='1234'
```

Guardando lo YAML si vede che i valori stanno nel campo `data:` **sono già in
base64**, non in chiaro:

```bash
kubectl get secret db-cred -o yaml
```

```yaml
apiVersion: v1
data:
  password: MTIzNA==
  username: YW5kcmVh
kind: Secret
metadata:
  creationTimestamp: "2026-08-19T07:41:26Z"
  name: db-cred
  namespace: default
  resourceVersion: "142179"
  uid: 42c51983-44a2-4794-a1ff-13ffe1a01520
type: Opaque   
```

### Esportare lo YAML, modificarlo e creare un nuovo Secret

Salviamo lo YAML su file:

```bash
kubectl get secret db-cred -o yaml > new-secret.yaml
```

Calcoliamo i base64 delle **nuove** credenziali:
```bash
echo -n 'gianfranco'      | base64      # nuovo username
echo -n 'password' | base64      # nuova password
```

Puliamo il file dai campi runtime (`creationTimestamp`, `resourceVersion`,
`uid`), cambiamo il `name` e sostituiamo i valori in `data:`

#### new-secret.yaml

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-cred-2
type: Opaque
data:
  username: Z2lhbmZyYW5jbw==
  password: cGFzc3dvcmQ=
```

Creiamo e verifichiamo decodificando:

```bash
kubectl apply -f new-secret.yaml
kubectl get secret db-cred-2 -o jsonpath='{.data.username}' | base64 -d ; echo
kubectl get secret db-cred-2 -o jsonpath='{.data.password}' | base64 -d ; echo
```

### Il Secret come variabili d'ambiente in un Pod

Il costrutto `ValueFrom.secretKeyRef` permette di iniettare come variabile d'ambiente il valore di una singola chiave del Secret, referenziandola per nome.

#### secret-env-pod.yaml

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secret-env-pod
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "sleep 9999"]
    env:
    - name: DB_USERNAME
      valueFrom:
        secretKeyRef:
          name: db-cred-2  
          key: username
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-cred-2
          key: password
```

Entrando nel Pod e facendo l'echo:

```bash
kubectl exec -it secret-env-pod -- sh
# dentro al Pod:
echo "utente: $DB_USERNAME"
echo "password: $DB_PASSWORD"
env | grep DB_
exit
```

### BONUS — Encryption at rest dei Secret

`base64` è **codifica**, non cifratura: si torna in chiaro con un `base64 -d`.
Di default un Secret finisce in **etcd** solo codificato base64 — chiunque abbia
accesso a etcd o a un suo backup lo legge. "Encryption at rest" significa cifrare
davvero quel dato prima che tocchi il disco.

**1) Cifratura nativa in etcd:**
L'API server può cifrare i Secret prima di scriverli in etcd tramite un file di
`EncryptionConfiguration` passato con `--encryption-provider-config`. Provider:

- `identity` — nessuna cifratura (default): solo base64;
- `aescbc` / `aesgcm` / `secretbox` — cifratura con **chiave locale** scritta nel
  file di config (la chiave sta sul control plane);
- `kms` — *envelope
  encryption*: le chiavi dati sono cifrate da una **KMS esterna** (AWS KMS, GCP
  KMS, Azure Key Vault, HashiCorp Vault via plugin).

**2) **Evitare i Secret in chiaro fuori dal cluster:** Non cifrano etcd, risolvono un problema complementare:

- **Sealed Secrets**: committi in Git un `SealedSecret` cifrato in modo
  asimmetrico; solo il controller nel cluster lo decifra.
- **External Secrets Operator (ESO)**: i secret veri stanno in Vault/AWS SM/GCP/
  Azure e vengono sincronizzati nel cluster.
- **SOPS** : cifra i file YAML.
- **Secrets Store CSI Driver**: monta i secret direttamente dal manager esterno.

---

## Nginx con HTTP Basic Auth

### File htpasswd → Secret

```bash
htpasswd -c -b .htpasswd andrea password123
```
`htpasswd` genera il file **utente:password_hashata** che Nginx usa per la `Basic Auth`: la password è salvata come hash, non in chiaro. -c crea il file, -b passa la password inline.

Dal file creiamo il Secret:

```bash
kubectl create secret generic nginx-htpasswd --from-file=.htpasswd
```

### Config di Nginx → ConfigMap

**`default.conf`**

```nginx
server {
    listen 80;
    server_name localhost;

    location / {
        auth_basic           "Area riservata";          
        auth_basic_user_file /etc/nginx/auth/.htpasswd; 
        root  /usr/share/nginx/html;
        index index.html;
    }
}
```

```bash
kubectl create configmap nginx-conf --from-file=default.conf
```

### Pod che monta il Secret + ConfigMap

**`nginx-auth-pod.yaml`**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-auth
  labels:
    app: nginx-auth
spec:
  containers:
  - name: nginx
    image: nginx:1.27
    ports:
    - containerPort: 80
    volumeMounts:
    - name: conf                      
      mountPath: /etc/nginx/conf.d
    - name: htpasswd                
      mountPath: /etc/nginx/auth
      readOnly: true
  volumes:
  - name: conf
    configMap:
      name: nginx-conf
  - name: htpasswd
    secret:
      secretName: nginx-htpasswd
```

### Test

```bash
kubectl apply -f nginx-auth-pod.yaml

```

poi in un terminale il port-forward:

```bash
kubectl port-forward pod/nginx-auth 8080:80
```

In un secondo terminale:

```bash
curl -i localhost:8080                         # 401 Unauthorized
curl -i -u andrea:password123 localhost:8080   # 200 OK
```

---

## Ingress /eng e /ita

### I due backend + Service

**`deployment-service.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-eng
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-eng 
  template:
    metadata:
      labels: 
        app: hello-eng
    spec:
      containers:
      - name: echo
        image: hashicorp/http-echo:1.0
        args: ["-text=Hello World", "-listen=:5678"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: hello-eng
spec:
  selector: 
    app: hello-eng 
  ports:
  - port: 5678
    targetPort: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-ita
spec:
  replicas: 1
  selector:
    matchLabels: 
      app: hello-ita
  template:
    metadata:
      labels: 
        app: hello-ita
    spec:
      containers:
      - name: echo
        image: hashicorp/http-echo:1.0
        args: ["-text=Ciao Mondo", "-listen=:5678"]
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: hello-ita
spec:
  selector: 
    app: hello-ita
  ports:
  - port: 5678
    targetPort: 5678
```

Questo file definisce i due "siti" da **instradare**, ciascuno composto da un `Deployment` e da un `Service`. Ogni Deployment crea un Pod con l'immagine **hashicorp/http-echo**, un echo server che risponde sempre con il testo passato in args (Hello World per l'inglese, Ciao Mondo per l'italiano) sulla porta 5678. Il selector/matchLabels con l'etichetta app collega il Service ai Pod giusti: hello-eng inoltra il traffico ai Pod etichettati `app: hello-eng`, hello-ita a quelli `app: hello-ita`. In questo modo otteniamo due endpoint stabili e distinti (i due Service) che l'Ingress potrà richiamare per nome

### L'Ingress con `pathType: Exact`

**`ingress.yaml`**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress
spec:
  ingressClassName: nginx
  rules:
  - host: lingue.local
    http:
      paths:
      - path: /eng
        pathType: Exact        
        backend:
          service:
            name: hello-eng
            port:
              number: 5678
      - path: /ita
        pathType: Exact       
        backend:
          service:
            name: hello-ita
            port:
              number: 5678
```

```bash
kubectl apply -f ingress.yaml
```

**Test:**

```bash
kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8080:80
# secondo terminale:
curl -i -H "Host: lingue.local" localhost:8080/eng     # -> Hello World (200)
curl -i -H "Host: lingue.local" localhost:8080/ita     # -> Ciao Mondo (200)
curl -i -H "Host: lingue.local" localhost:8080/ita/    # -> 404 
```

- `-n ingress-nginx` indica il namespace, cioè il "cassetto" del cluster dove vivono le risorse dell'Ingress controller.
- `ingress-nginx-controller` è il Service che espone i Pod del controller Nginx: è il componente che legge le regole degli oggetti Ingress e smista davvero il traffico. Si fa il port-forward perché è l'unico punto d'ingresso attraverso cui si testano le regole /eng e /ita.

### Perché funziona: `pathType`

Ogni regola di path ha `path` (la stringa) e `pathType` (come confrontarla con
l'URL). Tre valori:

- **`Exact`** — corrispondenza **identica**, carattere per carattere. `/ita`
  matcha solo `/ita`, **non** `/ita/` né `/ita/bar`.
- **`Prefix`** — prefisso **a segmenti** separati da `/`. `/ita` matcha `/ita`,
  `/ita/`, `/ita/libri`, ma **non** `/italiano`.
- **`ImplementationSpecific`** — decide il controller. Ingress-nginx tratta il
  `path` come **regex/location di Nginx**, per controllo fine.