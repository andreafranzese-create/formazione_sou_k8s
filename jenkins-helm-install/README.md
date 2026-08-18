# Helm Install con Jenkins

Deploy automatizzato del chart Helm `flask-app` su un cluster Kubernetes locale tramite una pipeline **dichiarativa** di Jenkins, che preleva il chart versionato su GitHub nel repository `formazione_sou_k8s` ed esegue l'`helm install` sul namespace `formazione-sou`.

## Configurazione RBAC – accesso di Jenkins al namespace

Il file `jenkins-serviceaccount` definisce tre risorse nel namespace `formazione-sou`:

- **ServiceAccount** `jenkins-service`: l'identità con cui gira il Pod-agent di Jenkins.
- **Role** `jenkins-service-role`: i permessi sul namespace.
- **RoleBinding** `jenkins-service-binding`: lega il ServiceAccount al Role.

Applicazione dei manifest:

```sh
kubectl apply -f jenkins-serviceaccount
```

### Perché serve

Gli agent di Jenkins vengono avviati come Pod nel cluster. Impostando `serviceAccountName: jenkins-service`, il Pod eredita i permessi del ServiceAccount e può quindi eseguire `helm`/`kubectl` sul namespace `formazione-sou` senza dover gestire kubeconfig o credenziali esterne: l'autenticazione avviene tramite il token del ServiceAccount montato automaticamente nel Pod.

## Pipeline dichiarativa Jenkins

Il `Jenkinsfile` definisce una pipeline che:

- avvia un **agent Kubernetes** (un Pod effimero nel cluster) con il ServiceAccount `jenkins-service`;
- usa il container `dtzar/helm-kubectl`, che include già `helm` e `kubectl`;
- esegue il deploy con `helm upgrade --install`.

```groovy
pipeline {
  agent {
    kubernetes {
      yaml '''
        apiVersion: v1
        kind: Pod
        spec:
          serviceAccountName: jenkins-service
          containers:
          - name: helm
            image: dtzar/helm-kubectl:latest
            command: ["sleep"]
            args: ["99d"]
      '''
      defaultContainer 'helm'
    }
  }
  stages {
    stage('Deploy') {
      steps {
        sh 'helm upgrade --install flask-app charts/flask-app -n formazione-sou'
      }
    }
  }
}
```

Dettagli:

- `helm upgrade --install flask-app` installa il release `flask-app` se non esiste, altrimenti lo aggiorna: rende la pipeline **idempotente** e rieseguibile.
- `charts/flask-app` è il percorso del chart all'interno del repository clonato da Jenkins.
- `-n formazione-sou` indirizza il deploy sul namespace corretto.

## Configurazione del Cloud Kubernetes su Jenkins

Jenkins **non** usa un agent statico/fisso: è configurato con un **Cloud di tipo Kubernetes**, per cui gli agent vengono creati **on-demand** come Pod effimeri nel cluster e distrutti a fine build. Per questo la pipeline definisce l'agent inline nel blocco `agent { kubernetes { ... } }` del `Jenkinsfile`, invece di puntare a un nodo preconfigurato.

Per autorizzare Jenkins a parlare con l'API del cluster è stato fornito sito il token del ServiceAccount come credenziale:

1. Recupera il token del ServiceAccount `jenkins-service` (Secret text):

   ```sh
   kubectl -n formazione-sou create token jenkins-service
   ```

   *(oppure, su versioni che generano il Secret automaticamente, leggilo con `kubectl -n formazione-sou get secret <nome-secret> -o jsonpath='{.data.token}' | base64 -d`)*

2. In **Manage Jenkins → Credentials**, aggiungi una credenziale di tipo **Secret text** incollando il token, e assegnale un ID.
3. In **Manage Jenkins → Clouds → Kubernetes**, configura il Cloud usando quella credenziale come **Kubernetes service account credential** (o Credentials) per l'autenticazione verso l'API server, insieme all'URL del cluster.

In questo modo il Cloud è autorizzato a creare i Pod-agent e il Pod, girando con `serviceAccountName: jenkins-service`, ha i permessi RBAC sul namespace `formazione-sou`.