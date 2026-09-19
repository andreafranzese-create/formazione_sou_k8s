#!/usr/bin/env bash

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

check_campi() {
    campo="$1"
    etichetta="$2"
    exit_code="$3"

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