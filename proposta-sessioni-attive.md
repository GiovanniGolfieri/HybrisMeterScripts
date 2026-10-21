# Proposta — Tabella sessioni / token attivi

Stato: **fasi 0, 1 e 2a realizzate** (2026-08-27); restano 2b, 3 e 4 (elenco in `residui.md` §5) · Data: 2026-08-27,
stato aggiornato al 2026-10-10 · Ambito: DB + BE/api + FE

> Dal 2026-09-19 l'app installatore usa già un access token breve con chiave di rinnovo ruotante (`api_SessionRefresh`) e
> verifica la sessione a ogni richiesta (`get_installer_user`): per lei la revoca è immediata. Quanto segue sulla fase 2b
> riguarda il solo web.

Obiettivo: sostituire il contatore `db_users.usr_status ≥ 1` (fragile, soggetto a
drift) con un conteggio delle connessioni attive **derivato** da una tabella di
sessioni, e abilitare come effetto collaterale il **logout server-side reale** e la
**revoca dei token** — oggi impossibili con l'auth JWT puramente stateless.

---

## 1. Contesto e motivazione

### 1.1 Com'è adesso

- `db_users.usr_status` è un intero sovraccarico: `-2`=bloccato, `-1`=disabilitato,
  `0`=non connesso, `≥1`=numero di connessioni attive.
- `api_LoginConfirm` (dal fix 2026-08-27) incrementa di 1 dopo un login riuscito;
  `api_Logout` decrementa di 1 con guardia `usr_status > 0`.
- L'auth è JWT stateless: un solo access token (`ACCESS_TOKEN_EXPIRE_MINUTES=480`),
  nessun `jti`, nessun refresh token. Il BE non ha modo di sapere che una sessione
  è finita se il FE non chiama `POST /auth/logout`.
- Mitigazione attuale del drift: `FE/src/context/AuthContext.tsx` pianifica un
  logout automatico ~15 s prima della scadenza del token mentre la scheda è aperta.

### 1.2 Perché non basta

Il contatore si muove solo su due eventi espliciti ed entrambi inaffidabili, senza
TTL né heartbeat: ogni incremento non bilanciato resta gonfiato **per sempre**.
Casi non coperti:

- chiusura/crash del browser prima della scadenza del token;
- scadenza naturale del JWT senza logout (auto-logout non scattato: sospensione del
  SO, scheda in background con timer throttled, ecc.);
- più schede sulla stessa sessione (possibile doppio decremento, floor a 0);
- qualunque errore di rete tra la risposta di login e il salvataggio del token lato FE.

Inoltre `usr_status` mescola due concetti (stato-account e conteggio-sessioni) nello
stesso campo, il che complica sia la UI sia ogni query che deve distinguere
"bloccato" da "connesso da 2 postazioni".

---

## 2. Modello dati

### 2.1 Nuova tabella `wrk_userSessions`

Definizione concordata (PK intera `serial`, non uuid — l'`ID` di sessione viaggia nel
JWT come claim `sid`):

```sql
create table wrk_userSessions (
  tb_info                  jsonb             default jsonb_build_object('mkT', current_timestamp)not null          ,  -- tab info: creation and last modification datetime and user (subject), possibly other
  ID                       serial                                     not null          ,  -- table ID
  sbj_id                   integer                                    not null          ,  -- references db_users(sbj_id) on delete cascade,
  ses_application          smallint                                   not null          ,  -- GATE bit used at login (1=WebApp,2=UserApp,4=Installer)
  ses_createdAt            timestamptz       default now()            not null          ,  --
  ses_lastSeenAt           timestamptz       default now()            not null          ,  --
  ses_expiresAt            timestamptz                                not null          ,  -- JWT claim exp
  ses_revokedAt            timestamptz                                                  ,  -- null = alive; valued at logout / revocation / sweep
  ses_revokedReason        text                                                         ,  -- 'logout' | 'expired' | 'admin' | 'superseded'
  ses_ip                   inet                                                         ,  --
  ses_userAgent            text                                                         ,  --
  constraint pk_wrkuserSessions primary key(ID),
  constraint fk_sbjid foreign key(sbj_id) references db_users(sbj_ID) on delete cascade
);
create index ix1_wrkuserSessions on wrk_userSessions(sbj_id)        where ses_revokedAt is null;
create index ix2_wrkuserSessions on wrk_userSessions(ses_lastSeenAt) where ses_revokedAt is null;
```

Note:

- **FK `on delete cascade`** verso `db_users` — voluta (cancello l'utente → spariscono
  le sue sessioni) e coerente con il resto delle relazioni utente. Va comunque
  annotata nel doc-sync (regola: verificare sempre le cascade prima di
  DELETE/DROP su DB reale).
- `tb_info` come da convenzione di progetto (`jsonb_build_object('mkT', current_timestamp)`);
  il trigger `trUpdateTBinfoUPT` mantiene `upt` su UPDATE.
- Indici parziali `where ses_revokedAt is null`: le uniche righe interrogate a caldo
  sono le sessioni vive; le revocate restano solo per storico finché lo sweep non le
  elimina.

### 2.2 "Sessione viva" — definizione

Una sessione conta come attiva se:

```
ses_revokedAt is null
AND ses_lastSeenAt > now() - interval '<SESSION_IDLE_WINDOW>'
```

`SESSION_IDLE_WINDOW` proposto: **15 minuti**, allineato alla cadenza dell'heartbeat
FE (vedi §5.3). Un browser chiuso sparisce dal conteggio entro ~15 min invece di
restare fino alla scadenza del token (8 h). **Decisione da confermare con l'utente.**

### 2.3 Modifica a `v_users`

`21.subjectViews.sql` — `usr_status` resta com'è **durante le fasi 1–2** (dual-write:
`api_LoginConfirm`/`api_Logout` lo muovono ancora); si aggiunge subito una colonna
derivata, che diventa l'unica fonte del badge in fase 3:

```sql
, (select count(*) from wrk_userSessions s
    where s.sbj_id = u.sbj_id
      and s.ses_revokedAt is null
      and s.ses_lastSeenAt > now() - interval '15 minutes')   as usr_liveSessions
```

`loo_userStates` (lookup `-2..1`) resta invariata per il significato di stato-account.

---

## 3. Stored functions (`41.api_access.sql`)

Tutte con la firma standard `(p_user integer, p_body jsonb) → jsonb` e output
`{"##":0,"@@":...}`.

| Funzione | Body in | Ritorno | Chiamata da |
|----------|---------|---------|-------------|
| `api_SessionOpen`   | `{application, expiresAt, ip, userAgent}` | `{"id": <ID>}` | BE `/auth/login`, dopo `verify_password` |
| `api_SessionTouch`  | `{id}` | `{"live": true}` oppure `##<0` | BE `/auth/ping` (e, in fase 2b, la dependency di ogni richiesta) |
| `api_SessionClose`  | `{id, reason}` | `null` | BE `/auth/logout`, `/auth/logout-beacon` |
| `api_SessionList`   | `{sbj_id?, grants?, currentId?}` | `[{id, application, createdAt, lastSeenAt, live, ip, userAgent, current}]` | BE `/auth/sessions` |
| `api_SessionRevoke` | `{id}` \| `{sbj_id, all:true}` + `{grants?}` | `{"revoked": n}` | BE `DELETE /auth/sessions/...` |
| `api_SessionSweep`  | — (p_user null ammesso) | `{"expired": n, "purged": n}` | job schedulato (§6) |

Dettagli chiave:

- **`api_SessionTouch`** — verifica che la riga esista, appartenga a `p_user`, non sia
  revocata né oltre `ses_expiresAt`; se non viva ritorna `##<0` (→ il BE risponde
  401 e il FE fa logout). L'`UPDATE` di `ses_lastSeenAt` è **throttled**:
  `... where ID = $1 and ses_lastSeenAt < now() - interval '60 seconds'` →
  al massimo una scrittura al minuto per sessione, per evitare write amplification e
  bloat della tabella.
- **`api_SessionClose`** — idempotente: `... where ID = $1 and ses_revokedAt is null`
  (chiusure concorrenti da più schede non fanno danni).
- **`api_SessionList` / `api_SessionRevoke`** — sulle **proprie** sessioni sempre
  consentite; su quelle di un altro utente richiedono `VIEW_USER` (list) /
  `EDIT_USER` (revoke): il BE verifica con `require_grant`, il DB ricontrolla contro
  i `grants` passati nel body (stesso pattern di `api_GetUsers`). `current` nel list =
  la sessione (`currentId`) del token con cui sto chiamando, per non farmi
  "terminare" da solo per sbaglio.
- **`api_SessionSweep`** — due fasi: (a) marca `ses_revokedAt=now(),
  ses_revokedReason='expired'` dove `ses_revokedAt is null and (ses_expiresAt < now()
  or ses_lastSeenAt < now() - interval '<grace>')`; (b) `DELETE` delle righe con
  `ses_revokedAt < now() - interval '30 days'` (retention: mantiene lo storico
  recente per audit, tiene piccola la tabella).

### 3.1 Funzioni ritirate a fine rollout (fase 3)

- `api_LoginConfirm` → sostituita da `api_SessionOpen`.
- `api_Logout` → sostituita da `api_SessionClose`.

Restano vive durante le fasi 1–2 (dual-write, §7): `/auth/login` chiama **sia**
`api_LoginConfirm` **sia** `api_SessionOpen`; `/auth/logout` **sia** `api_Logout`
**sia** `api_SessionClose`. Così `usr_status` continua a funzionare come prima finché
il conteggio da `wrk_userSessions` non è verificato, poi in fase 3 si rimuovono le due
funzioni e si riporta `usr_status` a dominio `{-2,-1,0}`.

---

## 4. Modifiche BE/api

### 4.1 `core/security.py`

- `create_access_token(data, session_id: int | None = None)` — aggiunge
  `payload["sid"] = session_id` quando presente.

### 4.2 `core/config.py`

- Nuova costante `SESSION_IDLE_WINDOW_MINUTES` (default 15).

### 4.3 `core/deps.py` — **fase 2b (rimandata)**

- Nuova dependency `get_current_session(conn, user)` che chiama
  `api_SessionTouch({id: user["sid"]})`; se `##<0` → `HTTPException(401)`.
- `require_grant(bit)` passa a dipendere da `get_current_session` — **unico punto di
  modifica**, tutti gli endpoint la ereditano.

> Costo: +1 query DB per richiesta autenticata (mitigato dal throttle sull'`UPDATE`).
> **Non incluso nel primo giro**: nel primo giro l'unica cosa che aggiorna
> `ses_lastSeenAt` è l'heartbeat FE via `/auth/ping`; una sessione revocata
> dall'admin viene espulsa al ping successivo (≤ intervallo heartbeat), non
> istantaneamente. Basta e avanza per il conteggio; la revoca "immediata" è il
> contenuto di 4.3.

### 4.4 `api/v1/endpoints/auth.py`

- `POST /auth/login` — inietta `Request`. Dopo `verify_password`: **dual-write** —
  `await queries.db_login_confirm(...)` (invariato) **e**
  `sid = await queries.session_open(conn, user_id, {application, expiresAt,
  ip=request.client.host, userAgent=request.headers.get('user-agent')})`; poi
  `create_access_token({...}, session_id=sid)`.
- `POST /auth/logout` — **dual-write**: `await queries.db_logout(...)` (invariato)
  **e** `await queries.session_close(conn, user_id, {id: user["sid"],
  reason: "logout"})` quando il token porta `sid`.
- `POST /auth/ping` (grant LOGIN, `204`) — `await queries.session_touch(conn,
  user_id, user["sid"])`; `##<0` → 401. È l'endpoint colpito dall'heartbeat FE.
- `POST /auth/logout-beacon` — body `{token}` (niente header `Authorization`, perché
  `navigator.sendBeacon` non lo imposta); verifica il token, estrae `sid`, chiama
  `session_close`. Nessun grant (il token è la prova).
- `GET /auth/sessions` — proprie sessioni; `?user_id=` per quelle altrui
  (`require_grant(VIEW_USER)`). → `session_list`.
- `DELETE /auth/sessions/{id}` — revoca una sessione (propria, o altrui con
  `EDIT_USER`). → `session_revoke`.
- `DELETE /auth/sessions?user_id=N` — revoca tutte le sessioni di un utente. →
  `session_revoke {sbj_id, all:true}`.

### 4.5 `db/queries.py`

Wrapper tipizzati: `session_open`, `session_touch`, `session_close`, `session_list`,
`session_revoke` (pattern identico agli esistenti `db_*`).

### 4.6 Test (`tests/`)

- `test_auth.py` — login mette `sid` nel token; logout chiama `api_SessionClose` con
  l'`id` giusto; `/auth/ping` senza token → 401.
- `test_sessions.py` (nuovo) — list/revoke scope: senza `VIEW_USER` non si vedono le
  sessioni altrui; revoca altrui senza `EDIT_USER` → 403; flag `current` corretto.

---

## 5. Modifiche FE

### 5.1 `context/AuthContext.tsx`

- Aggiunge un heartbeat: `setInterval` ogni `SESSION_PING_INTERVAL` (~5 min) che, **solo
  se `document.visibilityState === 'visible'`**, chiama `POST /auth/ping`.
- Su risposta 401 dal ping → `logout()` forzato (la sessione è stata revocata altrove
  o è scaduta): copre il caso "l'admin mi ha disconnesso".
- L'auto-logout pre-scadenza esistente **resta** come rete di sicurezza.

### 5.2 Chiusura scheda

- Listener su `pagehide` e `visibilitychange`→`hidden`: `navigator.sendBeacon(
  '/api/v1/auth/logout-beacon', new Blob([JSON.stringify({token})], {type:
  'application/json'}))`. Best-effort, non blocca la chiusura.
- Nota: `sendBeacon` non garantisce la consegna al 100% (né su crash del processo) —
  per questo il **sweep** lato DB (§6) resta indispensabile come fallback.

### 5.3 Costanti

`SESSION_PING_INTERVAL` (FE) deve essere **minore** di `SESSION_IDLE_WINDOW` (BE): con
15 min di finestra, ping ogni 5 min lascia margine per due ping persi prima che la
sessione risulti idle.

### 5.4 UI — **fase 4 (rimandata)**

- `cnf/usergroups/page.tsx` — il badge stato continua a mostrare `Attivo` /
  `Connesso [n]`, ma `n` ora viene da `usr_liveSessions`. Riga espandibile o modale
  "Sessioni" (gated `VIEW_USER`) che elenca `api_SessionList`: applicazione, IP,
  user-agent, ultima attività, pulsante "Termina" (gated `EDIT_USER`) e "Termina
  tutte". `DataSourceTag` → `source="wrk_userSessions"`.
- Pagina Account dell'utente (`user-card`) — sezione "Le mie sessioni" con lo stesso
  elenco sulle proprie sessioni + "Disconnetti le altre".

---

## 6. Job di pulizia sessioni

Serve qualcosa che chiami `api_SessionSweep()` periodicamente (ogni ~5 min), perché
`sendBeacon` e l'auto-logout FE non coprono crash/spegnimenti.

Opzioni, in ordine di preferenza:

1. **`pg_cron`** sul DB (RDS lo supporta via parameter group):
   `select cron.schedule('session-sweep', '*/5 * * * *', $$select api_SessionSweep()$$);`
   — zero infrastruttura extra, gira anche se il BE è giù. **Da verificare che
   `pg_cron` sia abilitato sul parameter group RDS PROD**; in locale va aggiunto a
   `shared_preload_libraries`.
2. Task asincrono nel `lifespan` di FastAPI (`asyncio` loop con `asyncio.sleep(300)`)
   — nessuna dipendenza, ma non gira se il BE è fermo e si moltiplica se ci sono più
   worker uvicorn (mitigabile con un advisory lock).
3. Cron di sistema che chiama un endpoint interno protetto.

---

## 7. Rollout per fasi

| Fase | Contenuto | Effetto osservabile |
|------|-----------|---------------------|
| **0** ✅ | Fix "login falliti non incrementano" (2026-08-27) | Niente più drift da password errata |
| **1 + 2a** ✅ (2026-08-27) | Schema `wrk_userSessions` + `api_Session{Open,Touch,Close,List,Revoke,Sweep}` + `v_users.usr_liveSessions` + wrapper BE. **Dual-write**: `/auth/login` chiama sia `api_LoginConfirm` sia `api_SessionOpen`; `/auth/logout` sia `api_Logout` sia `api_SessionClose`. Nuovi endpoint `/auth/ping`, `/auth/logout-beacon`, `GET/DELETE /auth/sessions`. Heartbeat FE + `sendBeacon`. Badge `cnf/usergroups` **ancora su `usr_status`**. | `wrk_userSessions` popolata; `usr_liveSessions` deve combaciare con `usr_status` nel tempo; browser chiuso sparisce da `usr_liveSessions` entro `SESSION_IDLE_WINDOW` |
| **2b** | `get_current_session` agganciata a `require_grant` (touch + validazione revoca a ogni richiesta autenticata). Job `api_SessionSweep` schedulato (§6). | Revoca sessione **immediata** (non al prossimo ping); `ses_lastSeenAt` fresco anche senza heartbeat |
| **3** | Badge `cnf/usergroups` passa a `usr_liveSessions`. Si **eliminano** `api_LoginConfirm` e `api_Logout`; `/auth/login` e `/auth/logout` restano solo con le `api_Session*`. `usr_status` torna a dominio `{-2,-1,0}`. Migrazione: `update db_users set usr_status = 0 where usr_status > 0`. | `usr_status` di nuovo pulito; una sola fonte di verità per il conteggio |
| **4** (poi) | UI elenco sessioni + "termina tutte" + pagina "Le mie sessioni". Eventuale modello refresh-token (access token corto + refresh che fa da touch). | Visibilità e controllo per operatore e utente finale |

Le fasi 1–3 sono tutte deploy **A** (schema) + **F** (funzioni); la fase 3 include un
`update` di migrazione una tantum in `þ-deploy/alter/`.

---

## 8. Rischi e decisioni aperte

| # | Tema | Nota / mitigazione | Serve decisione utente |
|---|------|--------------------|:---:|
| 1 | Costo +1 query/richiesta | Throttle sull'`UPDATE`; misurare in fase 2; eventuale cache in-process TTL 30 s | — |
| 2 | Lunghezza `SESSION_IDLE_WINDOW` | Proposto 15 min (heartbeat 5 min) | ✅ |
| 3 | `pg_cron` su RDS | Verificare parameter group; fallback = task nel lifespan con advisory lock | — |
| 4 | `sendBeacon` invia il token nel body | Stesso token già in `localStorage`; comparirà nei log applicativi del BE — valutare se offuscarlo in logging | ✅ |
| 5 | Privacy IP + user-agent | Dato operativo di sicurezza; retention 30 giorni via sweep (DELETE, non solo marcatura) | ✅ |
| 6 | Crescita tabella | Sweep con DELETE oltre retention; se il volume cresce molto, valutare partizionamento per mese | — |
| 7 | Skew orologio BE/DB | Usare sempre `now()` del DB per i confronti di scadenza, mai `datetime.now()` del BE | — |
| 8 | Race multi-scheda su close | `api_SessionClose` idempotente (`where ses_revokedAt is null`) | — |

---

## 9. Checklist doc-sync

Fatto per fasi 1+2a (2026-08-27): `DB/CLAUDE.md`, `BE/api/CLAUDE.md`, `FE/CLAUDE.md`, foglio «Hybris - Database
structure» (`wrk_userSessions`).

---

## 10. Riepilogo file toccati

**DB** (fasi 1+2a — fatto)
- `10_Tables/11.tbhybrismeter.sql` — `wrk_userSessions` + commenti colonna
- `þ-deploy/alter/alter-hybrismeter.sql` — stessa DDL per deploy incrementale T/P
- `20_Views/21.subjectViews.sql` — `v_users.usr_liveSessions`
- `40_ApiFunctions/41.api_access.sql` — `api_Session{Open,Touch,Close,List,Revoke,Sweep}` (in fase 3: rimozione `api_LoginConfirm`/`api_Logout`)

**BE/api** (fasi 1+2a — fatto)
- `core/security.py` — claim `sid`
- `core/config.py` — `SESSION_IDLE_WINDOW_MINUTES`
- `api/v1/endpoints/auth.py` — login/logout dual-write, `/auth/ping`, `/auth/logout-beacon`, `GET/DELETE /auth/sessions`
- `models/auth.py` — `SessionInfo`
- `db/queries.py` — wrapper `session_*`
- `tests/test_auth.py`, `tests/test_sessions.py`
- **fase 2b:** `core/deps.py` — `get_current_session`, `require_grant`

**FE** (fasi 1+2a — fatto)
- `context/AuthContext.tsx` — heartbeat `/auth/ping` + `sendBeacon` su `pagehide` + reazione a 401
- `types/api.ts` — tipo `Session`
- **fase 3/4:** `app/(dashboard)/cnf/usergroups/page.tsx` — badge da `usr_liveSessions` + modale sessioni; pagina Account — "Le mie sessioni"
- `types/api.ts` — tipi `Session`
