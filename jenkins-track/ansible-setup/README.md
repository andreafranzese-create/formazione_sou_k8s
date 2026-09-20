# Jenkins su Podman con Ansible

## Architettura

L'ambiente è composto da due container che vivono sulla stessa rete bridge dedicata:

- **jenkins-master** — IP `10.0.0.2`. È il cuore di Jenkins: espone la UI web sulla porta `8080` e la porta JNLP `50000` a cui si agganciano gli agent. Salva tutti i suoi dati (configurazioni, job, plugin, credenziali) in un volume persistente.
- **jenkins-agent** — IP `10.0.0.3`. Si connette al master e si occupa di eseguire i job. Grazie al socket Podman montato dall'host, può creare container come parte delle pipeline.
- Entrambi vivono sulla rete bridge `network_1` (`10.0.0.0/24`) con IP statici, così l'agent raggiunge sempre il master a un indirizzo noto.

Il pattern usato per i container nelle build è quello "Docker-out-of-Docker": l'agent non annida un runtime dentro di sé, ma delega al Podman dell'host tramite il socket.


## Dockerfile dell'agent

```dockerfile
FROM jenkins/inbound-agent:latest
USER root
RUN apt-get update && \
    apt-get install -y podman-remote && \
    rm -rf /var/lib/apt/lists/*
RUN ln -s $(which podman) /usr/local/bin/docker
ENV CONTAINER_HOST=unix:///var/run/podman.sock
USER jenkins
```


- **`FROM jenkins/inbound-agent:latest`** — Immagine base ufficiale dell'agent Jenkins di tipo *inbound*
- **`USER root`** — L'immagine base gira come utente non privilegiato `jenkins`. Per installare pacchetti di sistema servono i permessi di root, quindi si passa temporaneamente a root.
- **Installazione di `podman-remote`** — Installa solo il **client** Podman, non il demone completo. È sufficiente perché i container non girano dentro l'agent: vengono lanciati sul Podman dell'host attraverso il socket. Le tre istruzioni sono concatenate in un unico `RUN`: così la pulizia della cache di apt (`rm -rf /var/lib/apt/lists/*`) avviene nello stesso layer in cui è stata creata, evitando che i file restino in un layer precedente e appesantiscano l'immagine.
- **`ln -s $(which podman) /usr/local/bin/docker`** — Crea un symlink che fa puntare il comando `docker` a `podman`. Serve per compatibilità: moltissime pipeline e plugin invocano `docker build`, `docker run`, ecc. Con questo alias funzionano senza modifiche, perché Podman è compatibile con la CLI di Docker.
- **`ENV CONTAINER_HOST=unix:///var/run/podman.sock`** — Indica al client Podman a quale socket connettersi: quello dell'host, montato come volume nel playbook. I container vengono quindi creati dal Podman dell'host, non annidati nell'agent.
- **`USER jenkins`** — Si torna all'utente non privilegiato per l'esecuzione a runtime.

## Playbook del master

Il playbook del master prepara l'host e avvia il container principale. Task per task:

- **Installa podman** — Assicura che il runtime Podman sia presente sull'host
- **Creazione rete** — Crea la rete bridge `network_1` con subnet `10.0.0.0/24` e IP statici. Avere indirizzi fissi permette all'agent di raggiungere il master in modo stabile.
- **Crea il volume** — Crea il volume nominato `jenkins-data`, montato su `/var/jenkins_home`, che rende persistenti i dati di Jenkins. Qui viene salvato tutto lo stato: config, job e plugin sopravvivono così alla ricreazione del container.
- **Pull dell'immagine** — Scarica in anticipo l'immagine ufficiale `jenkins/jenkins:latest`, così l'avvio del container non deve attendere il download.
- **Avvia il container jenkins-master** — Crea e avvia il master con IP `10.0.0.2`, le porte `8080` (UI) e `50000` (JNLP), il volume dati e il socket Podman. Le opzioni `label=disable` (SELinux) e `group_add` servono a dare al container l'accesso al socket dell'host.
- **Password iniziale dell'admin** — Legge il file `initialAdminPassword` dentro il container con `podman exec`. Usa retry e delay perché Jenkins impiega qualche secondo ad avviarsi e generare il file.
- **Stampa la password** — Mostra la password recuperata nell'output di Ansible, così è disponibile per il primo login.

## Playbook dell'agent

Il playbook dell'agent costruisce l'immagine custom e avvia il container che eseguirà i job:

- **Builda l'immagine dell'agent** — Costruisce l'immagine `jenkins-agent` a partire dal `Dockerfile-agent` presente in `/root`. La build avviene localmente sull'host.
- **Avvia l'agent jenkins** — Crea e avvia il container con `pull: never` (usa la build locale, non un registry), IP `10.0.0.3` e il socket Podman montato dall'host. Le variabili d'ambiente lo configurano:
  - `JENKINS_URL` — dove trovare il master (`http://10.0.0.2:8080`).
  - `JENKINS_AGENT_NAME` — il nome del nodo come registrato in Jenkins.
  - `JENKINS_SECRET` — il segreto di aggancio, letto da `vault.yaml`. Va tenuto cifrato con Ansible Vault perché è una credenziale.
  - `JENKINS_AGENT_WORKDIR` — la directory di lavoro dell'agent.
  - `CONTAINER_HOST` — ribadisce il socket a cui puntare, coerente col Dockerfile.

Il mount del socket `/run/podman/podman.sock:/var/run/podman.sock` è ciò che rende operativo il `CONTAINER_HOST`: senza di esso le pipeline che usano container fallirebbero, perché il client non avrebbe con chi parlare.