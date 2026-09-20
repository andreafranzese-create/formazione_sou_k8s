# Pipeline Jenkins: build & push di immagini su registry

Questa pipeline Jenkins costruisce un'immagine container a partire da una piccola app Flask e la pubblica su un registry Docker, assegnandole un tag calcolato automaticamente in base allo stato di Git. La build e il push usano **Podman**, e le credenziali del registry sono gestite tramite il credential store di Jenkins.

## Architettura

Il repository contiene tre pezzi che lavorano insieme:

- **L'applicazione** (`app.py`) — una minimale app Flask che risponde "hello world".
- **Il Dockerfile** — descrive come impacchettare l'app in un'immagine.
- **Il Jenkinsfile** — orchestra il calcolo del tag, la build e il push.

L'idea di fondo è che il **tag dell'immagine non è fisso**: viene derivato da Git, così ogni branch/tag produce un'immagine identificabile senza sovrascrivere quelle degli altri. La pipeline funziona con qualsiasi Dockerfile. L'app Flask è solo un esempio per mostrare il flusso completo

---

## Il Jenkinsfile

Il file è composto da due funzioni di supporto e dalla pipeline vera e propria.

### Funzione `determineTag()`

```groovy
def determineTag() {
  def tag = sh(script: 'git describe --tags --exact-match || true', returnStdout: true).trim()
  def branch = env.GIT_BRANCH.replaceAll('^origin/', '')
  def commitHash = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()

  if (tag) {
    return tag
  } else if (branch == 'main') {
    return 'latest'
  } else {
    return "${branch}-${commitHash}"
  }
}
```

Calcola il tag da assegnare all'immagine seguendo una strategia basata su Git:

- **Prima controlla se il commit corrente ha un tag Git esatto** (`git describe --tags --exact-match`). Il `|| true` evita che il comando fallisca la build quando non c'è nessun tag: in quel caso la variabile resta vuota. Se un tag c'è (es. una release `v1.2.0`), viene usato quello.
- **Se siamo sul branch `main`**, l'immagine prende il tag `latest`.
- **Per qualsiasi altro branch**, il tag è `<nomebranch>-<hash>`.

La riga `env.GIT_BRANCH.replaceAll('^origin/', '')` ripulisce il nome del branch dal prefisso `origin/` che Jenkins aggiunge.

### Funzione `buildAndPushTag(Map args)

```groovy
def buildAndPushTag(Map args) {
  def defaults = [
    registryUrl: 'docker.io',
    credRegistry: 'credenziali-dockerhub',
    dockerfileDir: "./jenkins"
  ]
  args = defaults + args
  env.IMAGE_NAME = "${args.image}:${args.buildTag}"

  withCredentials([usernamePassword(
    credentialsId: args.credRegistry,
    usernameVariable: 'USER',
    passwordVariable: 'PASS'
  )]) {
    try {
      sh 'echo "$PASS" | podman login ' + args.registryUrl + ' -u "$USER" --password-stdin'
      sh "podman build  -t ${args.image}:${args.buildTag} ${args.dockerfileDir}"
      sh "podman push ${args.image}:${args.buildTag}"
    }
    finally {
      sh "podman rmi --force ${args.image}:${args.buildTag}"
      sh "podman logout ${args.registryUrl}"
    }
  }
}
```

Esegue login, build e push:

- **Valori di default** — La funzione definisce dei default (`registryUrl`, `credRegistry`, `dockerfileDir`) e li fonde con gli argomenti passati (`args = defaults + args`). Così chi la chiama deve specificare solo lo stretto necessario, ma può sovrascrivere qualunque default.
- **`env.IMAGE_NAME`** — Salva il nome completo `immagine:tag` in una variabile d'ambiente.
- **`withCredentials`** — Recupera username e password del registry dal credential store di Jenkins e li espone come variabili `USER` e `PASS`, senza mai scriverle in chiaro nel codice o nei log.
- **Login** — Fa il login al registry passando la password via `--password-stdin` (letta dallo stdin invece che come argomento) così non compare nella lista dei processi né nei log.
- **Build e push** — Costruisce l'immagine dal `dockerfileDir` e la pusha sul registry con il tag calcolato.
- **Blocco `finally`** — Qualunque cosa succeda (successo o errore), fa **cleanup**: rimuove l'immagine locale (`podman rmi --force`) per non lasciare spazzatura sull'agent ed esegue il logout dal registry per non lasciare credenziali attive.

### La pipeline

```groovy
pipeline {
  agent any
  stages {
    stage('getTag') {
      steps {
        script {
          sh 'git fetch --tags'
          env.TAG = determineTag()
        }
      }
    }
    stage('Build & Push') {
      steps {
        script {
          buildAndPushTag(
            image: 'andry67/helloworld',
            buildTag: env.TAG
          )
          echo "Immagine pubblicata: ${env.IMAGE_NAME}"
        }
      }
    }
  }
}
```

Due stage in sequenza:

- **`getTag`** — Prima scarica i tag dal remoto con `git fetch --tags` (necessario perché `determineTag()` deve poterli vedere), poi calcola il tag e lo salva in `env.TAG`.
- **`Build & Push`** — Chiama `buildAndPushTag` passando il nome dell'immagine e il tag calcolato, poi stampa un messaggio di conferma con il nome completo dell'immagine pubblicata.

---

## Strategia di tagging in breve

| Situazione                    | Tag risultante            |
|-------------------------------|---------------------------|
| Commit con tag Git esatto     | il tag stesso (es. `v1.2.0`) |
| Branch `main`                 | `latest`                  |
| Qualsiasi altro branch        | `<branch>-<hash>`         |

Questo garantisce che ogni build sia identificabile e che le release taggate e la `latest` di produzione non vengano sovrascritte per errore dalle build di feature branch.
