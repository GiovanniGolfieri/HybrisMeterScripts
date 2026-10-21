# CLAUDE.md — HybrisMeter (root)

Guida per la gestione assistita da AI del progetto HybrisMeter.
Questo file è il punto di ingresso; ogni sottodirectory con CLAUDE.md propria va consultata
per i dettagli specifici del componente.

---

## Descrizione del progetto

**HybrisMeter** è una piattaforma digitale per la raccolta e la gestione dei consumi
di acqua, calore ed energia in ambito condominiale.

Il flusso principale:
1. Contatori fisici (brand Qundis) trasmettono dati cifrati via SFTP
2. Un pipeline Node.js li decifra, li parsifica e li inserisce nel DB PostgreSQL
3. Un frontend Next.js (vedi sotto) permette a operatori e amministratori di consultare
   misure, consumazioni e riparti di costo — in PROD, con alcune pagine di dettaglio
   ancora in corso di porting da una precedente UI legacy ormai superata
4. Script Python ausiliari gestiscono l'inserimento iniziale di strutture e la generazione
   di documenti (bollette, fogli tecnici) via Google Sheets

---

## Struttura delle directory

```
HybrisMeter/
├── CLAUDE.md                        ← questo file
├── DB/                              ← schema PostgreSQL + stored functions (CLAUDE.md proprio)
├── BE/                              ← tutti i servizi backend
│   ├── file-monitoring-services/    ← pipeline Node.js importazione misure (CLAUDE.md proprio)
│   ├── socket-server-service/       ← WebSocket server Node.js (in sviluppo)
│   ├── consumption-service/         ← aggiornamento automatico dei consumi, Node sempre attivo (CLAUDE.md proprio)
│   └── api/                         ← NEW — backend FastAPI (CLAUDE.md proprio)
├── FE/                              ← NEW — frontend Next.js (CLAUDE.md proprio)
├── INSTALLERAPP/                    ← app Android dell'installatore (Kotlin + Compose, offline-first; repo Git proprio)
├── USERAPP/                         ← app Android dell'utente finale (Kotlin + Compose; repo Git proprio)
├── version.sh                       ← versione unica della piattaforma (vedi «Versione»)
├── .githooks/                       ← hook pre-commit comune ai cinque repository
├── start-be.sh                      ← avvio locale BE/api (FastAPI)
└── start-fe.sh                      ← avvio locale FE (Next.js)
```

**Repository della radice** (2026-10-21): script e documenti comuni (questo file, `GRANT.md`, `INSTALL.md`,
`PARAMETRI-RIPARTI.md`, `version.sh`, `run-tests.sh`, `.githooks/`, `start-*.sh`) sono nel repository
`github.com/GiovanniGolfieri/HybrisMeterScripts`, che ignora le cinque cartelle con repository proprio (DB, BE, FE,
INSTALLERAPP, USERAPP). L'hook di versione non vale per questo repository. Clonazione su un PC nuovo: `README.md`.

**Nota (2026-09-07):** `Strumenti/` non è più una sottocartella di HybrisMeter — è stata spostata
allo stesso livello, in `/dati/Lavoro/=HYBRIS=/Strumenti/`, con repository Git proprio
(`github.com/GiovanniGolfieri/HybrisTools`), indipendente da DB/BE/FE. Resta visibile insieme
al resto del progetto tramite il file multi-root `HybrisMeter.code-workspace`. Contiene:

```
Strumenti/
├── ImportStabiliDaSheet/        ← importStabiliDaSheet.py, import stabili via API (CLAUDE.md proprio)
├── CreazioneFogliBollette/      ← creaBollette.py (CLAUDE.md proprio)
├── CreazionePLTqundis/
├── CreazioneTecnicoDaRiparto/
├── FormattazioneFogliStabili/
├── CreazioneSQLperInserimentoStabili/
├── EstrazioneMisure/
├── CodificaPassword/
├── PuliziaPLTqundis/
└── EstrazioneRiparto3RL/
```

---

## Dominio applicativo

```
STABILE (edificio/condominio)
  └── UNITÀ IMMOBILIARE (appartamento, locale, ...)
        └── MISURATORE (contatore fisico)
              ├── MISURE (letture periodiche)
              └── CONSUMAZIONI (differenze fra letture, calcolate)
                    └── RIPARTO (allocazione costi → bollette)
```

Terminologia usata in codice e nel DB:

| Dominio        | Tabella principale                     | Note                                  |
|----------------|----------------------------------------|---------------------------------------|
| Stabile        | `db_buildingsHead` + `db_buildingsDet` | Det con validità temporale            |
| Unità immob.   | `db_unitsHead` + `db_unitsDet`         | Det con validità temporale            |
| Misuratore     | `db_meters` (tipo: `db_meterTypes`)    |                                       |
| Lettura        | `wrk_waterReads`, `wrk_heatReads`      | inserita da pipeline o manualmente    |
| Consumazione   | `wrk_waterConsums`, `wrk_heatConsums`  | calcolata da `fnCalcMeterMonthCons()` |
| Riparto        | `wrk_allocwater`, `wrk_allocheat`      | calcolato da `dbAllocCompute()`       |
| Soggetto       | `db_subjects`                          | persone, enti, edifici-come-soggetto  |
| Utente         | `db_users` (⊆ db_subjects)             | con username/password bcrypt          |
| Gruppo utenti  | `db_uGroups`                           | con `grp_grants` bitmask              |

---

## Database — PostgreSQL

**Vedi:** [DB/CLAUDE.md](DB/CLAUDE.md) per inventario completo di tabelle, viste, funzioni e trigger.

**DB:** `hybrismeterdb`
**Schema principale:** `hybrismeter`
**Schema utente applicativo:** `hybrismeter` (ruolo limitato rispetto a `postgres`)

### Struttura sorgenti DB

```
DB/SRC/
├── hybrismeter/
│   ├── 10_Tables/        — tabelle e dati di sistema
│   ├── 20_Views/         — viste (soggetti, strutture, misure, consumi, riparti)
│   ├── 30_WrkFunctions/  — stored functions interne (logica applicativa, prefisso fn/db)
│   ├── 40_ApiFunctions/  — stored functions API-facing (prefisso api_) ← usate da BE/api
│   ├── 50_Trigger/       — trigger di audit
│   ├── 60_SystemData/    — dati demo
│   ├── 80_Tests/         — test SQL
│   └── 90_Custom/        — customizzazioni per cliente specifico
├── _common/              — funzioni condivise
└── þ-deploy/             — script di deploy DB
```

### Stored functions principali

Le stored functions esposte via BE/api sono nel prefisso `api_` (directory `40_ApiFunctions/`).
Le funzioni in `30_WrkFunctions/` (prefisso `db`/`fn`) sono di uso interno o usate dal pipeline Node.js.

| File (`40_ApiFunctions/`)   | Funzioni chiave                                                                                    |
|------------------------------|---------------------------------------------------------------------------------------------------|
| `41.api_access.sql`          | `api_Login` — autenticazione; `api_GetPasswordResetContact` — lookup email per reset password    |
| `42.api_structures.sql`      | `api_GetBuildingsHead`, `api_SetBuildingHead`, `api_SetBuildingDet`, `api_NewBuildingDet`         |
|                               | `api_GetUnitsHead`, `api_SetUnitHead`, `api_SetUnitDetail`, `api_SetUnitSubject`                  |
|                               | `api_GetMeters`, `api_SetMeter`, `api_SetMeterTypes`                                              |
| `43.api_meascons.sql`        | `api_GetMeasures`, `api_SetMeasure` — letture (GET e inserimento manuale); `api_GetEchartCons`,   |
|                               | `api_GetEchartDelta`, `api_GetEchartBldCons`, `api_GetHeatMonthPie` — consumi                     |
| `44.api_allocations.sql`     | `api_AllocCheckBuilding`, `api_AllocCompute`, `api_AllocApprove` (acqua/calore/ACS/RAFF,          |
|                               | versionamento periodi, Riparto Generale)                                                          |

**Regola:** consultare sempre i file SQL in `DB/SRC` come riferimento autorevole per
lo schema. Non fare assunzioni sullo schema leggendo solo il codice di BE/api o FE.

### Modello permessi (bitmask grants)

I permessi utente sono codificati come bitmask esadecimale nel campo `grp_grants` di `db_uGroups`.
**Riorganizzazione 2026-08-03** (specifica completa in `GRANT.md`, root del progetto): tre assi —
**GATE** (da quale app client ci si autentica, verificato in `api_Login`), **CAPABILITY** (quale
azione su quale dominio, verificata nel BE via `require_grant`), **SCOPE** (su quale sottoinsieme
di record, verificato nel DB dentro ogni funzione `api_Get*`/`api_Set*`). `HANDLE_ROOT` è un quarto
asse **PLATFORM**. La vecchia triade `VIEW/EDIT/CREATE_*` è stata eliminata: `EDIT_*` copre ora
sempre modifica+creazione+cancellazione. Vedi [DB/CLAUDE.md](DB/CLAUDE.md) per il dettaglio
completo (query di scoping, gruppi predefiniti).

| Bit (hex)    | Nome              | Asse       | Descrizione                                          |
|--------------|-------------------|------------|-------------------------------------------------------|
| `0x00000001` | LOGIN             | GATE       | Accesso da WebApp                                      |
| `0x00000002` | APPLOGIN          | GATE       | Accesso app utente finale (`USERAPP`, application=2)   |
| `0x00000004` | TECHLOGIN         | GATE       | Accesso app installatore/tecnico                       |
| `0x00000010` | VIEW_USER         | CAPABILITY | Visualizza utenti e gruppi                             |
| `0x00000020` | EDIT_USER         | CAPABILITY | Modifica/crea/cancella utenti e gruppi                 |
| `0x00000040` | VIEW_SUBJECTS     | CAPABILITY | Visualizza soggetti e anagrafiche                      |
| `0x00000080` | EDIT_SUBJECTS     | CAPABILITY | Modifica/crea/cancella soggetti e anagrafiche          |
| `0x00000100` | VIEW_STRUCT       | CAPABILITY | Visualizza strutture                                   |
| `0x00000200` | EDIT_STRUCT       | CAPABILITY | Modifica/crea/cancella strutture                       |
| `0x00000400` | VIEW_MAP          | CAPABILITY | Mappa stabili (solo quelli del proprio ambito)          |
| `0x00001000` | VIEW_MEASURE      | CAPABILITY | Visualizza misure e consumi                            |
| `0x00002000` | EDIT_MEASURE      | CAPABILITY | Modifica/crea/cancella misure                          |
| `0x00004000` | VIEW_ALLOC        | CAPABILITY | Visualizza riparti                                     |
| `0x00008000` | EDIT_ALLOC        | CAPABILITY | Modifica/crea/cancella riparti                         |
| `0x00010000` | VIEW_ALARMS       | CAPABILITY | Visualizza allarmi consumo                             |
| `0x00020000` | EDIT_ALARMS       | CAPABILITY | Tacita/chiude allarmi consumo                          |
| `0x00040000` | SELF_READ         | CAPABILITY | Autoletture sulle proprie unità (utente finale)        |
| `0x00100000` | OWN_UNITS    | SCOPE      | Solo le proprie unità immobiliari (utente finale)      |
| `0x00200000` | OWN_CREATED_BUILDINGS | SCOPE      | Crea ovunque; modifica/cancella solo il proprio, finché non validato |
| `0x00400000` | VIEW_ALL_BUILDINGS    | SCOPE      | Vede tutto in sola lettura (nessun diritto di modifica) |
| `0x10000000` | ALL_BUILDINGS        | SCOPE      | Amministratore completo (tutti gli stabili)            |
| `0x20000000` | MANAGED_BUILDINGS    | SCOPE      | Responsabile condominiale (solo stabili amministrati)  |
| `0x40000000` | HANDLE_ROOT       | PLATFORM   | Superutente: dettagli tecnici griglie, config. colori  |

### Deploy DB

```bash
cd DB/SRC/þ-deploy
./deploy.sh [L|T|P] [A|F|V|R]
# L=Local, T=Test, P=Prod
# A=Alter (schema), F=Functions (logica), V=Patch (fix mirati), R=Reset completo (solo da terminale)
```

**Il reset (`R`) lo esegue solo l'utente, a mano, da terminale**: nessun agente AI lo lancia né prova ad aggirare il
controllo del terminale, in nessun ambiente (LOCAL compreso).

---

## Backend — BE/

Tutti i servizi backend risiedono in `BE/`. Le sottodirectory sono indipendenti
e non condividono codice tra loro.

### BE/file-monitoring-services — pipeline Qundis (Node.js)

**Vedi:** [BE/file-monitoring-services/CLAUDE.md](BE/file-monitoring-services/CLAUDE.md)

Pipeline in due microservizi Node.js (ES modules) — non va modificato nel porting:

1. **msvc-incoming-monitor** — osserva directory SFTP per ZIP cifrati → estrae XML
2. **msvc-data-monitor** — osserva XML estratti → parsing → INSERT via `dbSetMeasure()`

Formato dati: XML Siemeca v1.1 (contatori Qundis, dimensione `H.C.A.`)

```bash
cd BE/file-monitoring-services
./deploy.sh [L|T|P]   # L=Local, T=Test, P=Prod
```

### BE/consumption-service — aggiornamento automatico dei consumi (Node.js, 2026-09-24)

**Vedi:** [BE/consumption-service/CLAUDE.md](BE/consumption-service/CLAUDE.md) e la sezione *Calcolo consumi* sotto.

Servizio systemd `msvc-cons-worker`, separato dal file monitoring (non guarda file: è avviato dal DB). Ascolta le
notifiche della coda dei ricalcoli e chiama le procedure del DB; la logica resta nelle stored functions.

```bash
cd BE/consumption-service
./deploy.sh [L|T|P]   # dopo il deploy DB (A + F)
```

### BE/socket-server-service — WebSocket server (Node.js, in sviluppo)

Non ancora documentato in dettaglio. Struttura analoga a file-monitoring-services.

### BE/api — FastAPI (NEW)

**Vedi:** [BE/api/CLAUDE.md](BE/api/CLAUDE.md) per documentazione completa (endpoint, pattern, grants).

Backend unico per il nuovo frontend Next.js e futuro app mobile.

---

## Nuova architettura — Frontend Next.js

### Obiettivo e strategia

Frontend Next.js moderno che sostituisce la precedente UI legacy (ormai superata),
mantenendo DB e stored functions invariati. Alcune pagine di dettaglio sono ancora
in corso di porting.

### Stack tecnologico

| Layer    | Tecnologia                                      | Note                              |
|----------|-------------------------------------------------|-----------------------------------|
| Frontend | Next.js 15, TypeScript, Tailwind CSS, shadcn/ui | App Router, TanStack Query v5     |
| Backend  | FastAPI (Python 3.12+)                          | Unico API server per web e mobile |
| Auth     | JWT (Bearer token)                              | Logica grants bitmask invariata   |
| DB conn. | asyncpg                                         | Pool async, chiamate stored fn    |
| DB       | PostgreSQL / AWS RDS                            | Schema e stored functions intatti |

### Struttura directory BE/api (FastAPI)

```
BE/api/
├── CLAUDE.md                        ← ✅ creato
├── app/
│   ├── __init__.py
│   ├── main.py                      ← app FastAPI, CORS, lifespan, include router
│   ├── api/
│   │   └── v1/
│   │       ├── __init__.py
│   │       ├── router.py            ← aggrega tutti i sub-router
│   │       └── endpoints/
│   │           ├── auth.py          ← POST /auth/login → JWT
│   │           ├── buildings.py
│   │           ├── units.py
│   │           ├── meters.py
│   │           ├── measures.py
│   │           ├── consumptions.py
│   │           └── allocations.py
│   ├── core/
│   │   ├── config.py                ← Settings da .env (pydantic BaseSettings)
│   │   ├── security.py              ← create_token, verify_token, hash/verify password
│   │   └── deps.py                  ← get_db(), get_current_user(), require_grant(bit)
│   ├── db/
│   │   ├── pool.py                  ← asyncpg pool, init/close, helper call_fn()
│   │   └── queries.py               ← wrapper tipizzati per ogni stored function
│   └── models/
│       ├── auth.py                  ← LoginRequest, TokenResponse
│       ├── building.py
│       ├── unit.py
│       ├── meter.py
│       ├── measure.py
│       ├── consumption.py
│       └── allocation.py
├── content/
│   └── guida/                       ← testi Markdown delle pagine di guida (non su DB)
│       ├── riparti-acqua.md
│       └── riparti-calore.md
├── tests/
│   ├── conftest.py
│   └── test_auth.py
├── venv/                            ← mai committare (in .gitignore)
├── .env                             ← mai committare
├── .env.example                     ← committare, valori vuoti
├── requirements.txt
├── setup.sh                         ← crea venv, installa deps, copia .env.example se manca
└── .gitignore
```

### Struttura directory FE (Next.js)

```
FE/
├── CLAUDE.md                        ← ✅ creato (vedi FE/docs/AGENTS.md e FE/docs/DESIGN.md)
├── src/
│   ├── app/
│   │   ├── (auth)/
│   │   │   └── login/
│   │   │       └── page.tsx
│   │   └── (dashboard)/
│   │       ├── layout.tsx           ← sidebar + header autenticati
│   │       ├── dashboard/page.tsx
│   │       ├── buildings/page.tsx
│   │       ├── units/page.tsx
│   │       ├── meters/page.tsx
│   │       ├── measures/page.tsx
│   │       ├── consumptions/page.tsx
│   │       └── allocations/page.tsx
│   ├── components/
│   │   ├── ui/                      ← shadcn/ui components
│   │   └── layout/
│   │       ├── Sidebar.tsx
│   │       └── Header.tsx
│   ├── lib/
│   │   ├── api.ts                   ← axios instance + interceptor JWT
│   │   ├── auth.ts                  ← get/set/remove token
│   │   └── queryClient.ts
│   ├── proxy.ts                      ← protegge le route dashboard (ex middleware.ts, Next 16)
│   └── types/
│       └── api.ts                   ← TypeScript types ≡ Pydantic models BE
├── .env                             ← mai committare
├── .env.example                     ← committare, valori vuoti
├── .env-test                        ← mai committare (credenziali TEST)
├── .env-prod                        ← mai committare (credenziali PROD)
├── next.config.ts
├── tailwind.config.ts
├── tsconfig.json
└── package.json
```

### Convenzioni API

- Prefisso: `/api/v1/`
- Stessa terminologia del DB: `buildings`, `units`, `meters`, `measures`, `consumptions`, `allocations`
- Tutte le query DB chiamano stored functions `api_*` via `call_fn_jsonb()` — **mai query dirette sulle tabelle**
- Auth: `api_Login(username, application)` restituisce `hash` BCrypt + `grants`; BE verifica password
  e crea JWT con `user_id` + `grp_grants`
- Ogni endpoint verifica i bit necessari tramite `require_grant(bit)` in `deps.py`
- DELETE: le stored functions `api_Set*` accettano `{"<pk>": N, "DELETE": 1}` nel body per le cancellazioni

### Stato porting BE/api — endpoint implementati

| Dominio | GET | POST (create) | PUT (update) | DELETE |
|---------|-----|---------------|--------------|--------|
| Auth | — | ✅ `/auth/login` | — | — |
| Buildings | ✅ list + det | ✅ | ✅ | ✅ |
| Buildings det | ✅ | ✅ + `det/new` | ✅ | ✅ |
| Units | ✅ | ✅ | ✅ | ✅ |
| Units det | ✅ | ✅ | ✅ | ✅ |
| Units subjects | ✅ | ✅ | ✅ | ✅ |
| Meters | ✅ | ✅ | ✅ | ✅ |
| Meter types | — | ✅ | ✅ | ✅ |
| Measures | ✅ | ✅ | — | — |
| Autoletture | ✅ `/self-readings/targets`, foto | ✅ (anche correzione) | — | ✅ |
| Consumptions | ✅ (chart) | — | — | — |
| Allocations | ✅ check | ✅ compute | — | — |
| Allocations approve | — | ✅ | — | — |
| Guida | ✅ indice + `{slug}` | — | — | — |
| Inviti utenti / mittente email | ✅ `/config/mail-sender`, `/apps/{app}/invite` | ✅ `/config/users/{id}/invite/*`, `/auth/first-password` | ✅ `/config/mail-sender` | — |
| App installatore | ✅ `/installer/snapshot`, `/proposals`, ambienti, assegnazioni | ✅ `/auth/refresh`, `/installer/sync`, `/installer/photos`, `/buildings/{id}/validate` | — | ✅ foto |

**Completamento degli stabili** (2026-09-30): per ogni stabile una percentuale = informazioni presenti / informazioni
necessarie ai riparti senza approssimazioni (somma semplice dei punti: 1 per requisito di stabile, 1 per ogni unità o
misuratore interessato; solo i servizi gestiti; trasmissione solo per gli stabili a telelettura). Lo stato impostato a
mano (`bld_state`: Attivo / Sospeso / Inattivo / Chiuso) è separato dallo stato **mostrato**, calcolato: Sospeso /
Inattivo / Chiuso come impostati, altrimenti Cantiere (cantiere aperto, `bld_flags` bit0) / Incompleto (manca un dato
**bloccante**, senza il quale il riparto non parte) / Attivo; i dati **consigliati** mancanti (riparto possibile con stime
o avvisi: generali, trasmissione, proprietario/conduttore, fattore u.r. → kWh) abbassano solo la percentuale (2026-10-10). `bld_flags` bit1 = lettura manuale. Modelli di misuratore `typ_radio` / `typ_iot`; misuratore silente
(già trasmesso, fermo oltre la soglia ereditata misuratore → unità → stabile) = allarme 3, notturno. FE: colonna
«Completamento» (barra monocolore da rosso a giallo a verde secondo la %, riquadro al clic con ciò che manca) nella lista stabili e nella griglia
unità, pannello nella scheda. DB: `3A.bldCompletion.sql` — vedi [DB/CLAUDE.md](DB/CLAUDE.md) → *Completamento degli stabili*.

**Antenne e ripetitori** (2026-09-30): non sono misuratori. Tabelle proprie (`db_antennaTypes` ANTENNA / REPEATER,
`db_antennas`, `db_antennaPhotos`, `wrk_antennaContacts`); un ripetitore fa capo a un'antenna dello stesso stabile; un'antenna
appartiene a un solo stabile. A ogni file Siemeca la pipeline passa il blocco `<communicator>` (matricola, ora, batteria,
firmware) ad `api_SetAntennaContact`: storico, stato dell'antenna e allarme 4 sotto la soglia unica di piattaforma
(`loo_appConfig 'antennaBattery'`, default 20%). I ripetitori non compaiono nei file. FE: riquadro «Antenne e ripetitori»
nella sottoscheda «Misuratori generali e antenne», Configurazione → Modelli antenna e Sistema → Batteria antenne.
DB: `47.api_antennas.sql`; BE: `/antennas`. Gestione dall'app installatore: in carico alla sessione dell'app.

**Inviti agli utenti** (2026-10-01): da Configurazione → Utenti e gruppi, alla prima email in anagrafica. Utente finale →
invito alla piattaforma con una **password provvisoria valida per un solo accesso** (`db_users.usr_pwdState`; al primo
accesso il web chiede subito la nuova password). Installatore → link e QR code della pagina `/scarica-app/invito`
dell'ambiente che invia, che scarica l'app e la apre già configurata (server + nome utente, `hybrisinstaller://setup`).
Mittente in Configurazione → Sistema → Invio email (HANDLE_ROOT, `loo_appConfig 'mailSender'`, password cifrata con la
`SECRET_KEY` dell'ambiente: va inserita in ogni ambiente). Vedi [BE/api/CLAUDE.md](BE/api/CLAUDE.md) → *Inviti*.
Dal 2026-10-07 l'import degli stabili crea solo le persone: l'**account nasce con l'invito**, dal dettaglio dell'unità
(icona accanto a proprietari e conduttori) o con «Invita tutti» della griglia unità, solo per chi è collegato oggi a
un'unità. Nome utente sempre `cognome.nome` (max 32
caratteri, numero se già usato; esclusi gli utenti iniziali dello script di sistema); si entra anche con l'e-mail se è di
un solo utente; invito (e recupero password) all'indirizzo scelto nei contatti del soggetto, altrimenti alla prima e-mail,
altrimenti alla PEC. In «Nuovo utente» il nome utente è proposto come `cognome.nome` ed è modificabile.

**Autoletture dell'utente finale** (2026-10-05): con il bit `SELF_READ` (gruppo 9) l'utente finale inserisce dalla pagina
Letture il valore letto sul display dei contatori installati oggi sulle sue unità (acqua e calore), con foto facoltativa,
nel suo periodo corrente fino a oggi; la corregge o la elimina finché nessun riparto l'ha usata. Modalità sempre
`Autolettura` (priorità dopo le letture automatiche), consumi aggiornati dalla coda come per ogni lettura, misuratore guasto
= rifiutata. DB: `fnSelfRead*` (`34.measures.sql`), `api_*SelfRead*` (`43.api_meascons.sql`), tabella `wrk_selfReadPhotos`;
BE `/self-readings`; FE `SelfReadingDialog`. Test 99e + sezione L di `smoke_enduser.py`.

**Colori di riferimento** (2026-10-01): cinque colori base (`loo_appColors REF_*`, Configurazione → Colori, HANDLE_ROOT)
da cui il FE ricava le gradazioni di tutti gli stati (badge, barre di completamento, messaggi). Vedi
[FE/CLAUDE.md](FE/CLAUDE.md) → *Colori degli stati*.

**Configurazioni di importazione degli stabili** (2026-10-05): le celle dei fogli tecnici lette dall'import e scritte
dall'export sono configurazioni con nome (`loo_appConfig 'buildingImport'`, una predefinita), da Configurazione → Sistema →
Importazione stabili (HANDLE_ROOT); la finestra «Importa» lascia scegliere quale usare. Vedi [BE/api/CLAUDE.md](BE/api/CLAUDE.md).
Dal 2026-10-07: contatti **uno per riga** sotto la persona (resta valido più contatti in una cella), PEC riconosciute dal
dominio (`pecDomains` nella stessa configurazione) o da «PEC:» e salvate come PEC; prima di scrivere l'import cerca
presunti errori dei dati e, se ne trova, non scrive nulla e chiede conferma («Importa comunque»).
Dal 2026-10-21 i modelli generici della colonna TIPO (-1/-2/-3, necessari alle formule dei fogli) si abbinano all'import
al modello vero, una scelta per generico; per gli stabili già importati «Modelli misuratori» nella scheda stabile, per
tutto il gruppo o per i soli misuratori spuntati (stabili con modelli misti). Un misuratore che trasmette con un codice
diverso da quello del suo modello (es. modulo radio) si associa da solo alla prima trasmissione e prende il modello giusto.
La colonna P «coeff» (KQ × KC del radiatore) diventa il K del misuratore; il fattore di rivalutazione del ripartitore
(2.33 / 1.00) è del modello e i fogli lo dichiarano in Struttura G19:I19 (vedi [BE/api/CLAUDE.md](BE/api/CLAUDE.md)).

**Riparto calore secondo il documento di riferimento** (2026-10-10): regole in `Specifiche e Doc normativi/info_CalcoloRiparti2/`
(PDF = guida e formule, `Riparto_calore_tecnico.md` = specifica). Energia di centrale proposta dai misuratori generali (RISC =
totale − ACS), dalle bollette (× coefficiente di conversione × rendimento del libretto o 0.85) o dai totali mensili; bolletta di
centrale divisa in parte RISC e ACS; misto con la formula UNI 10200; minimo del 50% sulla spesa con correzione; ACS dai m³
convenzionali; consumo stimato predefinito per le unità senza misuratore; prima stagione; parti comuni (destinazione d'uso
`PC`); centrale condivisa del super-condominio; segnalazioni. Regole in [DB/CLAUDE.md](DB/CLAUDE.md) → *Calore*, guida
`BE/api/content/guida/riparti-calore.md`. Dal 2026-10-14 è il **comportamento di riferimento** anche per i fogli Google
usati in attesa della piattaforma (`Riparto_calore_tecnico.md` + parte seconda del PDF, «Schema per foglio elettronico»):
quota involontaria RISC dal fattore d'uso (UNI 10200:2018) se la relazione tecnica lo prevede, quota ACS misurata nel
periodo → Parte ACS di progetto → (senza) ultimo anno dei generali (avviso col gas estivo), Parte ACS propria per energia elettrica e spese di
gestione, fattore di base dei modelli di ripartitore, spesa energetica a millesimi nei periodi senza consumo.

**Energia elettrica della centrale nei riparti calore** (2026-10-12): contratti «Energia elettrica» con il loro contatore
(centrale termica, ACS o raffrescamento dedicati; `rel_bldContract.ctr_srvID`) e bollette in kWh; nei *Parametri
ripartizione* se ACS e raffrescamento hanno un contatore proprio. Nel wizard ogni bolletta elettrica del periodo ha la sua
percentuale (proposta: la parte ancora libera, 100% se intera; quella usata resta collegata al riparto); senza bollette si
inserisce la cifra. Come vuole la UNI 10200 l'energia elettrica entra nella spesa energetica e nel costo unitario, non nei kWh di energia utile.
DB: `fnHeatPlantElec` — vedi [DB/CLAUDE.md](DB/CLAUDE.md) → *Calore*; test 99j.

**Codice di trasmissione dei misuratori** (2026-10-10): la pipeline riconosce un misuratore prima dal codice che trasmette
(`db_meters.mtr_code`, Qundis `matricola|17555|versione|tipo`), qualunque sia il tipo trasmesso, poi da matricola + tipo.
Il codice è proposto dallo schema del modello (`db_meterTypes.typ_IOTcode`, Configurazione → Modelli misuratore), corretto
dalla prima trasmissione trovata per matricola e modificabile nella scheda del misuratore. Un contatore di acqua calda montato
sulla fredda resta registrato come fredda: da Misuratori sconosciuti si **associa** al misuratore con la stessa matricola e
le letture in sospeso vengono recuperate. Vedi [DB/CLAUDE.md](DB/CLAUDE.md) → *Codice di trasmissione dei misuratori*.

**Calcolo consumi** (2026-09-24): i consumi mensili (`wrk_waterConsums`/`wrk_heatConsums`/`wrk_acsConsums`) si
aggiornano da soli. I trigger sulle letture (e su misuratori, fattore u.r.→kWh, totali ACS) mettono in coda in
`wrk_consQueue` **cosa** ricalcolare — un intervallo di mesi per misuratore — e mandano `pg_notify('cons_queue')`.
Il servizio `BE/consumption-service` aspetta la quiete dello stabile (30 s, tetto 10 min: un file importato = un solo
ricalcolo) e chiama `prcConsProcessQueue`; passata di controllo ogni 5 min, notturna alle 02:30 (mese corrente, che
cambia ogni giorno), verifica completa il giorno 1 alle 03:30. Parametri in `loo_appConfig` 'consRecalc', modificabili da
Configurazione → Sistema → Calcolo consumi (HANDLE_ROOT), applicati senza riavvio. Pulsante «Aggiorna ora» nella pagina
Consumi = elaborazione sincrona dello stabile. Il riparto ACS elabora la coda dello stabile prima di leggere i consumi.
DB: `39.consQueue.sql`, `55.trConsumptions.sql` — vedi [DB/CLAUDE.md](DB/CLAUDE.md).
Dal 2026-10-21 i ripartitori nei grafici valgono **gli stessi kWh del riparto**: u.r. corrette come nel riparto (K × fattore
di base) × fattore del riparto approvato che copre il mese, altrimenti dello stabile, altrimenti **stima del modello di
ripartitore** (`db_meterTypes.typ_urKwhFactor`, consumi segnalati come stimati su web e app). Allarme 2 chiuso da solo
quando un fattore c'è; nella scheda dello stabile confronto dei consumi della stagione con il fabbisogno di progetto.
L'ACS mensile di un'unità = m³ di acqua calda × 1.162 × (calda − fredda), gli stessi kWh del volontario del riparto ACS:
c'è dal primo giorno, senza generali, totali o bollette.

**Guida** (2026-08-28): pagine descrittive della piattaforma (es. come vengono eseguiti i
riparti acqua/calore). Contenuto = file Markdown in `BE/api/content/guida/` (**non su DB**, per
scelta dell'utente — rivedibile in futuro); endpoint `/api/v1/guida/` di sola lettura, gate
`LOGIN`. FE: icona "?" in TopNav → `/guida` (indice) → `/guida/[slug]`, renderer Markdown
interno senza dipendenze (`FE/src/components/hm/Markdown.tsx`). Non modifica alcun
comportamento esistente. Vedi [BE/api/CLAUDE.md](BE/api/CLAUDE.md) → *Guida*.

**App installatore** (2026-09-19, in realizzazione a fasi F0–F7): app Android standalone (`INSTALLERAPP/`) per
registrare i dispositivi nelle unità di uno stabile "cantiere" (dal 2026-09-30 `db_buildingsHead.bld_flags` bit0, non più lo stato `-1`), assegnato all'installatore
dal back office (`rel_bldInstaller`). Accesso `application=4` (gate `TECHLOGIN`) con access token 60 min + chiave di
rinnovo 30 giorni; sincronizzazione offline-first, "ultima modifica vince", operazioni idempotenti; dove non può
scrivere direttamente l'installatore **propone** e il back office approva (`/proposals`); convalida in blocco dello
stabile dalla piattaforma. Nessun nuovo bit di grant: si estende `OWN_CREATED_BUILDINGS` (GRANT.md §4.4). Contratto
congelato e dettagli: [BE/api/CLAUDE.md](BE/api/CLAUDE.md) → *App installatore*; DB: `DB/SRC/hybrismeter/40_ApiFunctions/46.api_installer.sql`.

**App dell'utente finale** (2026-10-21, `USERAPP/`): app Android con cui l'utente finale consulta dal telefono gli
stessi dati del web (letture, consumi, autoletture con foto, guida, account), con stile, accesso, aggiornamento
automatico, collegamento dell'invito e pubblicazione copiati dall'app installatore. Accesso `application=2` (gate
`APPLOGIN`, ora nel gruppo 9 `x'00141003'`) con chiave di rinnovo come l'installatore; la password provvisoria
dell'invito vale anche nell'app (che chiede subito la nuova). Nessun endpoint nuovo: le stesse API del web; ultimi dati
consultabili senza rete. L'invito alla piattaforma porta, a chi ha `APPLOGIN`, QR code e link di
`/scarica-app/invito?a=enduser` con l'avviso sull'installazione da fonti esterne. App `enduser` nel registro dei
rilasci. Vedi [USERAPP/CLAUDE.md](USERAPP/CLAUDE.md).

### Ambienti nuova architettura

| Ambiente | FastAPI (BE/api)                 | Next.js (FE)                     | DB Host                                                 |
|----------|----------------------------------|----------------------------------|---------------------------------------------------------|
| LOCAL    | http://localhost:8000            | http://localhost:3000            | localhost                                               |
| TEST     | https://api-test.hybrismeter.it  | https://app-test.hybrismeter.it  | meterdb-test.hybrismeter.it                             |
| PROD     | https://api-prod.hybrismeter.it  | https://app.hybrismeter.it       | hybrismeterdb.cdqq4uckobs1.us-east-1.rds.amazonaws.com |

### Variabili d'ambiente

**BE/api `.env`:**
```
DB_HOST=
DB_PORT=5432
DB_NAME=hybrismeterdb
DB_USER=
DB_PASSWORD=
DB_SCHEMA=hybrismeter
SECRET_KEY=
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=480
ALLOWED_ORIGINS=http://localhost:3000
```

**FE `.env`:**
```
NEXT_PUBLIC_API_URL=http://localhost:8000/api/v1
```

### Avvio locale

```bash
# Terminale 1 — backend
./start-be.sh

# Terminale 2 — frontend
./start-fe.sh
```

`start-be.sh` (root): attiva `BE/api/venv`, avvia uvicorn con `--reload` su porta 8000.
`start-fe.sh` (root): entra in `FE/`, avvia `npm run dev` su porta 3000.
Entrambi verificano i prerequisiti (.env compilato, venv, node_modules) prima di avviarsi.

---

## Strumenti Python ausiliari

**Repository separato** (2026-09-07): `Strumenti/` non è più sotto `HybrisMeter/`, ma allo stesso
livello — `/dati/Lavoro/=HYBRIS=/Strumenti/`, repo Git proprio `github.com/GiovanniGolfieri/HybrisTools`.

**Vedi:** CLAUDE.md nelle sottodirectory specifiche dove presenti.

| Script                | Directory                              | CLAUDE.md |
|-----------------------|----------------------------------------|-----------|
| `importStabiliDaSheet.py` | `Strumenti/ImportStabiliDaSheet/` | ✅        |
| `creaBollette.py`     | `Strumenti/CreazioneFogliBollette/`    | ✅        |
| `creazionePLT.py`     | `Strumenti/CreazionePLTqundis/`        | —         |
| `creaTecnico.py`      | `Strumenti/CreazioneTecnicoDaRiparto/` | —         |
| `formatBuildSheet.py` | `Strumenti/FormattazioneFogliStabili/` | —         |
| `estrazioneMisure.py` | `Strumenti/EstrazioneMisure/`          | —         |
| `encryptPassword.py`  | `Strumenti/CodificaPassword/`          | —         |
| `pulisciPLT.py`       | `Strumenti/PuliziaPLTqundis/`          | —         |
| `estraiRiparto3RL.py` | `Strumenti/EstrazioneRiparto3RL/`      | —         |

**Pattern comuni a tutti gli script:**
- GUI tkinter, operazioni pesanti in thread separato con `root.after()` per aggiornamenti UI
- Google Sheets API via OAuth2 (`credentials.json` + `token.json` in ogni directory)
- Hashing password con `bcrypt` (10 rounds) dove necessario

---

## Ambienti di deploy

| Ambiente | DB Host                                                   | Note                           |
|----------|-----------------------------------------------------------|--------------------------------|
| LOCAL    | `localhost`                                               | sviluppo locale, utente `golf` |
| TEST     | `meterdb-test.hybrismeter.it`                             | server di test                 |
| PROD     | `hybrismeterdb.cdqq4uckobs1.us-east-1.rds.amazonaws.com` | AWS RDS, SSL obbligatorio      |

Chiavi SSH:
- TEST: `/dati/Lavoro/=HYBRIS=/Accessi/Chiavi/HybrisTEST.pem`
- PROD: `/dati/Lavoro/=HYBRIS=/Accessi/Chiavi/HybrisPROD.pem`

---

## Versione

**Un solo numero per DB, BE, FE, app installatore e app utente**: `MAGGIORE.MINORE.COMPILAZIONE`, con `0.` davanti finché non c'è
il primo rilascio ufficiale. Ogni repository ha un file `VERSION` alla radice; l'hook `pre-commit` comune
(`.githooks/`, attivato con `./version.sh install` → `core.hooksPath`) a ogni commit porta COMPILAZIONE al massimo dei
cinque repository + 1 e mette il file nel commit. COMPILAZIONE non si azzera mai (è il `versionCode` Android).

- `./version.sh` = versioni attuali e prossimo numero; `./version.sh set 0.8` = il prossimo commit di **ogni** repository
  avrà `0.8.<compilazione>` (stesso numero ovunque: è il modo di allineare tutto a un rilascio) e un MINORE nuovo azzera
  `DB/SRC/þ-deploy/changesLIST.txt` (`reset.sh`); `./version.sh set 0.8.300` = valore esatto (la compilazione può solo
  crescere, l'hook rifiuta il contrario). Si può anche modificare a mano `VERSION` prima del commit.
- Dove si vede: piattaforma in fondo al menu utente (e in login), app nella schermata di accesso e in Impostazioni,
  `GET /api/v1/version` (BE + versione del DB scritta dal deploy F in `loo_appConfig 'platformVersion'`).
- **Versioni delle app** (2026-10-01): archivio `db_appReleases` + file sul server, gestito da Configurazione → Sistema →
  Rilasci app (HANDLE_ROOT), pubblicazione con `INSTALLERAPP/þ-deploy/publish.sh`, primo scaricamento dalla pagina pubblica
  `/scarica-app` (credenziali di un utente abilitato all'app), aggiornamento proposto dall'app all'avvio e obbligatorio
  quando il BE risponde 426. Dettagli: [BE/api/CLAUDE.md](BE/api/CLAUDE.md), [FE/CLAUDE.md](FE/CLAUDE.md),
  [INSTALLERAPP/CLAUDE.md](INSTALLERAPP/CLAUDE.md).

## Test

**Un solo comando: `./run-tests.sh`** (dalla radice, ~25 secondi) — esegue tutta la batteria **senza mai toccare un
database reale**. Quando l'utente chiede di «eseguire i test», si lancia questo, non i pezzi.

| Livello | Cosa fa | Dove |
|---------|---------|------|
| `db` | test SQL su un database **usa-e-getta** costruito dai sorgenti + dati sintetici (creato e poi eliminato) | `DB/SRC/hybrismeter/80_Tests/` — vedi [DB/CLAUDE.md](DB/CLAUDE.md) → *Test DB* |
| `be` | pytest di `BE/api` (DB simulato) + rete di sicurezza generata da tutte le rotte (401 senza token, 403 senza il grant) | `BE/api/tests/` |
| `live` | il vero BE (uvicorn) avviato contro lo **stesso DB usa-e-getta**: tutti i GET con login reale + flusso app installatore + **ambito dell'utente finale** (scenario `97`, 109 controlli: proprie unità, cambio di inquilino, misuratore sostituito, flag di accesso, amministratore + utente finale, non regressione del personale) + **ambito dell'amministratore di condominio** (scenario `98`, 93 controlli: mandato aperto/chiuso/futuro, cambio di amministratore) | `BE/api/tests/smoke_live.py`, `smoke_enduser.py`, `smoke_condo.py` |
| `svc` | test node di `BE/consumption-service` (quiete per stabile, calendario notturna/verifica mensile); la parte DB è nel livello `db` (test 96) | `BE/consumption-service/tests/` |
| `fe` | `tsc --noEmit` (vincolo) + eslint (solo informativo: ~1380 segnalazioni storiche) | `FE/` |
| `installerapp` | test unitari JVM dell'app Android (`gradlew testDebugUnitTest --offline`); gli `androidTest` richiedono un dispositivo e NON girano | `INSTALLERAPP/` |
| `userapp` | test unitari JVM dell'app dell'utente finale | `USERAPP/` |

`./run-tests.sh --only db,be` per un sottoinsieme (livelli: `db,be,live,svc,fe,installerapp,userapp`); `--update-golden` solo dopo aver rivisto un cambio voluto dei numeri
dei riparti (poi committare `DB/SRC/hybrismeter/80_Tests/golden/*.csv`). Il server di prova è localhost salvo
`HM_TEST_HOST/PORT/USER/PASSWORD`. Ogni nuova stored function `api_*` o endpoint va coperto: i nuovi endpoint lo sono già
per autenticazione/grant grazie a `test_route_security.py`; per la logica aggiungere un test in `80_Tests/9x` o in `BE/api/tests/`.

**Verifiche nel browser (Playwright) — vincolo:** usare **Brave**, non Chrome, e sempre con cache isolata:
`chromium.launch({ executablePath: '/opt/brave.com/brave/brave', args: ['--no-sandbox'], env: { ...process.env, XDG_CACHE_HOME: '<scratchpad>/xdg-cache' } })`.
Chrome (154) incorpora una fontconfig più nuova di quella di Kubuntu 26.04 e scrive in `~/.cache/fontconfig` file
`cache-12` e collegamenti `cache-9 → cache-12` che fanno andare in crash plasmashell e il blocco schermo (sblocco solo
con `loginctl unlock-session`): successo il 2026-09-24 alle 10:54 e alle 00:24. Dal 2026-09-25 anche Brave (1.96) fa lo
stesso: la cache isolata è quindi **indispensabile**, mai lanciare un browser Chromium senza `XDG_CACHE_HOME` deviata.

---

## Convenzioni generali

- **Nomi colonne PostgreSQL:** sempre lowercase (PostgreSQL abbassa i nomi non quotati).
  Es: `uiD_rowID` → accessibile come `uid_rowid` nelle query.
- **Nomi funzioni DB:** prefisso `db` + PascalCase (es. `dbSetMeasure`, `dbGetBuildings`)
- **Nomi viste DB:** suffisso `Det` o `Head` per distinguere viste di dettaglio da testata
- **File `.env`:** mai committare. Ogni componente ha il suo `.env` locale.
- **Credenziali Google OAuth2:** `credentials.json` + `token.json` — mai committare.
- **Logica applicativa:** risiede nelle stored functions PostgreSQL.
  BE/api non deve duplicarla, solo chiamarla.
- **Terminologia dei servizi:** il servizio estivo si chiama sempre **Raffrescamento** (sigla `RAFF`), in piattaforma,
  app installatore, fogli e script; mai «Raffreddamento» o «Condizionamento». «Climatizzazione» = riscaldamento e
  raffrescamento insieme. «Raffreddamento» resta solo nelle citazioni testuali di legge (D.Lgs. 102/2014, 73/2020).
- **Lingua:** tutte le comunicazioni tra AI e operatore devono essere in italiano,
  mentre nel codice si deve sempre usare la lingua inglese (commenti, nomi variabili e altro),
  a meno che non sia diversamente indicato in modo esplicito.
  