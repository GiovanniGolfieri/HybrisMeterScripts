# Cose da fare — HybrisMeter

Elenco operativo dei punti ancora aperti. Ultima verifica diretta a codice: 2026-10-10.

---

## 1. Riparti — gap funzionali

### 1.1 Import massivo comuni italiani (bacini tariffari acqua)
`loo_Municipalities` contiene 5 comuni (area di Bologna), CRUD singolo in `cnf/tariffe`, nessun import massivo. Collo di
bottiglia certo con stabili fuori zona.

### 1.2 Punti minori UX
- **Riparto Generale:** interazione non definitiva quando una cella ha più `all_id` associati (split tariffario a metà
  periodo); decidere se includere il riepilogo generale come copertina configurabile nello ZIP.
- **Totali mensili RISC/ACS/RAFF** (`HeatMonthlyTotalsCard` in `stabili/page.tsx`): valutare se spostarli fuori dalla
  scheda tecnica dello stabile (erano marcati per un "task parallelo dedicato" mai definito).

---

## 2. Scheda "Parametri ripartizione" e dati di unità

Tutto in `FE/src/app/(dashboard)/stabili/page.tsx` (schede `TabTecnici`, `TabUnita`, `UnitFormModal`, `UnitDetailPanel`,
`BuildingPeriodBar`).

### 2.1 Totale canone noleggio — allineare il motore ai misuratori reali
La griglia "Dati per unità" mostra `canone unitario × n. misuratori reali dell'unità` (`db_unitsDet.ui_totWaterMeters` /
`ui_totHeatMeters`, aggiornati dal trigger su `rel_meters`). Il **motore di riparto** calcola invece ancora
`ui_rentFee* × ui_rentNdev*` (`fnResolveUnitRent` in `30_WrkFunctions/37.periodResolution.sql`). Allineare il motore al
conteggio reale.

### 2.2 Eliminare `ui_rentNdevWater` / `ui_rentNdevHeat`
Non più editabili da UI, ma restano: lette dal motore (§2.1), nelle liste colonne di `api_SetUnitDetail`
(`42.api_structures.sql`), nei modelli Pydantic `SetUnitDetailRequest` / `NewUnitDetailRequest` (`BE/api/app/models/unit.py`),
in `UnitDatiPatch` / `SetUnitDetailPayload` lato FE (`types/api.ts`) e nelle viste. Rimozione = colonna tolta dal sorgente
e dal foglio + `fnResolveUnitRent` riscritta su `ui_totWaterMeters` / `ui_totHeatMeters` + pulizia liste colonne e
`_keep_explicit_rental_nulls` + modelli BE/FE + `DB/CLAUDE.md`. Dipende da §2.1.

### 2.3 Periodo di stabile condiviso fra le schede
`StabileDetail` condivide il periodo di stabile scelto in `BuildingPeriodBar` con la griglia dei misuratori della scheda
"Unità immobiliari e misuratori"; la scheda "Parametri ripartizione" (`TabTecnici`) ha ancora un proprio selettore
(`activeRowid` interno). Vanno unificati su un unico stato di periodo di stabile della pagina Stabili.

### 2.4 Blocco "periodo già usato": nascondere "Salva" invece di dare errore
Pattern già applicato alla modale unità (`UnitFormModal`): messaggio in testa + pulsante "Nuova configurazione" + campi
bloccati grigi, niente errore al salvataggio. **Da applicare a:**
- **Periodo di stabile** in `BuildingPeriodBar` — nessun avviso persistente, solo il toast `PERIOD_READONLY_MSG` al
  tentativo di salvataggio;
- **Scheda "Parametri ripartizione"** (`TabTecnici`) — ha ancora il riquadro ambra persistente "Sola lettura: periodo già
  usato…", il `<fieldset disabled={isPeriodLocked}>` e il pulsante "Salva modifiche" solo disabilitato, non nascosto.

Il comportamento voluto: niente pulsante "Salva" + una label che spiega che per modificare quei dati va creato
manualmente un nuovo periodo (`api_NewBuildingDet` mode=1).

### 2.5 Quota di possesso proprietario (`ui_ownership`) — non impostabile da FE
`rel_unitSubject.ui_ownership` è mostrata in sola lettura (×100) in `UnitDetailPanel`. La modale unità (`UnitFormModal` →
`UnitSubjectsBlock`) permette solo di aggiungere/rimuovere i proprietari, non di impostarne la quota. Manca anche il
controllo «Σ = 1 sulle righe proprietario» — non esprimibile con un CHECK: va in `api_SetUnitSubject` + FE.

---

## 3. "Riparti da completare" — rifiniture residue

La base è implementata (`api_GetAllocationsGeneralPending`, pannello in dashboard, vista "Da completare" in `/riparti`).
Restano:

### 3.1 KPI "Riparti in ritardo" in testata dashboard
Un KPI sullo stesso modello di "Allarmi aperti", cliccabile verso la vista "Da completare" già filtrata.

### 3.2 Soglia "60 giorni" cablata + scala colore graduale
La soglia `overdue` (60 giorni dalla chiusura contabile) è fissa in `api_GetAllocationsGeneralPending`. Valutare se
renderla parametro (globale o per stabile) e una scala di colore continua sui giorni di ritardo nel badge della dashboard.

### 3.3 (opzionale) Dimensione operativa
Assegnatario / priorità / scadenza intervento / nota sui riparti da fare, sul modello degli allarmi (`alr_assignee` /
`alr_priority` / `alr_duedate` / `alr_note`).

**Fuori scope:** notifiche email quando un riparto diventa urgente; avvio automatico del calcolo riparto (resta manuale).

---

## 4. Permessi (GRANT.md)

### 4.1 Correzione strutturale del controllo "non puoi assegnare ciò che non possiedi"
`dbSetUser` / `api_SetUserGroups` trattano i tre assi GATE / CAPABILITY / SCOPE allo stesso modo, mentre solo CAPABILITY è
un potere la cui assegnazione va limitata. Tampone attuale: il gruppo "Amministratore piattaforma" (`x'3077F7F7'`)
accumula i bit di servizio (`APPLOGIN`, `TECHLOGIN`, `SELF_READ`, `OWN_UNITS`, `OWN_CREATED_BUILDINGS`,
`VIEW_ALL_BUILDINGS`, `MANAGED_BUILDINGS`) per poter assegnare i gruppi 4/8/9. Va ripetuto per ogni nuovo bit: se il
pattern si ripete ancora, fare la correzione strutturale (escludere GATE e SCOPE da quel controllo per chi ha già
`ALL_BUILDINGS`).
- **Collegato:** `APPLOGIN` non è nel gruppo "Utente finale" (`x'00141001'`): va riaggiunto quando esisterà l'app utente
  finale.

### 4.2 `pageGrants`
Visibilità delle voci di menu FE con un insieme di permessi separato da `grp_grants` (oggi le pagine dipendono dai bit
CAPABILITY, `GrantGuard.tsx`): serve una decisione sull'elenco definitivo delle pagine da controllare e sulle combinazioni
di visibilità volute. Sessione dedicata.

---

## 5. Sessioni attive (`wrk_userSessions`) — vedi `proposta-sessioni-attive.md`

Fatte le fasi 0 / 1 / 2a; per l'app installatore la sessione è già verificata a ogni richiesta (`get_installer_user`) con
access token breve e chiave di rinnovo ruotante. Restano per il web:

- **Fase 2b:** `get_current_session` agganciata a `require_grant` in `core/deps.py` → revoca **immediata** invece che al
  prossimo ping. Job `api_SessionSweep` schedulato (pg_cron su RDS da verificare, oppure task nel `lifespan` con advisory
  lock).
- **Fase 3:** badge di `cnf/usergroups` da `usr_status` a `usr_liveSessions`; **eliminare** `api_LoginConfirm` e
  `api_Logout`; `usr_status` torna a dominio `{-2,-1,0}` (con TEST/PROD reinstallati da zero basta il sorgente).
- **Fase 4:** UI elenco sessioni (`cnf/usergroups` + pagina Account "Le mie sessioni"), "Termina" / "Termina tutte".

---

## 6. `db_users.tmp_grants`

La colonna esiste ma non è mai scritta. Idea: al login calcolare i grant effettivi (gruppi + individuali, come
`gl_getUserGrants`) e salvarli lì, per non ricalcolarli a ogni chiamata.
