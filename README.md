# formazione_sou_k8s

Repository del percorso di formazione su **CI/CD e Kubernetes**: raccoglie gli esercizi svolti, dal setup di Jenkins fino al rilascio di un'applicazione su un cluster Kubernetes e alla verifica del deployment.

Il filo conduttore è un'applicazione Flask che viene **costruita, pubblicata, rilasciata e controllata** attraversando tutti gli strumenti della catena: Podman, Ansible, Jenkins, Helm e Kubernetes.

## Il percorso

```
Codice → immagine container → registry → chart Helm → cluster Kubernetes → verifica
         (Jenkins + Podman)             (Helm)        (Jenkins + RBAC)     (script + RBAC)
```

## Contenuto della repository

| Cartella | Argomento |
|---|---|
| [`jenkins-track/`](jenkins-track/) | Pipeline Jenkins di **build & push** dell'immagine su registry, con tag calcolato automaticamente da Git. Include l'app Flask e il Dockerfile di esempio. |
| [`jenkins-track/ansible-setup/`](jenkins-track/ansible-setup/) | Provisioning dell'**ambiente Jenkins** (master + agent) su Podman tramite playbook Ansible. |
| [`charts/`](charts/) | **Chart Helm** `flask-app` per il deploy dell'applicazione: Deployment, Service, Ingress e dipendenza `ingress-nginx`, con il tag dell'immagine passabile in input. |
| [`jenkins-helm-install/`](jenkins-helm-install/) | Pipeline Jenkins che esegue l'**`helm install`** sul cluster usando agent effimeri e un ServiceAccount dedicato (RBAC). |
| [`check-deployment/`](check-deployment/) | Script di **verifica delle best practice** del Deployment (probe, requests/limits), eseguito con un Service Account di sola lettura. |
| [`kubernetes-bonus/`](kubernetes-bonus/) | Esercizi aggiuntivi Kubernetes: **Secret**, Nginx con Basic Auth, routing con **Ingress** e `pathType`. |
| [`jenkins-bonus/`](jenkins-bonus/) | Esercizio aggiuntivo su pipeline Jenkins: **parametri** e stage condizionali. |

## Tecnologie usate

- **Jenkins** — pipeline dichiarative, credential store, agent su Kubernetes
- **Podman** — build e push delle immagini container
- **Ansible** — provisioning dell'ambiente Jenkins
- **Helm** — packaging e rilascio dell'applicazione
- **Kubernetes** (minikube) — Deployment, Service, Ingress, Secret, ConfigMap, RBAC
- **Bash / jq** — script di export e verifica