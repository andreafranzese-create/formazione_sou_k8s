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