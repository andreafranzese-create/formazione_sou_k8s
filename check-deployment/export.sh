#!/usr/bin/env bash

FILE=export.yaml
TOKEN=$(kubectl create token cluster-reader -n formazione-sou)

if kubectl --token="$TOKEN" get deployment flask-app -n formazione-sou -o yaml > "$FILE"; then
    echo "Export eseguito con successo"
else
    echo "Errore, export non riuscito"
    exit 1
fi

if ! grep -q "readinessProbe" "$FILE"; then
    echo "Errore, non è presente la readinessProbe" 
    exit 2
fi

if ! grep -q "livenessProbe" "$FILE"; then
    echo "Errore, non è presente la livenessProbe" 
    exit 3
fi

if ! grep -q "limits" "$FILE"; then
    echo "Errore, non sono presenti i limits"
    exit 4
fi

if ! grep -q "requests" "$FILE"; then
    echo "Errore, non sono presenti i requests" 
    exit 5
fi

echo "Tutti gli attributi sono presenti"