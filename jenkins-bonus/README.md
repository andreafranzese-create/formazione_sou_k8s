# Esercizi Jenkins Pipeline 

## Funzionamento

All'avvio calcola il giorno corrente e legge il parametro `ENVIRONMENT`, poi decide quali stage eseguire tramite blocchi `when`.

### Oggetto Date

Nel blocco `environment` viene definita la variabile `GIORNO`:

```groovy
GIORNO = new Date().format('u')
```
- `new Date()` crea un **oggetto** data/ora con il momento attuale (data e ora di quando la pipeline viene eseguita).

- `.format('u')` **formatta** quella data secondo il pattern 'u'. Rappresenta i giorni della settimana come numero: 1 = lunedì, 2 = martedì, … fino a 7 = domenica.

### Gli stage

- **Warning** – Si esegue quando `GIORNO >= 6`, cioè sabato o domenica. Richiama `unstable`, che marca la build come *unstable* e stampa il messaggio che avvisa che nel weekend è sconsigliato eseguire build. La pipeline non fallisce, ma segnala uno stato non stabile.

- **PRODUCTION** – Si esegue solo se il parametro `ENVIRONMENT` vale `PRODUCTION`. Stampa a video il valore dell'ambiente selezionato.

- **DEVELOPMENT** – Si esegue solo se `ENVIRONMENT` vale `DEVELOPMENT`. Anch'esso stampa il valore dell'ambiente.

## Parametri

Il parametro è di tipo `choice`, definito nel blocco `parameters`:

```groovy
choice(name: 'ENVIRONMENT', choices: ['PRODUCTION', 'DEVELOPMENT'])
```

Un parametro `choice` mostra un **menù a tendina** con i soli valori di `choices`. L'utente ne sceglie uno; il **primo** (`PRODUCTION`) è il **default**.