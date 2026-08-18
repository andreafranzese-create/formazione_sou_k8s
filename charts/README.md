# Helm Chart (`flask-app`)

Il chart permette di specificare **in input il tag dell'immagine** da rilasciare, così da poter deployare di volta in volta la versione desiderata prodotta dalla pipeline.

## Struttura

```
charts/
└── flask-app/
    ├── Chart.yaml            # metadati del chart + dipendenza ingress-nginx
    ├── Chart.lock            # lock delle dipendenze
    ├── values.yaml           # valori di default (immagine, tag, repliche, ingress, service...)
    ├── .helmignore
    ├── charts/
    │   └── ingress-nginx-4.11.3.tgz   # dipendenza scaricata (helm dependency)
    └── templates/
        ├── _helpers.tpl      # helper per nomi e label
        ├── deployment.yaml   # Deployment dell'app Flask
        ├── service.yaml      # Service ClusterIP
        ├── ingress.yaml      # Ingress (host formazionesou.local)
        └── NOTES.txt         # note mostrate dopo l'install
```

## Componenti deployati

- **Deployment** `flask-app` con `2` repliche e strategia `RollingUpdate` (`maxSurge: 1`, `maxUnavailable: 0`), readiness/liveness probe su `/` e resource requests/limits.
- **Service** `service-flask-app` di tipo `ClusterIP` che espone la porta `80` verso la `targetPort 5000` del container.
- **Ingress** con `ingressClassName: nginx` e host `formazionesou.local`.
- **Dipendenza `ingress-nginx`** (v4.11.3) installata insieme al chart 


## Dipendenze

La dipendenza `ingress-nginx` è dichiarata in `Chart.yaml`. Per scaricarla/aggiornarla:

```bash
helm dependency update charts/flask-app
```

## Deploy

### Deploy con i valori di default

Dalla root della repo `formazione_sou_k8s`:

```bash
helm install flask-app ./charts/flask-app
```

Con i default viene rilasciata l'immagine `andry67/helloworld:latest`.

### Deploy specificando il tag dell'immagine (requisito Step 3)

Il tag dell'immagine prodotta dalla pipeline si passa **in input** tramite `containers.tag`:

```bash
helm install flask-app ./charts/flask-app --set containers.tag=<TAG_DA_RILASCIARE>
```

Esempio, per rilasciare il tag `v1.2.0`:

```bash
helm install flask-app ./charts/flask-app --set containers.tag=v1.2.0
```

### Aggiornare il rilascio con un nuovo tag

Per rilasciare una nuova versione dell'immagine su un deploy già esistente:

```bash
helm upgrade flask-app ./charts/flask-app --set containers.tag=<NUOVO_TAG>
```

Comando comodo che installa se assente o aggiorna se presente:

```bash
helm upgrade --install flask-app ./charts/flask-app --set containers.tag=<TAG>
```

## Verifica del deploy

```bash
# stato del rilascio
helm status flask-app

# pod dell'applicazione
kubectl get pods -l app=flask-app

# service e ingress
kubectl get svc,ingress
```

Per accedere all'app tramite Ingress, aggiungi l'host al tuo `/etc/hosts` puntando all'IP dell'ingress controller:

```
<IP_INGRESS>   formazionesou.local
```

Il nodo minikube gira in modo isolato sull'host(driver Docker), con una propria rete interna. Di conseguenza l'host `formazionesou.local` **non è raggiungibile direttamente** dalla macchina, è **necessario** fare il port-forward del controller `ingress-nginx`:

```bash
   kubectl port-forward svc/flask-app-ingress-nginx-controller 8080:80
```

e poi apri `http://formazionesou.local/`

## Parametri configurabili (`values.yaml`)

| Parametro | Descrizione | Default |
|---|---|---|
| `name` | Nome delle risorse (Deployment/Ingress) | `flask-app` |
| `replicas` | Numero di repliche | `2` |
| `LabelKey` / `LabelValue` | Label usate da selector e service | `app` / `flask-app` |
| `strategy.type` | Strategia di deploy | `RollingUpdate` |
| `strategy.rollingUpdate.maxSurge` | Pod extra durante il rollout | `1` |
| `strategy.rollingUpdate.maxUnavailable` | Pod non disponibili durante il rollout | `0` |
| `containers.image` | Repository dell'immagine | `andry67/helloworld` |
| **`containers.tag`** | **Tag dell'immagine da rilasciare (input)** | `latest` |
| `containers.imagePullPolicy` | Pull policy | `IfNotPresent` |
| `containers.port` | Porta del container | `5000` |
| `containers.resources.requests` | CPU/Memory richieste | `100m` / `128Mi` |
| `containers.resources.limits` | CPU/Memory massime | `500m` / `256Mi` |
| `containers.readinessProbe` / `livenessProbe` | Probe HTTP su `/` | — |
| `Ingress.IngressClassName` | Ingress class | `nginx` |
| `Ingress.host` | Host dell'Ingress | `formazionesou.local` |
| `Ingress.path` / `Ingress.pathType` | Path e tipo | `/` / `Prefix` |
| `ClusterIP.name` | Nome del Service | `service-flask-app` |
| `ClusterIP.servicePort` / `ClusterIP.targetPort` | Porta service / porta container | `80` / `5000` |
| `ingress-nginx.enabled` | Installa la dipendenza ingress-nginx | `true` |
