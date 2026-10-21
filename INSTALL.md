# HybrisMeter — Guida di installazione e avvio

> Questo documento descrive come installare e avviare l'intero stack in ambiente **LOCAL**.
> Per TEST e PROD vedere la sezione [Ambienti](#ambienti).

---

## Prerequisiti

| Componente | Versione minima | Verifica |
|---|---|---|
| Node.js | 20 LTS (≥ 20.9, richiesto da Next.js 16) | `node -v` |
| npm | 9+ | `npm -v` |
| Python | 3.12+ | `python3 --version` |
| PostgreSQL | 14+ | `psql --version` |
| psql CLI | qualsiasi | `psql -U postgres` |

### Installazione prerequisiti su Ubuntu/Kubuntu

```bash
# Node.js 20 LTS (tramite NodeSource)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Python 3.12
sudo apt-get install -y python3.12 python3.12-venv python3.12-dev

# PostgreSQL
sudo apt-get install -y postgresql postgresql-client
```

---

## Struttura del progetto

```
HybrisMeter/
├── DB/                              ← Schema PostgreSQL (sorgente + script deploy)
├── BE/api/                          ← Backend FastAPI (Python)
├── BE/file-monitoring-services/     ← Pipeline Node.js di importazione delle letture Qundis
├── BE/consumption-service/          ← Servizio Node.js di aggiornamento automatico dei consumi
├── FE/                              ← Frontend Next.js (TypeScript)
├── INSTALLERAPP/                    ← App Android dell'installatore (repository Git proprio)
├── USERAPP/                         ← App Android dell'utente finale (repository Git proprio)
├── start-be.sh / start-fe.sh        ← Avvio backend / frontend (dalla root)
├── run-tests.sh                     ← Batteria completa dei test (DB usa-e-getta, mai il DB reale)
├── version.sh                       ← Versione unica della piattaforma e hook dei commit
└── INSTALL.md                       ← Questo file
```

La radice (script e documenti comuni) è il repository `GiovanniGolfieri/HybrisMeterScripts`; DB, BE, FE,
INSTALLERAPP e USERAPP sono repository propri, clonati al suo interno. Comandi per un PC nuovo in
[README.md](README.md) → *Setting up a new PC*.

---

## 1. Database

### 1a. Configurazione PostgreSQL locale

```bash
# Avvia il servizio (se non già attivo)
sudo systemctl start postgresql

# Crea il database e l'utente applicativo (il deploy si collega come "hybrismeteradmin")
sudo -u postgres psql <<'SQL'
CREATE DATABASE hybrismeterdb;
CREATE USER hybrismeteradmin WITH PASSWORD 'scegli-una-password' CREATEDB;
GRANT ALL PRIVILEGES ON DATABASE hybrismeterdb TO hybrismeteradmin;
\c hybrismeterdb
CREATE EXTENSION IF NOT EXISTS btree_gist;   -- vincoli "exclude" sui periodi; richiede il superutente
SQL
```

`CREATEDB` serve a `./run-tests.sh`, che crea e poi elimina un database usa-e-getta.

### 1b. Deploy dello schema

Le password dei ruoli stanno in `DB/SRC/þ-deploy/.setpass.sh` (non versionato).

Lo schema nasce **da zero** dai sorgenti (`10_Tables/11.tbhybrismeter.sql` + dati di sistema `12.system_config_data.sql`):
prima installazione = ricostruzione completa (voce `R` di `deploy.sh`), possibile solo da terminale.

```bash
cd DB/SRC/þ-deploy
./deploy.sh L R      # mostra ambiente e contenuto attuale, chiede di scrivere RESET LOCAL; ricrea lo schema vuoto
./deploy.sh L F      # funzioni, trigger; rispondere y alla domanda sulla ricostruzione delle viste
```

`alter/alter-hybrismeter.sql` resta vuoto finché non c'è il primo rilascio ufficiale: TEST e PROD si reinstallano da zero.

> **Opzioni deploy:** `L`=Local · `T`=Test · `P`=Production  
> Modalità: `A`=Alter (DDL) · `F`=Functions (logica) · `V`=Patch (fix mirati)

---

## 2. Backend — BE/api (FastAPI)

### 2a. Setup

```bash
cd BE/api
./setup.sh
```

Lo script esegue automaticamente:
- Verifica Python 3.12+
- Crea `venv/` con `python3 -m venv`
- Installa le dipendenze da `requirements.txt`
- Copia `BE/api/.env.example` → `BE/api/.env` (solo se non esiste)

### 2b. Configurazione `.env`

Apri `BE/api/.env` e compila i parametri obbligatori:

```dotenv
DB_HOST=localhost
DB_PORT=5432
DB_NAME=hybrismeterdb
DB_USER=hybrismeteradmin
DB_PASSWORD=scegli-una-password
DB_SCHEMA=hybrismeter

# Chiave segreta per firmare i JWT — usa una stringa casuale lunga ≥ 32 caratteri
SECRET_KEY=cambia-con-stringa-casuale-lunga-almeno-32-chars

ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=480
ALLOWED_ORIGINS=http://localhost:3000
```

Genera una `SECRET_KEY` sicura:
```bash
python3 -c "import secrets; print(secrets.token_hex(32))"
```

### 2c. Avvio

```bash
# Dalla root del progetto
./start-be.sh
```

Il backend sarà disponibile su:
- API: http://localhost:8000
- Documentazione interattiva: http://localhost:8000/docs
- Schema OpenAPI: http://localhost:8000/openapi.json

> **Verifica:** `curl http://localhost:8000/docs` deve rispondere con HTML.

---

## 3. Frontend — FE (Next.js)

### 3a. Setup

```bash
cd FE
./setup.sh
```

Lo script esegue:
- Verifica Node.js 20+
- `npm install`
- Copia `FE/.env.example` → `FE/.env` (solo se non esiste)

### 3b. Configurazione `.env`

Apri `FE/.env` e imposta l'URL del backend:

```dotenv
# Ambiente LOCAL
NEXT_PUBLIC_API_URL=http://localhost:8000/api/v1
```

### 3c. Avvio

```bash
# Dalla root del progetto
./start-fe.sh
```

Il frontend sarà disponibile su: http://localhost:3000

> `start-fe.sh` verifica che `FE/.env` esista **e** non sia identico a `FE/.env.example`
> (per evitare avvii con URL vuoto).

---

## 4. Avvio completo

Apri **due terminali** nella root del progetto:

```bash
# Terminale 1 — Backend
./start-be.sh

# Terminale 2 — Frontend
./start-fe.sh
```

Poi apri http://localhost:3000 nel browser.

---

## 5. Primo accesso

`12.system_config_data.sql` crea gli utenti iniziali della piattaforma (superutente e amministratori Hybris) con i
gruppi predefiniti: si entra con quelle credenziali e si creano gli altri utenti da Configurazione → Utenti e gruppi
(gli utenti finali ricevono l'account con l'invito). Per generare a mano un hash bcrypt:
`python3 -c "import bcrypt; print(bcrypt.hashpw(b'password', bcrypt.gensalt(10)).decode())"`, oppure lo script
`Strumenti/CodificaPassword/encryptPassword.py` (repository separato, allo stesso livello di `HybrisMeter/`).

### Servizi Node e controlli

```bash
cd BE/consumption-service && ./deploy.sh L        # aggiornamento automatico dei consumi (dopo il deploy DB A + F)
cd BE/file-monitoring-services && ./deploy.sh L   # importazione delle letture Qundis (SFTP)
./run-tests.sh                                    # dalla root: tutta la batteria di test
./version.sh install                              # una volta per clone: hook comune dei commit (numero di versione)
```

---

## 6. Struttura endpoint API

| Metodo | Endpoint | Descrizione |
|---|---|---|
| POST | `/api/v1/auth/login` | Login → JWT |
| GET | `/api/v1/buildings/` | Lista stabili |
| GET | `/api/v1/units/?build_id={id}` | Unità di uno stabile |
| GET | `/api/v1/meters/?sbj_id={id}` | Misuratori di uno stabile |
| GET | `/api/v1/meters/?ui_id={id}` | Misuratori di un'unità |
| GET | `/api/v1/measures/?mtr_ids={ids}` | Misure per misuratori |

Documentazione completa con schema e test interattivi: http://localhost:8000/docs

---

## 7. Deploy su TEST e PROD

Gli script di deploy gestiscono il rilascio di ogni componente dello stack
sui server remoti tramite SSH + rsync, seguendo lo stesso approccio degli script DB.

### Script disponibili

| Componente | Script | Directory di esecuzione |
|---|---|---|
| Database | `deploy.sh [L\|T\|P] [A\|F\|V]` | `DB/SRC/þ-deploy/` |
| Aggiornamento consumi | `deploy.sh [L\|T\|P]` | `BE/consumption-service/` |
| Importazione letture | `deploy.sh [L\|T\|P]` | `BE/file-monitoring-services/` |
| Backend API | `deploy.sh [L\|T\|P] [D\|R]` | `BE/api/þ-deploy/` |
| Frontend | `deploy.sh [L\|T\|P] [D\|B\|R]` | `FE/þ-deploy/` |

### 7a. Configurazione iniziale server (gestita automaticamente al primo deploy)

Il file `.env` viene copiato automaticamente sul server alla prima esecuzione di `deploy.sh D`.
I file sorgente da compilare prima del primo deploy sono:

**Backend API** — compilare `BE/api/.env-test` e/o `BE/api/.env-prod`:
```dotenv
DB_HOST=meterdb-test.hybrismeter.it    # .env-test (in .env-prod: host AWS RDS)
DB_PORT=5432
DB_NAME=hybrismeterdb
DB_USER=hybrismeteradmin
DB_PASSWORD=<password-db>
DB_SCHEMA=hybrismeter
SECRET_KEY=<stringa-casuale-lunga-32-chars>
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=480
ALLOWED_ORIGINS=https://app-test.hybrismeter.it   # .env-prod: https://app.hybrismeter.it
```

**Frontend** — compilare `FE/.env-test` e/o `FE/.env-prod`:
```dotenv
NEXT_PUBLIC_API_URL=https://api-test.hybrismeter.it/api/v1   # .env-prod: URL PROD
```

> Il file `.env` già presente sul server **non viene mai sovrascritto** dai deploy successivi.
> Per aggiornarlo manualmente: `scp -i <chiave.pem> BE/api/.env-test ubuntu@<server>:/opt/hybrismeter-api/.env`

---

### 7b. Deploy Database

```bash
cd DB/SRC/þ-deploy

# Primo deploy / reinstallazione (solo da terminale: conferma RESET TEST)
./deploy.sh T R      # ricrea lo schema vuoto su TEST
./deploy.sh T F      # installa stored functions, viste e trigger su TEST

# Aggiornamenti successivi
./deploy.sh T F      # rilascio logica applicativa (solo funzioni/viste/trigger)
./deploy.sh T V      # patch mirata (fix specifici)

# PROD (stesse opzioni, chiede conferma)
./deploy.sh P A
./deploy.sh P F
```

Modalità: `A`=Alter (DDL tabelle) · `F`=Functions (logica) · `V`=Patch (fix mirati)

---

### 7c. Deploy Backend API (FastAPI)

```bash
cd BE/api/þ-deploy

./deploy.sh T D    # deploy completo su TEST (rsync + pip install + restart)
./deploy.sh T R    # solo restart su TEST  (es. dopo modifica .env sul server)
./deploy.sh P D    # deploy su PROD — chiede conferma Y/N
```

**Cosa fa il deploy:**
1. `rsync` di `app/`, `requirements.txt`, `pyproject.toml` verso `/opt/hybrismeter-api/`
   (esclusi: `venv/`, `__pycache__/`, `tests/`, `.env*`, `*.pyc`)
2. Crea/aggiorna il virtual environment Python e installa le dipendenze
3. Copia il file `systemd/hybrismeter-api.service` e gli script ausiliari
4. Installa (o riavvia) il servizio systemd `hybrismeter-api`
5. Verifica che il servizio sia attivo

**Servizio:** `hybrismeter-api` — uvicorn, porta 8000

```bash
# Comandi manuali sul server
sudo systemctl status hybrismeter-api
sudo systemctl restart hybrismeter-api
sudo journalctl -u hybrismeter-api -f    # log in tempo reale
```

---

### 7d. Deploy Frontend (Next.js)

```bash
cd FE/þ-deploy

./deploy.sh T B    # solo build locale (verifica che compili prima di deployare)
./deploy.sh T D    # build + deploy su TEST
./deploy.sh T R    # solo restart su TEST  (es. dopo modifica .env sul server)
./deploy.sh P D    # build + deploy su PROD — chiede conferma Y/N
```

**Cosa fa il deploy:**
1. `npm run build` eseguito **localmente** (produce la directory `.next/`)
2. `rsync` degli artefatti compilati verso `/opt/hybrismeter-fe/`:
   `.next/` (senza cache), `public/`, `package.json`, `package-lock.json`, `next.config.ts`
3. Sul server: `npm ci --omit=dev` per installare le dipendenze di produzione
4. Copia il file `systemd/hybrismeter-fe.service` e gli script ausiliari
5. Installa (o riavvia) il servizio systemd `hybrismeter-fe`
6. Verifica che il servizio sia attivo

> Il build viene sempre eseguito in **locale**: al server arrivano solo gli artefatti
> compilati, non il codice sorgente TypeScript.

**Servizio:** `hybrismeter-fe` — next start, porta 3000

```bash
# Comandi manuali sul server
sudo systemctl status hybrismeter-fe
sudo systemctl restart hybrismeter-fe
sudo journalctl -u hybrismeter-fe -f    # log in tempo reale
```

---

### 7e. Workflow di rilascio completo

Ordine raccomandato per un rilascio che include modifiche a tutti i componenti:

```bash
# 1. Database (prima di tutto — le stored functions cambiano)
cd DB/SRC/þ-deploy && ./deploy.sh T F

# 1b. Servizio dei consumi (dipende dalle procedure del DB)
cd BE/consumption-service && ./deploy.sh T

# 2. Backend API (dipende dalle stored functions)
cd BE/api/þ-deploy && ./deploy.sh T D

# 3. Frontend (dipende dall'API)
cd FE/þ-deploy && ./deploy.sh T D
```

Se solo il frontend cambia, basta il passo 3.  
Se solo le stored functions cambiano (senza modifiche al contratto API), basta il passo 1 + `./deploy.sh T R` per il backend.

---

## Ambienti

| Ambiente | Backend | Frontend | Database |
|---|---|---|---|
| **LOCAL** (dev) | `./start-be.sh` → :8000 | `./start-fe.sh` → :3000 | `localhost` |
| **LOCAL** (servizio) | systemd `hybrismeter-api` :8000 | systemd `hybrismeter-fe` :3000 | `localhost` |
| **TEST** | https://api-test.hybrismeter.it | https://app-test.hybrismeter.it | `meterdb-test.hybrismeter.it` |
| **PROD** | https://api-prod.hybrismeter.it | https://app.hybrismeter.it | AWS RDS (`meterdb-prod.hybrismeter.it`) |

Chiavi SSH per accesso server:
- TEST: `/dati/Lavoro/=HYBRIS=/Accessi/Chiavi/HybrisTEST.pem`
- PROD: `/dati/Lavoro/=HYBRIS=/Accessi/Chiavi/HybrisPROD.pem`

---

## Risoluzione problemi comuni

### Backend non parte — "Database pool non inizializzato"
→ Verificare che `BE/api/.env` abbia `DB_HOST`, `DB_USER`, `DB_PASSWORD` compilati.  
→ Verificare che PostgreSQL sia in esecuzione: `sudo systemctl status postgresql`.

### Backend non parte — "could not connect to server"
→ Il database non è raggiungibile. Verificare host/porta in `.env`.

### Frontend — 401 su tutte le chiamate API
→ Token scaduto o non valido. Eseguire nuovamente il login.

### Frontend — CORS error in console
→ Verificare che `ALLOWED_ORIGINS` in `BE/api/.env` includa l'URL del frontend (`http://localhost:3000`).

### `./deploy.sh` DB — "psql: command not found"
→ `sudo apt-get install -y postgresql-client`

### `setup.sh` — Python version error
→ Installare Python 3.12: `sudo apt-get install -y python3.12 python3.12-venv`

### Deploy BE/api — servizio non si avvia dopo il deploy
→ Verificare che `/opt/hybrismeter-api/.env` esista e sia compilato correttamente.  
→ `sudo journalctl -u hybrismeter-api -n 50` per vedere l'errore di avvio.

### Deploy FE — `npm ci` fallisce sul server
→ Verificare che Node.js 20+ sia installato sul server: `node -v`.  
→ Se assente: `curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash - && sudo apt-get install -y nodejs`

### Deploy FE — "Key file not found"
→ Verificare il percorso del file PEM in `FE/þ-deploy/deploy.sh` (variabile `TEST_SERVERS` / `PROD_SERVERS`).

### Servizio systemd non si avvia — "Permission denied"
→ Verificare che `User=` nel file `.service` corrisponda all'utente corretto sul server
  (`ubuntu` per TEST/PROD, `golf` per LOCAL — lo script lo aggiusta automaticamente per LOCAL).
