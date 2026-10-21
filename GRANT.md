# GRANT.md — Specifica di riorganizzazione del sistema permessi

> Stato: **specifica operativa, chiusa** — tutti i punti aperti (§4.2 blocco
> `db_meters`/anagrafiche soggetto, §5 assegnazioni `ALARMS`/`SUBJECTS`/`VIEW_ALLOC`)
> confermati in sessione di revisione del 2026-08-03. **Seconda passata, stesso giorno
> (verifica pre-esecuzione)**: verificato a codice che il ramo SCOPE di §4.2 non esiste
> ancora nelle 5 funzioni di scrittura coinvolte (`api_SetBuildingDet`,
> `api_NewBuildingDet`, `api_SetUnitDetail`, `api_SetMeter`, `api_SetMeasure`) — va
> scritto ex novo, non solo esteso con la condizione di blocco come indicava la stesura
> precedente. Valutata e **scartata** l'ipotesi di spostare quel controllo dal DB al BE:
> per coerenza con il resto della piattaforma (`ALL_BUILDINGS`/`MANAGED_BUILDINGS` sono già
> verificati dentro le funzioni DB ovunque, §2) e col principio generale del progetto
> (logica applicativa nelle stored functions, il BE la chiama e basta), il controllo
> resta nel DB. Corretti anche i nomi reali (`api_SetSubjectSite`/
> `api_SetSubjectContact`, non `SbjSite`/`SbjContact`) e il comando grep di chiusura
> audit di §6 (mancava la variante camelCase `lGrants`/`pGrants`). Pronta per
> l'esecuzione (§9).


---

## 1. Principi (vincolanti per tutta la specifica)

1. **Due sole variabili bitmappate**, per limiti del backend attuale — non quattro, non una:
   - **`coreGrants`** — "cosa posso fare (e su cosa)": autenticazione, ambito dei dati,
     azioni consentite. Consultata da DB e BE. È l'unica trattata in questo documento.
   - **`pageGrants`** — "cosa vedo nel menu": visibilità delle voci di navigazione FE,
     indipendente dal dato sottostante. Consultata solo dal FE. **Non ancora
     implementata come colonna separata** (oggi esiste solo `grp_grants`) e il suo
     dimensionamento resta fuori dallo scope di questa sessione — vedi §7.
2. **I permessi sono governati da singoli flagbit, mai dall'appartenenza a un gruppo.**
   Un gruppo è solo un nome dato a una combinazione di bit; la logica applicativa (DB e
   BE) non deve mai chiedere "questo utente è nel gruppo X?", solo "questo bit è
   acceso?". I gruppi definiti in §5 sono configurazioni di partenza, riassegnabili
   liberamente da chi amministra la piattaforma.
3. Ogni bit ha **un solo significato**, univoco in tutta la piattaforma. Un bit
   riutilizzato con due significati diversi in due punti del codice è per definizione un
   bug (è la causa esatta di almeno tre difetti reali trovati durante l'audit di questa
   sessione, vedi §6).

---

## 2. I tre assi di `coreGrants`

| Asse | Significato | Chi lo consulta | Bit coinvolti |
|------|-------------|------------------|----------------|
| **GATE** | da quale applicazione client posso autenticarmi | `api_Login` (unico punto) | `LOGIN`, `APPLOGIN`, `TECHLOGIN` |
| **CAPABILITY** | quale azione posso compiere su un dominio: sola lettura, o lettura+inserimento+modifica+cancellazione | BE (`require_grant`) | coppie `VIEW/EDIT_*` |
| **SCOPE** | su quale sottoinsieme di record | DB, dentro ogni funzione `api_Get*`/`api_Set*` | `ALL_BUILDINGS`, `MANAGED_BUILDINGS`, `VIEW_ALL_BUILDINGS`, `OWN_UNITS`, `OWN_CREATED_BUILDINGS` |

`HANDLE_ROOT` non appartiene a nessuno dei tre assi sopra: è un bit **PLATFORM**,
riservato a configurazioni di sistema che non riguardano dati di alcun condominio
specifico (vedi §4).

**Regola operativa per ogni funzione `api_Get*`/`api_Set*`:** la catena `if/elsif` che
decide l'ambito dei dati deve testare **solo** bit SCOPE, mai un bit CAPABILITY o GATE
come proxy di ambito. È esattamente la violazione di questa regola ad aver causato i
bug elencati in §6.

---

## 3. Bit — tabella completa

### GATE (invariati)

| Bit | Nome | Significato |
|-----|------|-------------|
| `0x00000001` | `LOGIN` | accesso da WebApp (Next.js) — unico canale oggi attivo |
| `0x00000002` | `APPLOGIN` | accesso dall'app utente finale (`USERAPP`, `application=2`) |
| `0x00000004` | `TECHLOGIN` | accesso da InstallerApp mobile (non ancora esistente) |
| `0x00000008` | *riservato* | — |

### CAPABILITY — **ridotte a due livelli per dominio, bit compattati** (vedi §7 per la
verifica che ha reso possibile la riduzione a VIEW/EDIT; il compattamento è una
conseguenza diretta: con due soli bit per dominio invece di tre, due domini stanno nella
stessa quaterna esadecimale)

| Bit | Nome | Copre |
|-----|------|-------|
| `0x00000010` / `0x00000020` | `VIEW_USER` / `EDIT_USER` | utenti, gruppi, **amministratori** (`rel_bldAdmin`) — non i soggetti anagrafici, vedi `SUBJECTS` |
| `0x00000040` / `0x00000080` | **`VIEW_SUBJECTS`** / **`EDIT_SUBJECTS`** *(nuovo dominio)* | soggetti e anagrafiche (`db_subjects`, `db_sbjSites`, `db_sbjContacts`) — persone/enti indipendentemente dal ruolo di utente piattaforma o amministratore |
| `0x00000100` / `0x00000200` | `VIEW_STRUCT` / `EDIT_STRUCT` | stabili, unità, misuratori, contratti/bollette |
| `0x00000400` | `VIEW_MAP` | **mappa stabili** (`/mappa`, dal 2026-09-25 — prima dipendeva dal solo ambito ALL/MANAGED). Nessun endpoint dedicato: legge `GET /buildings/`, già limitato all'ambito dell'utente, quindi ognuno vede solo i propri stabili. Il clic su un marker apre lo stabile in Stabili (con `VIEW_STRUCT`) o in Letture. `0x00000800` resta libero per un eventuale `EDIT_MAP` |
| `0x00000400`, `0x00000800` | *vuoti* | nessun dominio assegnato per ora |
| `0x00001000` / `0x00002000` | `VIEW_MEASURE` / `EDIT_MEASURE` | **letture e consumi** (`wrk_water/heatReads`, grafici/ricalcolo consumazioni, totali mensili RISC/ACS/RAFF) — non gli allarmi, vedi `ALARMS` |
| `0x00004000` / `0x00008000` | `VIEW_ALLOC` / `EDIT_ALLOC` | riparti — invariato |
| `0x00010000` / `0x00020000` | `VIEW_ALARMS` / `EDIT_ALARMS` | `alr_consumptions` (allarmi consumo per misuratore): `VIEW_ALARMS` sola visualizzazione, `EDIT_ALARMS` tacita/chiude un allarme (`PUT /alarms/{id}`) — separato da `MEASURE` perché un allarme è una segnalazione derivata, non una lettura |
| `0x00040000` | `SELF_READ` | **autoletture** dell'utente finale (2026-10-05): inserisce, corregge ed elimina le proprie letture `Autolettura` (con foto facoltativa del display) sui misuratori installati oggi sulle unità del suo ambito, nel periodo corrente fino a oggi, finché nessun riparto le ha usate (ambito nel DB: `fnSelfReadRange`/`fnSelfReadEditable`, `34.measures.sql`). Bit separato da `EDIT_MEASURE`, che aprirebbe anche importazione, cancellazioni, ricalcolo e totali calore |
| `0x00080000` | *riservato* | margine per un futuro dominio CAPABILITY |

Tutto il blocco CAPABILITY sta ora in bit 4-19 (`0x10`-`0x80000`), compatto — libera per
intero il bit 23-27 come margine SCOPE (vedi tabella SCOPE sotto: la riduzione a bit
25-27 introdotta insieme ad `ALARMS` nella passata precedente è annullata, `ALARMS` ora
vive altrove).

`EDIT_*` copre inserimento, modifica **e** cancellazione (prima erano lettura/modifica/
creazione-cancellazione su tre bit separati). Non esiste un bit CAPABILITY che consenta
di creare senza poter poi correggere ciò che si è creato — cosa che comunque nessun
gruppo, reale o proposto in questo documento, ha mai richiesto (vedi §7). La restrizione
"posso creare ma non toccare ciò che hanno creato altri" resta intatta e vive per intero
sull'asse SCOPE (`OWN_CREATED_BUILDINGS`, §4), mai su CAPABILITY — è precisamente la
separazione degli assi voluta dal principio 2.

**Bit ex-`CREATE_*` (vecchia numerazione, ormai sostituita):** la numerazione compatta
qui sopra **rimpiazza** quella introdotta nella passata precedente (che lasciava
`0x40`/`0x80`/`0x400`/`0x800`/`0x4000`/`0x8000`/`0x40000`/`0x80000` riservati come ex-
`CREATE_*`). Poiché nessun codice è ancora stato scritto per la versione precedente
(§9 non è stato eseguito), non c'è nulla da migrare: questa è la numerazione definitiva
da implementare, quella vecchia non è mai esistita fuori da questo documento.

### SCOPE — **tre bit nuovi**, gli altri due invariati

| Bit | Nome | Significato | Query di riferimento |
|-----|------|--------------|------------------------|
| `0x10000000` | `ALL_BUILDINGS` | tutti i record, senza restrizione (implica sia lettura sia scrittura) | — |
| `0x20000000` | `MANAGED_BUILDINGS` | solo gli stabili amministrati dall'utente | `rel_bldAdmin` (`adm_id = p_user`, `dateEND is null`) |
| `0x00400000` | **`VIEW_ALL_BUILDINGS`** *(nuovo)* | vede tutti i record **in sola lettura** — non implica alcun diritto di modifica | nessun filtro, solo nei rami `api_Get*` |
| `0x00100000` | **`OWN_UNITS`** *(nuovo)* | opera sulle unità immobiliari di cui è proprietario/conduttore | `rel_unitSubject` (`sbj_id = p_user`, `sbj_flags & 1 = 1`, det corrente) |
| `0x00200000` | **`OWN_CREATED_BUILDINGS`** *(nuovo)* | in lettura: solo i record creati dall'utente; **in scrittura: consente sempre l'inserimento, limita modifica/cancellazione ai soli record creati dall'utente e solo finché la riga non è validata/bloccata** | `tb_info->>'mkU' = p_user::text` **oppure**, per unità/misuratori/misure, stabile in cantiere assegnato all'utente (§4.4) — **e** riga non bloccata (vedi §4) |
| `0x00800000`–`0x08000000` | *riservati* | margine per futuri SCOPE (bit 23-27 — margine pieno, `ALARMS` non occupa più questo intervallo dopo il compattamento CAPABILITY di §3) |

`VIEW_ALL_BUILDINGS` è distinto da `ALL_BUILDINGS` apposta: `ALL_BUILDINGS` continua a significare
"nessuna restrizione, né in lettura né in scrittura" (comportamento invariato per i
gruppi che lo hanno già oggi). `VIEW_ALL_BUILDINGS` è la sua metà "sola lettura" — serve
esclusivamente al profilo Installatore (§5) e a qualunque futuro profilo di sola
consultazione ampia senza diritto di modifica generale.

### PLATFORM (invariato)

| Bit | Nome | Significato |
|-----|------|--------------|
| `0x40000000` | `HANDLE_ROOT` | superutente: dettagli tecnici in griglia, configurazione colori/layout — impostazioni di piattaforma, non di singolo condominio |

**Bit 31 (`0x80000000`): non utilizzare.** Coincide con il bit di segno nella
rappresentazione a 32 bit con segno che il FE usa oggi in `hasGrant` (vedi nota tecnica
in §8) — un valore con solo quel bit acceso verrebbe letto come negativo dal FE.

---

## 4. Meccanismo per il nuovo requisito: creare sì, modificare solo il proprio — finché non è validato

**Requisito (rivisto rispetto alla prima stesura, in seguito a lacune segnalate dopo
letture successive):** un utente tecnico che lavora su una struttura (stabile/UI/
misuratore/misura) **o su un'anagrafica soggetto** (persona/ente) deve poter inserire
nuovi dati e modificare quelli inseriti da lui, ma:

1. smette di poterli modificare non appena la riga è **validata** — anche se il
   creatore è lui stesso;
2. un utente con ambito più ampio (`ALL_BUILDINGS`/`MANAGED_BUILDINGS`) deve poter
   modificare ciò che un tecnico più limitato ha creato, ma non viceversa.

### 4.1 Ownership — invariata rispetto alla prima stesura

Ogni tabella ha già `tb_info jsonb`, valorizzato automaticamente da `gl_insert`/
`gl_update` con `mkU` = ID di chi ha creato la riga (vedi `_common/30.fnGlobal.sql:264-267`).
Questo dato esiste già, per ogni riga, da sempre — non serve aggiungere alcuna colonna
di stato "nuovo/validato" solo per l'ownership.

- **INSERT**: nessun controllo di ambito — basta il bit CAPABILITY (`EDIT_STRUCT`/
  `EDIT_MEASURE`, che dopo l'unificazione di §7 copre anche l'inserimento). Non esiste
  ancora una riga da possedere, quindi non c'è nulla da restringere.
- **UPDATE/DELETE** su una riga esistente: consentito se
  `ALL_BUILDINGS` **oppure** (`MANAGED_BUILDINGS` **e** stabile amministrato) **oppure**
  (`OWN_CREATED_BUILDINGS` **e** riga creata dall'utente **e** riga non bloccata — vedi 4.2).
  Altrimenti rifiutato.

### 4.2 Lacuna 1 — blocco dopo validazione (nuovo)

La sola ownership (`mkU`) non basta: non porta nessuna informazione di stato, quindi non
può rappresentare "questa riga è stata validata e va congelata anche per chi l'ha
creata". Serve un secondo dato, indipendente dall'ownership — ma **non serve la
Proposta B originaria per intero** (colonna di stato con macchina a stati completa e
azione di promozione gestita in UI): basta riusare lo stesso pattern già in uso per
`mkU`/`upU`, due nuove chiavi in `tb_info`:

- `tb_info->>'valU'` — ID dell'utente che ha validato la riga
- `tb_info->>'valT'` — timestamp di validazione

Una riga è **bloccata** — solo per chi opera in `OWN_CREATED_BUILDINGS`, mai per
`ALL_BUILDINGS`/`MANAGED_BUILDINGS`, vedi oltre — se **almeno una** delle due condizioni è
vera:

1. **Validazione esplicita**: `tb_info ? 'valU'` è vero. Un supervisore
   (`ALL_BUILDINGS`/`MANAGED_BUILDINGS` sullo stabile, con la CAPABILITY `EDIT_*` già
   posseduta) ha invocato un'azione di validazione dedicata su quella riga. Non serve un
   nuovo bit di grant: la stessa combinazione ambito+capability che oggi consente la
   modifica libera consente anche di validare.
2. **Validazione automatica per uso a valle**: la riga è già stata usata da un riparto
   **stampato o approvato** (`all_state >= 2`, il punto in cui il riparto genera lo
   snapshot immutabile `all_snapshotJSON`, mai più rigenerato — vedi commento su
   `wrk_allocwater.all_state`). Nessuna azione manuale: la riga si blocca da sola.

| Entità | Sorgente del blocco automatico | Stato verifica |
|--------|--------------------------------|----------------|
| Misura (`wrk_waterReads`/`wrk_heatReads`) | riga presente in `wrk_usedWaterMeas`/`wrk_usedHeatMeas` il cui `allocation_ID` punta a un riparto con `all_state >= 2` | ✅ tabelle ponte già esistenti ([[project_delete_stabile]]) — meccanismo esistente, **non modificare** |
| Stabile (`db_buildingsDet`) | riga referenziata come `bldDet_rowID` da `wrk_allocwater`/`wrk_allocheat` con `all_state >= 2` | ✅ FK diretta confermata in `11.tbhybrismeter.sql` |
| Unità immobiliare (`db_unitsDet`) | riga la cui **testata** (`ui_ID`, `db_unitsHead`) è referenziata da `wrk_allocwaterDetUI`/`wrk_allocheatDetUI` il cui `all_ID` punta a un riparto con `all_state >= 2` | ✅ confermato — `wrk_allocwaterDetUI` (`11.tbhybrismeter.sql:1491-1492`), `wrk_allocheatDetUI` (`:1610-1611`). **Nota**: la FK è verso `ui_ID` (testata), non verso il singolo `uiD_rowID`/`db_unitsDet` come ipotizzato nella stesura precedente — il blocco copre quindi tutte le righe Det storiche dell'unità, non solo quella in vigore al momento del riparto |
| Misuratore (`db_meters`) | blocco per transitività: bloccato se almeno una delle sue misure (stessa `mtr_ID`) risulta bloccata secondo la riga sopra | ✅ deciso in sessione di revisione: transitività confermata (non solo validazione esplicita) |
| Anagrafica soggetto (`db_subjects`, `db_sbjSites`, `db_sbjContacts`) *(nuovo requisito, emerso in sessione di revisione)* | — | ✅ verificato: **nessun blocco automatico possibile**. Nessuna tabella di riparto/bolletta referenzia il `sbj_ID` della persona: `wrk_allocwaterDetUI`/`wrk_allocheatDetUI` usano solo `ui_ID`; `db_Bills` non ha colonna `sbj_ID` (collega solo `ctr_ID`→`rel_bldContract`, dove `sbj_ID` è l'edificio); `rel_unitSubject` non è referenziata da alcuna tabella di riparto. Solo validazione esplicita (`tb_info->>'valU'/'valT'`) |

Pattern SQL aggiornato per il ramo `OWN_CREATED_BUILDINGS` (sostituisce quello della prima
stesura):

```sql
-- dentro il ramo UPDATE/DELETE (mai nel ramo INSERT)
if (l_grants & 0x10000000) > 0 then                    -- ALL_BUILDINGS
  null; -- nessuna restrizione, bypassa anche il blocco di validazione
elsif (l_grants & 0x20000000) > 0
  and exists (select 1 from rel_bldAdmin
              where sbj_id = <stabile della riga> and adm_id = p_user and dateEND is null) then
  null; -- MANAGED_BUILDINGS sullo stabile della riga, bypassa anche il blocco di validazione
elsif (l_grants & 0x00200000) > 0
  and (select tb_info->>'mkU' from <tabella> where <pk> = <valore>) = p_user::text
  and not (select coalesce(tb_info ? 'valU', false) from <tabella> where <pk> = <valore>)
  and not exists (<query di blocco automatico per l'entità, vedi tabella sopra>) then
  null; -- OWN_CREATED_BUILDINGS: la riga è sua e non è (ancora) bloccata
else
  raise exception 'privilegi insufficienti per eseguire l''operazione' using errcode = '00001';
end if;
```

Il blocco (esplicito o automatico) **non si applica** ai rami `ALL_BUILDINGS`/
`MANAGED_BUILDINGS`: chi ha ambito pieno o gestisce lo stabile può sempre correggere anche
righe validate — decisione presa in risposta diretta alla domanda posta in sessione.

**Funzioni DB coinvolte:** verificato a codice (sessione di revisione pre-esecuzione,
2026-08-03) che **nessuna** delle funzioni seguenti ha oggi alcun controllo di
grants/scope — sono scritture pure via `gl_insert`/`gl_update`. Il ramo `if/elsif`
completo sopra (non solo la condizione "non bloccata") va **scritto ex novo** in
`api_SetBuildingDet`, `api_NewBuildingDet`, `api_SetUnitDetail`, `api_SetMeter`,
`api_SetMeasure` — le tabelle Det/misura per cui il blocco automatico ha un riscontro
nella tabella sopra. Questo richiede che il BE inizi a passare `grants` nel body/
parametro di chiamata a queste funzioni (oggi non lo fa).
`api_SetBuildingHead`, `api_SetUnitHead`, `api_SetUnitSubject`, `api_SetMeterTypes`
restano con la sola condizione di ownership (4.1): sono anagrafiche di testata, non
hanno un equivalente diretto di "riga usata in un riparto stampato".

Stesso trattamento (ownership 4.1 + blocco **solo esplicito**, mai automatico — per il
motivo verificato nella tabella sopra) va esteso a `api_SetSubject`,
`api_SetSubjectSite`, `api_SetSubjectContact` (nomi reali delle funzioni — verificati in
`40.api_config.sql:205,309,391`): queste tre **hanno già** un gate piatto
`if (l_grants & 0x10000000) = 0 then raise exception...` (solo `ALL_BUILDINGS`), da
**estendere** (non creare da zero) alla catena ownership 4.1 + blocco esplicito. Nessun
gruppo definito in §5 combina oggi `EDIT_SUBJECTS` con `OWN_CREATED_BUILDINGS` (solo
l'Installatore, grp 4, ha `OWN_CREATED_BUILDINGS`, ed è esplicitamente escluso da
`SUBJECTS`), quindi il ramo ownership non si attiva per nessun profilo attuale —
l'estensione è comunque a costo marginale e rende il meccanismo coerente per un futuro
gruppo che unisse le due cose, senza bisogno di rivedere questa specifica.

Nuove funzioni per la validazione esplicita (elenco chiuso, stesso requisito di grant
della `api_Set*` corrispondente — `ALL_BUILDINGS`/`MANAGED_BUILDINGS` + `EDIT_*` — scrivono
solo `tb_info.valU`/`valT`): `api_ValidateBuildingDet`, `api_ValidateUnitDetail`,
`api_ValidateMeter`, `api_ValidateMeasure`, `api_ValidateSubject`,
`api_ValidateSubjectSite`, `api_ValidateSubjectContact` (nomi corretti).

Resta fuori scope, non necessaria per il requisito così come posto: un'azione di
"annulla validazione" simmetrica al reopen dei riparti ([[project_period_versioning_gap]]).
Se servirà, è un'aggiunta successiva isolata (rimuove `valU`/`valT` da `tb_info`), non
richiede di rivedere questa specifica.

### 4.3 Lacuna 2 — gerarchia tecnico/supertecnico (nessun meccanismo nuovo richiesto)

Già risolta dalla combinazione di ambiti definita in §5, va solo resa esplicita qui
perché la prima stesura la lasciava implicita: `ALL_BUILDINGS` scavalca sempre il
confronto `mkU` (è il ramo valutato per primo nell'`elsif` di 4.1/4.2), quindi un
utente con `ALL_BUILDINGS` (Ufficio Tecnico, grp 3 — il "supertecnico") può modificare
righe create da un utente con solo `OWN_CREATED_BUILDINGS` (Installatore, grp 4 — il
"tecnico"). Il contrario non vale: chi ha solo `OWN_CREATED_BUILDINGS` è limitato dal
confronto `mkU = p_user`, quindi non può toccare righe create da altri, supertecnico
incluso. **Nessun bit nuovo, nessuna modifica al pattern SQL oltre a quella di 4.2** —
è già una proprietà dell'ordine dei rami nell'`elsif`.

Se in futuro servissero più di due livelli (es. un "tecnico senior" che scavalca solo
alcuni tecnici ma non tutti), il meccanismo attuale non basta — richiederebbe un
concetto di gerarchia fra utenti che oggi non esiste nello schema (`db_users` non ha un
campo "supervisore"). Non necessario per il requisito posto in questa sessione: **non
implementarlo ora.**

### 4.4 Cantieri assegnati all'installatore (2026-09-19, app installatore)

`OWN_CREATED_BUILDINGS` non cambia di bit, ma cambia il significato di "riga propria" per **unità, misuratori e
misure**: oltre alle righe create dall'utente (`tb_info->>'mkU'`), sono "proprie" **tutte** le righe di uno stabile
che (a) è un **cantiere aperto** e attivo (dal 2026-09-30 `db_buildingsHead.bld_flags` bit0 con `bld_state` 1 — prima era
lo stato -1 CANTIERE, eliminato) e (b) è assegnato all'utente con una riga **aperta**
(`dateEND is null`) in `rel_bldInstaller`, a prescindere da chi le ha create. Restano identici i limiti: la riga non
deve essere validata (`tb_info ? 'valU'`) né bloccata da un riparto stampato/approvato (`all_state >= 2`, calcolato
dal chiamante secondo l'entità). Effetto: quando il cantiere si chiude (Convalida, completamento dichiarato da tutti gli
installatori assegnati, o a mano dalla piattaforma), lo stabile viene sospeso/chiuso o l'assegnazione viene chiusa,
l'installatore perde da solo i diritti di scrittura.

- **Nessuna estensione ai livelli di stabile:** testata (`api_SetBuildingHead`), periodi (`api_SetBuildingDet`,
  `api_NewBuildingDet`, `api_ReopenBuildingDet`) restano modificabili dall'installatore solo se creati da lui —
  altrimenti potrebbe cambiare lo stato dello stabile (attivarlo da solo) o i suoi dati tecnici.
- **Unica autorità:** `fnOwnRowAllowed(p_user, p_grants, p_sbj, p_tbinfo, p_viaSite)` in
  `30_WrkFunctions/38.installerScope.sql` (`p_viaSite = true` per unità/misuratori/misure). Sostituisce il predicato
  che era duplicato inline in 10 punti: `api_SetBuildingHead/Det`, `api_NewBuildingDet`, `api_SetUnitHead/Detail/
  Subject`, `api_SetMeter`, `api_SetMeasure` (solo UPDATE), `api_ReopenBuildingDet/UnitDetail`. `api_SetBuildingDoc`
  mantiene il proprio controllo (solo creatore).
- **`api_NewUnitDetail`** non aveva alcun controllo di ambito (e il BE non passava `grants`): ora ha lo stesso blocco
  di `api_SetUnitDetail`; l'endpoint `POST /units/{ui_id}/det/new` passa `grants` (BE e funzione vanno rilasciati insieme).
- **Test:** `80_Tests/90.test_installerScope.sql` (matrice: creatore, assegnato, non assegnato, assegnazione chiusa,
  stabile non in cantiere, riga validata, riga bloccata da riparto, livello stabile, ALL/MANAGED, api_NewUnitDetail,
  letture).
- **Lettura:** non si allargano i getter generici a `VIEW_ALL_BUILDINGS` (esporrebbero anagrafiche): l'app usa la
  funzione dedicata `api_GetInstallerSnapshot` (fase F3, 2026-09-19): testate leggere di tutti gli stabili visibili
  (`ALL_BUILDINGS`/`VIEW_ALL_BUILDINGS`: tutti; `MANAGED_BUILDINGS`: i propri; altrimenti gli assegnati e quelli creati
  dall'utente) e dettaglio completo degli stabili assegnati e di quelli richiesti dall'app con `include` (stabili non
  assegnati su cui l'installatore aggiunge e propone: scaricati su richiesta); per le unità solo i **nomi** dei proprietari (mai
  recapiti, sedi, codici fiscali). Ogni riga porta `lock` (`allocation`/`validated`) ed `editable` calcolati con la
  stessa regola delle funzioni di scrittura.
- **Proposte (2026-09-19):** dove l'installatore non può scrivere direttamente (stabile non assegnato o non in cantiere,
  riga creata da altri, riga validata) può **proporre** modifica o eliminazione di unità e misuratori
  (`api_ProposeChange`; serve `OWN_CREATED_BUILDINGS`). La proposta non cambia nulla finché non è approvata da chi ha
  `ALL_BUILDINGS`, oppure `MANAGED_BUILDINGS` sul proprio stabile (`api_ResolveChangeProposal`): l'applicazione passa dalle
  stesse `api_Set*` con l'**approvatore** come utente e i suoi grants, quindi ogni controllo e blocco del DB resta valido.
  Le letture non sono mai proposte. L'installatore vede solo le proprie proposte (`api_GetChangeProposals`).
- **Convalida in blocco (2026-09-19):** `api_ValidateBuilding` (`ALL_BUILDINGS`, o `MANAGED_BUILDINGS` sullo stabile)
  scrive `valU`/`valT` sulle righe che un installatore poteva ancora modificare, tramite le stesse funzioni di
  convalida per riga; le righe già bloccate da un riparto sono "già bloccate", non errori. Il passaggio ad Attivo è
  sempre consentito e chiude le assegnazioni aperte.
- **Applicazione delle operazioni dell'app:** `api_InstallerApplyOp` richiede `OWN_CREATED_BUILDINGS` o `ALL_BUILDINGS`.

### Ambito di lettura (VIEW) per lo stesso profilo

Un tecnico deve poter *vedere* uno stabile esistente per orientarsi (evitare doppioni,
capire dove installare un nuovo misuratore) anche se non può modificarlo. Per questo il
profilo Installatore (§5) riceve `VIEW_ALL_BUILDINGS` in lettura, distinto e indipendente da
`OWN_CREATED_BUILDINGS` in scrittura — vedi la distinzione fra i due bit in §3. Il blocco di
4.2 non riguarda la lettura: una riga validata resta visibile a chi la vedeva prima.

---

## 5. Gruppi — assegnazione

I gruppi `Ufficio Amministrativo` (grp 2), `Ufficio Tecnico` (grp 3) e `Installatore`
(grp 4) esistono già come segnaposto vuoti in
`DB/SRC/hybrismeter/10_Tables/12.system_config_data.sql` (`x'00000000'::bigint`, commento
`--not_used`). Questa sezione ne definisce i grant reali, oltre a correggere i quattro
gruppi già attivi.

| grp_ID | Nome | `grp_grants` (nuovo) | Composizione |
|--------|------|------------------------|--------------|
| 0 | ROOT | `(-1)::bigint` | tutti i bit — invariato |
| 1 | Amministratore piattaforma | `x'3077F7F7'` (con `VIEW_MAP` dal 2026-09-25, `SELF_READ` dal 2026-10-05 per poter assegnare il gruppo 9) | `LOGIN` + `ALL_BUILDINGS` + VIEW/EDIT su USER/**SUBJECTS**/STRUCT/MEASURE/ALLOC/ALARMS, più `APPLOGIN`+`TECHLOGIN`+`OWN_UNITS`+`OWN_CREATED_BUILDINGS`+`VIEW_ALL_BUILDINGS`+`MANAGED_BUILDINGS` (2026-08-07, vedi nota sotto la tabella) |
| 2 | Ufficio Amministrativo | `x'1003F7C1'` (con `VIEW_MAP` dal 2026-09-25) | `LOGIN` + `ALL_BUILDINGS` + VIEW/EDIT_**SUBJECTS** + VIEW/EDIT_STRUCT + VIEW/EDIT_MEASURE + VIEW/EDIT_ALLOC + VIEW/EDIT_ALARMS — **senza** `*_USER` (non gestisce utenti/amministratori di sistema, ma gestisce anagrafiche soggetti) e senza `HANDLE_ROOT` |
| 3 | Ufficio Tecnico | `x'10033701'` (con `VIEW_MAP` dal 2026-09-25) | `LOGIN` + `ALL_BUILDINGS` + VIEW/EDIT_STRUCT + VIEW/EDIT_MEASURE + VIEW/EDIT_ALARMS — **senza** `*_ALLOC`, `*_USER`, `*_SUBJECTS`; modifica **qualunque** stabile/UI/misuratore/misura, propri o altrui (nessuna restrizione — a differenza dell'Installatore) |
| 4 | Installatore | `x'00613305'` | `LOGIN` + `TECHLOGIN` (canale mobile futuro, oggi opera via WebApp) + VIEW/EDIT_STRUCT + VIEW/EDIT_MEASURE + `VIEW_ALARMS` (sola visualizzazione — vede se il misuratore su cui lavora ha un allarme aperto, ma tacitare/chiudere resta una decisione amministrativa) + `VIEW_ALL_BUILDINGS` + `OWN_CREATED_BUILDINGS` — vede tutto, crea ovunque, modifica/cancella **solo ciò che ha creato lui e finché non è validato** (§4) |
| 8 | Amministratore Condominio | `x'20001401'` | **Ambito (2026-09-28, regole dell'utente):** un solo amministratore per volta sullo stesso stabile; vede tutti i dati dei suoi stabili, periodi precedenti compresi, fino alla fine del suo mandato — niente dopo, niente prima che inizi (`fnAdminUntil`). Documenti dello stabile: per ora non visibili. Verifica: `BE/api/tests/smoke_condo.py`. — `LOGIN` + `MANAGED_BUILDINGS` + `VIEW_MEASURE` + `VIEW_MAP` — **dal 2026-09-25** (era `x'20015101'`, con anche `VIEW_STRUCT` + `VIEW_ALLOC` + `VIEW_ALARMS`): le stesse funzioni dell'utente finale (Letture, Consumi) più la mappa, su **tutti** gli stabili e le unità che amministra. Riparti: per ora no; quando arriveranno (`VIEW_ALLOC`, forse `EDIT_ALLOC` per alcuni) l'ambito è già imposto dal DB (`gl_checkBldScope` in `_common/30.fnGlobal.sql`, chiamato in testa alle 25 funzioni di riparti e bollette che ricevono solo identificativi). Allarmi da riprendere in una sessione dedicata |
| 9 | Utente finale | `x'00141003'` (con `SELF_READ`: autoletture; con `APPLOGIN`: app utente finale) | **Ambito (2026-09-28):** tutti i periodi dell'unità a cui è collegato con flag di accesso — correnti e chiusi — e solo quelli (l'ex inquilino vede il suo, il nuovo mai quello del precedente); il misuratore sostituito per il periodo in cui era installato; mai `adm_id`/`bld_note` dello stabile né dati di altre unità. Regola unica: `fnUnitReadRanges` & C. (`33.structures.sql`); se ha anche MANAGED_BUILDINGS gli ambiti si sommano. Verifica: `BE/api/tests/smoke_enduser.py`. — `LOGIN` + VIEW_MEASURE + **`OWN_UNITS`** (nuovo bit — sostituisce l'uso improprio di `APPLOGIN` come ambito, vedi §6) — **senza `VIEW_STRUCT`** (2026-08-05: rimosso, non deve vedere la pagina STABILI; le pagine Letture/Consumi dipendono solo da `VIEW_MEASURE`, mai da `VIEW_STRUCT`). Con **`APPLOGIN`**: accesso dall'app utente finale (`USERAPP`), stesso ambito del web |

**Righe confermate in sessione di revisione (2026-08-03):**
- `ALARMS` su grp 1/2/3/8/4 come da tabella sopra — confermato: chi vede `MEASURE`/
  `ALLOC` in lettura vede anche gli allarmi in lettura; chi ha `ALL_BUILDINGS` su
  struttura/misure gestisce anche gli allarmi. **grp 9 esplicitamente escluso**: un
  utente finale non gestisce allarmi di sistema.
- `SUBJECTS` su grp 2 (Ufficio Amministrativo) — confermato: l'ufficio amministrativo
  aggiorna l'anagrafica di proprietari/conduttori nel lavoro quotidiano. **grp 3/4/8/9
  esplicitamente esclusi da `SUBJECTS`**: nessun caso d'uso individuato per tecnici,
  installatori, amministratori di condominio o utenti finali; da aggiungere se emerge
  un'esigenza reale.

**Superato il 2026-09-25** (decisione dell'utente: grp 8 = funzioni dell'utente finale + ambito degli stabili amministrati; `VIEW_ALLOC` tolto insieme a `VIEW_STRUCT`/`VIEW_ALARMS`). Testo originale:
**Motivazione `VIEW_ALLOC` per Amministratore Condominio (confermato):** il ruolo vede
già misure e consumi (l'input del riparto); vedere anche il riparto (il suo output) è
coerente e non introduce rischio, perché resta assente `EDIT_ALLOC` — nessuna capacità
di modifica viene concessa.

**Nota sui `grp_ID`:** i tre gruppi nuovi usano gli ID già riservati nel file sorgente
(2, 3, 4) — nessun nuovo ID da inventare, nessuna modifica alla sequence.

**Amendment 2026-08-07 — visibilità simmetrica alla scrittura, e sue conseguenze su grp1/grp9:**
`api_GetUserGroupsFull`/`api_GetUsers` ora nascondono qualunque gruppo/utente che porti un bit di
grant non posseduto dal chiamante, rendendo simmetrica la regola già esistente in scrittura
(`api_SetUserGroups`/`dbSetUser`, "non puoi assegnare autorizzazioni che non possiedi"). Nessuna
gerarchia di ruoli nel sistema (principio 2): tutto risolve sui bit, quindi un Amministratore di
piattaforma deve possedere lui stesso ogni bit di un gruppo per poterlo anche solo vedere/
assegnare a un altro utente — non solo i bit CAPABILITY (dove questo è il comportamento voluto,
previene l'escalation), ma anche GATE e SCOPE, dove invece non rappresenta una vera escalation
(un bit SCOPE è quasi sempre una *restrizione* rispetto ad `ALL_BUILDINGS`, non un potere aggiuntivo).
Non essendoci ancora una correzione strutturale di questa distinzione (valutata, rimandata — vedi
sotto), grp1 ha ricevuto i bit "di servizio" necessari a poter assegnare grp 4/8/9:
`APPLOGIN`+`TECHLOGIN`+`OWN_UNITS`+`OWN_CREATED_BUILDINGS`+`VIEW_ALL_BUILDINGS`+`MANAGED_BUILDINGS`.
Verificato: **senza alcun effetto pratico** su grp1 stesso, dato che ogni funzione `api_Get*`/
`api_Set*` testa `ALL_BUILDINGS` per primo in una catena `if/elsif` (§2) — chi ce l'ha già non vede
mai valutato un bit SCOPE successivo. grp9 "Utente finale" porta `APPLOGIN` (gate dell'app utente finale
`USERAPP`, `application=2`): grp1 lo possiede, quindi può continuare ad assegnare grp9.

**Correzione strutturale valutata e rimandata:** la causa di fondo è che il controllo "non puoi
assegnare ciò che non possiedi" (`dbSetUser`/`api_SetUserGroups`) tratta i tre assi GATE/
CAPABILITY/SCOPE allo stesso modo, mentre solo CAPABILITY rappresenta davvero un potere la cui
assegnazione andrebbe limitata a chi già lo possiede. Una versione più corretta escluderebbe GATE
e SCOPE da quel controllo per chi ha già `ALL_BUILDINGS` (o li tratterebbe come "restrizioni",
assegnabili liberamente da chi ha ambito pieno). Non implementata in questa sessione — la
soluzione adottata sopra (accumulare bit "di servizio" su grp1) funziona ma richiede di ricordarsi
di ripeterla per ogni nuovo gruppo/bit GATE o SCOPE introdotto in futuro; se il pattern si ripete
ancora, vale la pena tornare su questa correzione strutturale invece di continuare ad accumulare.

---

## 6. Bug di scoping trovati durante l'audit — da correggere nella stessa passata

L'ispezione di `40_ApiFunctions/` per preparare questa specifica ha trovato violazioni
concrete della regola §2 ("SCOPE mai sostituito da CAPABILITY o GATE"). Vanno corrette
insieme all'introduzione dei bit nuovi, perché la correzione **è** l'introduzione dei
bit nuovi (i rami sbagliati vanno sostituiti con i rami SCOPE corretti, non aggiunti
accanto). **I valori esadecimali citati qui sotto sono quelli attualmente nel codice
deployato** (numerazione originale, pre-riorganizzazione — es. `VIEW_STRUCT` vale ancora
`0x1000` nel DB/BE reali oggi), non la numerazione compatta di §3: la funzione DB non fa
distinzione fra le due, legge solo il valore che il BE le passa in quel momento, quindi
questi punti restano validi indipendentemente da quando, nel piano di esecuzione, la
rimappatura CAPABILITY viene applicata rispetto a queste correzioni SCOPE:

1. **`api_GetBuildingsHead`** (`42.api_structures.sql:55`) — usa `APPLOGIN` (`0x2`,
   bit GATE) come ambito "solo le mie unità". Sostituire con `OWN_UNITS`
   (`0x00100000`).
2. **`api_GetUnitsHead`** (`42.api_structures.sql:788`) — usa `VIEW_STRUCT` (`0x1000`,
   bit CAPABILITY) da solo come se implicasse ambito `ALL_BUILDINGS`. Conseguenza reale:
   oggi un Amministratore Condominio (che ha `VIEW_STRUCT`) vede le unità di **tutti**
   gli stabili tramite questo endpoint, non solo di quelli amministrati — il ramo
   `VIEW_STRUCT` viene raggiunto prima del ramo `MANAGED_BUILDINGS` nell'`elsif`. Il ramo
   `VIEW_STRUCT`-da-solo va **rimosso**, non sostituito: con SCOPE come unico
   discriminante, la sola combinazione `ALL_BUILDINGS` / `MANAGED_BUILDINGS` /
   `OWN_UNITS` basta.
3. **`api_GetUnitsHead`** (stessa funzione, riga 796) — usa `LOGIN` (`0x1`, bit GATE,
   posseduto da chiunque sia autenticato) come ambito "solo le mie unità" invece di
   `OWN_UNITS`. Va sostituito.
4. **`api_GetMeters`** e **`api_GetMeasures`** (`42.api_structures.sql`,
   `43.api_meascons.sql`) — **nessun controllo di ambito**: filtrano solo per
   `sbj_id`/`ui_id`/`mtr_ids` passati dal chiamante; se non passati, `api_GetMeters`
   restituisce l'elenco di **tutti** i misuratori della piattaforma a chiunque sia
   autenticato (il BE la espone con grant `LOGIN`). Va aggiunta la stessa catena SCOPE
   delle altre funzioni `api_Get*` prima di applicare il filtro per id.

**Verifica da estendere a tutto `40_ApiFunctions/`:** i quattro punti sopra sono quelli
confermati durante questa sessione, non un elenco esaustivo. Prima di dichiarare
concluso il lavoro sullo SCOPE, eseguire:

```bash
grep -n "l_grants &\|lGrants &\|p_grants &\|pGrants &" DB/SRC/hybrismeter/40_ApiFunctions/*.sql
```

**Nota sul comando:** la prima stesura di questo comando (`l_grants &\|p_grants &`) non
intercetta le occorrenze in variabile camelCase `lGrants &` presenti in
`44.api_allocations.sql:75-76` e `44.api_allocations.sql:126-127` — pattern lì
comunque corretto (vedi sotto), ma la scansione va estesa per non lasciare punti ciechi.

Verificare **ogni** occorrenza contro la regola §2: il bit testato deve essere uno fra
`ALL_BUILDINGS`, `MANAGED_BUILDINGS`, `VIEW_ALL_BUILDINGS`, `OWN_UNITS`, `OWN_CREATED_BUILDINGS`
— mai un bit CAPABILITY o GATE isolato. Le occorrenze in `48.api_globals.sql`,
`43.api_meascons.sql`, `44.api_allocations.sql`, `44.api_allocations.sql`,
`44.api_allocations.sql` che combinano `ALL_BUILDINGS`/`MANAGED_BUILDINGS` in AND con un
bit CAPABILITY (pattern `0x10001000`, `0x20001000`) sono **corrette così come sono**:
richiedono sia lo SCOPE sia la CAPABILITY, non usano l'uno al posto dell'altro — non
vanno toccate. Dopo l'intervento di §4, questo grep deve intercettare anche
`api_SetBuildingDet`, `api_NewBuildingDet`, `api_SetUnitDetail`, `api_SetMeter`,
`api_SetMeasure`, `api_SetSubject`, `api_SetSubjectSite`, `api_SetSubjectContact` — se
non compaiono, il ramo SCOPE previsto in §4 non è stato scritto.

### 6.1 Bug di CAPABILITY assente o nel dominio sbagliato (trovati estendendo USER/MEASURE)

Stessa regola di §2, violata sull'asse CAPABILITY invece che SCOPE — trovati mentre si
verificava dove ricadono "soggetti e amministratori" (dominio `USER`, §3) e "consumi"
(dominio `MEASURE`, §3) nel codice reale:

5. **`config.py` — `/subjects*`** (righe 28-159: GET su subjects/sites/contacts, POST/PUT/
   DELETE su subjects/sites/contacts): GET gated da `_ADMIN` (= `GRANT_ALL_BUILDINGS |
   GRANT_MANAGED_BUILDINGS`, un bit SCOPE), POST/PUT/DELETE da `GRANT_ALL_BUILDINGS` diretto —
   **nessun controllo CAPABILITY**, perché finora non esisteva un dominio dedicato. Ora
   che `VIEW_SUBJECTS`/`EDIT_SUBJECTS` coprono esplicitamente questo (§3), va sostituito:
   GET → `VIEW_SUBJECTS`, POST/PUT/DELETE → `EDIT_SUBJECTS`. Nessuno SCOPE si applica qui
   (l'anagrafica soggetti è un registro globale, non filtrabile per stabile) — CAPABILITY
   basta da sola, come già avviene per `buildings`/`units`/`meters`.
5bis. **`config.py` — `GET /admins`** (righe 223-226): stesso difetto (`_ADMIN`, un bit
   SCOPE, nessuna CAPABILITY), ma dominio diverso — gli amministratori restano sotto
   `USER` (§3), non sotto `SUBJECTS`. Da correggere a `VIEW_USER`. Non esiste oggi un
   endpoint di scrittura per l'assegnazione amministratore/stabile (solo un INSERT
   interno in `services/import_building.py` durante l'import guidato) — se in futuro se
   ne aggiunge uno, va gated `EDIT_USER`.
6. **`consumptions.py` — `GET /`, `/delta`, `/building`, `/heat-pie`, `GET /heat-totals`**
   (righe 16-90): nessun controllo CAPABILITY, solo autenticazione (`get_current_user`).
   Da correggere a `VIEW_MEASURE`, ora che il dominio copre esplicitamente anche i
   consumi (§3).
7. **`POST /consumptions/recalc`** (riga 70): gated da `VIEW_MEASURE` — sbagliato per
   costruzione, è un'azione di scrittura (ricalcola e sovrascrive le consumazioni). Da
   correggere a `EDIT_MEASURE`.
8. **`PUT`/`DELETE /consumptions/heat-totals`** (righe 96, 108): gated da
   `EDIT_STRUCT` — dominio sbagliato, sono dati di consumo mensile (`wrk_heatBldTotals`),
   non di struttura. Da correggere a `EDIT_MEASURE`.

---

## 7. Fuori scope in questa passata (deciso, non solo rimandato)

- **Dimensionamento di `pageGrants`** e correzione del bug PAGE (STABILI/DASHBOARD
  visibili all'utente finale solo perché ha `VIEW_STRUCT`): entrambi dipendono dalla
  stessa decisione ancora non presa — l'elenco definitivo delle pagine da controllare e
  le combinazioni di visibilità volute. Restano rimandati a una sessione dedicata a
  quell'unico tema. Nel frattempo il comportamento resta quello attuale (nessuna
  regressione introdotta da questa passata, nessun miglioramento su questo fronte).
- **Riduzione delle triadi `VIEW/EDIT/CREATE` a due soli livelli `VIEW/EDIT`**:
  **eseguita** (vedi §3). Una prima verifica basata solo sulla tabella riassuntiva di
  `BE/api/CLAUDE.md` (non sul codice) aveva fatto scartare la proposta, per un rischio
  di refactoring ampio che si è rivelato non reale. Verifica corretta, fatta leggendo
  ogni singolo endpoint in `BE/api/app/api/v1/endpoints/`:
  - `EDIT_STRUCT` copre **già** PUT+DELETE ovunque tranne `bills.py`; `CREATE_STRUCT`
    gate solo 5 azioni di puro inserimento (`create_building`, `create_unit`,
    `create_meter`, `create_meter_type`, `import_building_from_gsheet`).
  - `EDIT_ALLOC` non è mai referenziato da nessun endpoint: è un bit morto. Tutte le
    scritture riparto passano da `GRANT_CRUD_ALLOC` (alias di `CREATE_ALLOC`).
  - Nessun gruppo esistente o proposto in questo documento ha mai `CREATE_*` senza il
    corrispondente `EDIT_*` (verificato su tutti e quattro i domini — vedi tabella §5):
    la distinzione a tre livelli non era sfruttata da nessun profilo reale, in
    violazione del criterio di minimalità già enunciato in questo stesso documento
    (§2, principio 3: un bit si giustifica solo se un profilo reale ne dipende).
  - Le due obiezioni plausibili ("un ruolo potrebbe creare utenti senza poter toccare
    quelli esistenti", "un ruolo potrebbe gestire allarmi senza toccare le letture")
    non reggono: `create_user` può già assegnare i gruppi (stessa sensibilità di
    `update_user`), e nessun gruppo separa oggi allarmi da letture.
  - **Unico punto reale da verificare prima del deploy** (non un difetto di design):
    **TEST e PROD sono oggi vuoti** — riceveranno un deploy da zero in un secondo
    momento, non una migrazione di dati esistenti. La verifica (nessun gruppo con
    `CREATE_*` senza `EDIT_*`) si applica quindi solo a **LOCAL**, l'unico ambiente con
    `db_uGroups` popolato da dati/utenti reali oggi. Vedi §9, passo 0.
- **Riordino cosmetico dei bit `MEASURE`/`STRUCT`** per farli coincidere con l'ordine di
  presentazione nel FE: non se ne fa nulla — nessun beneficio funzionale, solo rischio
  di migrazione. Se si vuole un ordine diverso nella UI, si riordina la UI, non i bit.

---

## 8. Nota tecnica da spostare nel codice (non in questo file)

Il seguente testo va inserito come commento SQL in
`DB/SRC/hybrismeter/10_Tables/12.system_config_data.sql`, subito sopra la definizione di
`loo_grants`, così da restare disponibile a chi in futuro valuterà il passaggio a una
gestione oltre i 32 bit — senza doverlo recuperare da una conversazione:

```sql
-- NOTA TECNICA — margine di crescita dei bit grants (bigint, 64 bit con segno):
-- gli operatori bitwise di Postgres (&, |, ~) funzionano correttamente su tutti i 64
-- bit, bit 63 incluso: non è un limite di Postgres. Un valore con solo il bit 63 acceso
-- è il numero negativo -9223372036854775808 e quindi non si accende con un OR di
-- costanti positive nel modo consueto — per questo ROOT usa il letterale (-1) invece di
-- enumerare i bit. Non basare mai la logica sul valore numerico di -1, solo sul fatto
-- che tutti i bit sono a uno.
--
-- Limite reale, non qui ma nel FE: FE/src/types/api.ts implementa hasGrant con
-- l'operatore & nativo di JavaScript, che converte gli operandi a interi con segno a
-- 32 bit prima dell'AND (bit dal 32 in su azzerati in silenzio). Il tetto pratico è
-- quindi 32 bit lato FE. Se in futuro servisse comunque superarlo, l'impatto è su:
-- FE/src/types/api.ts, AuthContext.tsx, lib/auth.ts (hasGrant/tipi), serializzazione
-- BE del JWT, localStorage (JSON.stringify non accetta BigInt nativamente), i checkbox
-- e l'input numerico in cnf/usergroups/page.tsx. Non serve introdurre BigInt nel FE
-- finché i bit restano sotto il bit 31.
```

Una volta inserito il commento, questa nota può essere rimossa dalle versioni future di
GRANT.md — è documentazione di codice, non specifica di lavoro.

---

## 9. Piano di esecuzione (ordine consigliato per la sessione dedicata)

0. **Precondizione da verificare prima di scrivere codice** (vedi §7): TEST e PROD sono
   oggi **vuoti** (riceveranno un deploy da zero in un secondo momento, fuori scope per
   questa sessione) — la verifica si applica quindi solo a **LOCAL**: interrogare
   `db_uGroups` su LOCAL e decodificare `grp_grants` per ogni gruppo effettivamente
   configurato. Se un gruppo **non elencato in §5** ha `CREATE_*` senza il corrispondente
   `EDIT_*` per qualunque dominio, va deciso caso per caso prima di procedere — i gruppi
   0/1/2/3/4/8/9 vengono comunque sovrascritti integralmente dal passo 1.
1. **DB — schema dati**: nessuna modifica di schema richiesta (Proposta A, §4). Dati da
   aggiornare in `12.system_config_data.sql`: valori `grp_grants` di §5 per i grp_ID
   0/1/2/3/4/8/9; riscrivere `loo_grants` per intero con la numerazione compatta di §3
   (nessuna riga esistente conserva il proprio valore invariato tranne GATE/`HANDLE_*`,
   quindi non ha senso parlare di "aggiungere"/"rimuovere" singole righe — è una
   sostituzione integrale della tabella lookup); inserire il commento di §8.
2. **DB — funzioni**: scrivere **ex novo** (non estendere: verificato a codice che non
   esiste alcun controllo di grants oggi) il pattern completo di §4.2 (`ALL_BUILDINGS`/
   `MANAGED_BUILDINGS`/`OWN_CREATED_BUILDINGS` + blocco di validazione) in `api_SetBuildingDet`/
   `api_NewBuildingDet` (blocco via `wrk_allocwater`/`wrk_allocheat` su `bldDet_rowID`),
   `api_SetUnitDetail` (blocco via `wrk_allocwaterDetUI`/`wrk_allocheatDetUI` su `ui_ID`,
   **non** `uiD_rowID`), `api_SetMeter` (blocco per transitività dalle misure dello
   stesso `mtr_ID`), `api_SetMeasure` (blocco esistente via `wrk_usedWaterMeas`/
   `wrk_usedHeatMeas`, da non toccare, solo referenziare) — questo richiede che il BE
   inizi a passare `grants` nel body a queste funzioni (oggi non lo fa, verificare
   `BE/api/app/db/queries.py:381,415,420,439,462`). **Estendere** invece (gate piatto già
   presente) `api_SetSubject`/`api_SetSubjectSite`/`api_SetSubjectContact` (nomi reali)
   con ownership 4.1 + blocco esplicito, nessuna query di blocco automatico possibile.
   Creare le sette nuove `api_Validate*` (`BuildingDet`, `UnitDetail`, `Meter`,
   `Measure`, `Subject`, `SubjectSite`, `SubjectContact` — nomi corretti); correggere i
   quattro punti di §6; completare l'audit con il grep corretto (variante camelCase
   inclusa). Le funzioni DB non controllano mai CAPABILITY (verificato: nessun
   riferimento a bit `VIEW/EDIT/CREATE_*` in `42.api_structures.sql`), quindi
   l'unificazione del punto 3 non le tocca.
3. **BE — unificazione e rimappatura CAPABILITY** (§3/§7): in
   `BE/api/app/core/deps.py` rimuovere del tutto le vecchie costanti a tre livelli
   (`GRANT_VIEW/EDIT/CREATE_USER/MEASURE/STRUCT/ALLOC` e gli alias `GRANT_CRUD_*`) e
   riscriverle con i valori compatti di §3 (`GRANT_VIEW_USER=0x10` ...
   `GRANT_EDIT_ALARMS=0x20000`); aggiungere `GRANT_VIEW_SUBJECTS`, `GRANT_EDIT_SUBJECTS`,
   `GRANT_VIEW_ALL_BUILDINGS`, `GRANT_OWN_UNITS`, `GRANT_OWN_CREATED_BUILDINGS`.
   Correggere nella stessa passata i punti 5/5bis/6-8 di §6.1: `config.py` righe 28-159
   (GET `/subjects*` → `VIEW_SUBJECTS`, POST/PUT/DELETE `/subjects*` → `EDIT_SUBJECTS`),
   riga 226 (GET `/admins` → `VIEW_USER`); `consumptions.py` righe 17-90 (GET →
   `VIEW_MEASURE`), riga 70 (`recalc` → `EDIT_MEASURE`), righe 96/108 (`heat-totals`
   PUT/DELETE → `EDIT_MEASURE`); `alarms.py` riga 19 (GET → `VIEW_ALARMS`), riga 28
   (PUT → `EDIT_ALARMS`, oggi erroneamente `EDIT_MEASURE`).
   Punti di chiamata da correggere (tutti da bit `CREATE_*`/alias `CRUD_*` a `EDIT_*`
   diretto — elenco chiuso, verificato a grep):
   `buildings.py` righe 24, 66 · `units.py` riga 36 · `meters.py` righe 32, 73 ·
   `bills.py` righe 28, 49, 69, 94 (oggi `GRANT_CRUD_STRUCTS`) · `measures.py` righe
   166, 188 · `config.py` riga 440 · `allocations.py` righe 48, 60, 76, 89, 99, 108, 118
   · `allocations_heat.py` righe 47, 62, 75, 88, 98, 108, 158 · `allocations_general.py`
   riga 39 (questi ultimi 15, oggi `GRANT_CRUD_ALLOC`, diventano `GRANT_EDIT_ALLOC` —
   che passa così da bit mai controllato a bit realmente operativo).
   **Nello stesso passo**, chiudere la dipendenza incrociata del punto 2: in
   `queries.py` aggiungere il parametro `grants` alle firme `db_set_building_det`,
   `db_new_building_det`, `db_set_unit_detail`, `db_set_meter`, `db_set_measure`, e negli
   endpoint corrispondenti (`buildings.py:128,142,170`, `units.py:85,99`,
   `meters.py:34,46`, `measures.py:180`) passare `user.get("grp_grants", 0)`.
4. **FE**: allineare `FE/src/types/api.ts` con le stesse rimozioni/aggiunte del punto 3;
   `TopNav.tsx` riga 132 (`canAddUser`) da `GRANT_CREATE_USER` a `GRANT_EDIT_USER`;
   `cnf/usergroups/page.tsx` — togliere le 4 righe `CREATE_*` dalla griglia (non più
   assegnabili indipendentemente) e correggere nella stessa occasione il bug noto
   (`GRANT_BITS` hardcoded, non allineato a `loo_grants`, manca `HANDLE_ROOT` da prima
   di questa sessione) facendolo leggere da `loo_grants` invece che da un array
   statico, così i bit nuovi/rimossi restano sempre sincronizzati.
5. **Deploy**: solo **LOCAL** in questa sessione — `./deploy.sh L A` (dati) +
   `./deploy.sh L F` (funzioni). TEST e PROD sono vuoti e riceveranno un deploy da zero
   in un momento successivo, fuori scope qui: basta che i sorgenti risultanti siano
   corretti per quel deploy futuro.
6. **Sincronizzazione documentazione** (per [[feedback_db_documentation_sync]]):
   `DB/CLAUDE.md` (tabella "Modello
   permessi"), `BE/api/CLAUDE.md` (tabelle endpoint — molte righe `Grant` cambiano da
   `CREATE_STRUCT`/`CRUD_ALLOC` a `EDIT_STRUCT`/`EDIT_ALLOC`), Google Sheet "Hybris -
   Database structure".
