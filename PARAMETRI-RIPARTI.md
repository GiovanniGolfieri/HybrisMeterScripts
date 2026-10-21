# Parametri necessari per il calcolo dei riparti

Elenco dei dati **indispensabili**, oltre alle letture/consumi dei misuratori, per calcolare un
riparto conforme alle regole adottate:

- **ACQUA** — metodo tariffario **ATO 5 Bologna** (ATERSIR/ARERA: scaglioni per uso, quote fisse
  acquedotto/fognatura/depurazione, componenti di perequazione UI1–UI4, fondo perdite, IVA) +
  criteri assembleari per le voci non a consumo (art. 1123 c.c.);
- **CALORE** (RISC, ACS, RAFF) — UNI 10200, Guida ENEA, D.Lgs. 102/2014 art. 9 c. 5 come
  modificato dal D.Lgs. 73/2020 (quota volontaria ≥ 50%, criteri millesimali, esonero), secondo il documento di
  riferimento `info_CalcoloRiparti2` (2026-10-10).

Sono esclusi i dati facoltativi (se mancano il calcolo procede ignorando la voce) e quelli che il
sistema ricava da solo.

La colonna **«Serve solo se»** indica il caso particolare in cui il dato è richiesto; **vuota =
serve sempre**.

---

## 0. Dati comuni a tutti i riparti

| Parametro | Uso nel calcolo | Serve solo se |
|---|---|---|
| Periodo di riparto (inizio/fine) | Intervallo di calcolo; consecutivo al riparto precedente, non sovrapposto | |
| Data di chiusura contabile (giorno/mese) | Durata dell'esercizio (bisestili), pro rata delle quote annue, finestre del Riparto Generale | |
| Stato dell'unità nel periodo | Partecipano solo le unità attive | |
| Proprietario / conduttore | Intestatario delle quote | |
| Sotto-periodi dell'unità | Righe distinte pro rata temporis per ciascun occupante | cambia l'occupante nel periodo (subentro) |

---

## 1. ACQUA (ATO 5)

### 1.1 Tariffa

| Parametro | Uso nel calcolo | Serve solo se |
|---|---|---|
| Bacino tariffario | Individua il tariffario da applicare (oggi `ATO 5 BO`); si ricava dal CAP della sede dello stabile, che deve essere associato a un bacino | |

### 1.2 Configurazione dello stabile

| Parametro | Uso nel calcolo | Serve solo se |
|---|---|---|
| Servizio ACQUA gestito | Abilita il riparto idrico | |
| Acquedotto presente / fatturato | Abilita quota fissa acquedotto e perequazioni | |
| Fognatura presente / fatturata | Abilita quote fognatura e perequazioni | |
| Depurazione presente / fatturata | Abilita quote depurazione e perequazione UI1 | |
| Criterio della differenza di quadratura | Non ripartire · parti uguali · a consumo · millesimi generali · millesimi acqua · metri cubi utili | |
| Trattamento della differenza a credito | Stesso criterio · portare a nuovo · parti uguali | |
| Criterio delle altre partite | Stessa lista | |
| Criterio del costo del servizio di lettura | Stessa lista ("parti uguali" = in proporzione ai pesi delle unità) | |
| Costo del servizio di lettura | Per unità **oppure** totale di stabile | c'è un costo del servizio da ripartire |

### 1.3 Dati per unità immobiliare

| Parametro | Uso nel calcolo | Serve solo se |
|---|---|---|
| Uso tariffario (domestico residente, domestico non residente, commerciale, …) | Sceglie la tariffa dell'unità; stabilisce se l'uso è agevolato e/o pro capite | |
| Numero di componenti del nucleo | Moltiplica l'ampiezza degli scaglioni | l'uso ha tariffa pro capite (uso domestico residente) |
| Millesimi generali | Base di ripartizione | un criterio (differenze, altre partite, servizio) è "millesimi generali" |
| Millesimi acqua | Base di ripartizione | un criterio è "millesimi acqua" |
| Volume utile (m³) | Base di ripartizione | un criterio è "metri cubi utili" |
| Peso nel costo del servizio | Quota del costo del servizio; moltiplica il costo per unità | il costo del servizio è per unità o ripartito in parti uguali |
| Gestione dell'unità senza contatore | Blocca · esclusa · consumo zero con quote fisse · consumo massimo dello stabile | l'unità non ha contatori d'acqua |
| Destinazione d'uso «Parti comuni» (`PC`) | L'unità è esclusa dal riparto acqua | locali comuni censiti come unità |

### 1.4 Dati economici del periodo (bollette del gestore)

| Parametro | Uso nel calcolo | Serve solo se |
|---|---|---|
| Importo totale fatturato | Base della differenza di quadratura (importo fatturato − Σ quote a tariffa delle unità) | |
| Altre partite (non a consumo) | Depositi cauzionali, interessi, indennizzi, una-tantum | la bolletta contiene altre partite |
| Suddivisione della bolletta di impianto condiviso | La bolletta di super-condominio va prima divisa per stabile | l'allacciamento serve più stabili |

---

## 2. CALORE

Regole del documento di riferimento `Specifiche e Doc normativi/info_CalcoloRiparti2/` (UNI 10200, adeguamento del
2026-10-10); dettaglio del motore in `DB/CLAUDE.md` → *Calore*.

### 2.1 Generale (vale per RISC, ACS e RAFF)

Ogni servizio ha il suo riparto e la sua configurazione: salvo dove indicato, i parametri qui
sotto si impostano separatamente per ciascun servizio.

| Parametro | Uso nel calcolo | Serve solo se |
|---|---|---|
| Servizio gestito dallo stabile | Abilita il riparto del servizio | |
| Esonero dall'obbligo di contabilizzazione (sì/no) | Esonerato = intera spesa a soli millesimi, nessuna lettura né vincolo 50% | |
| Relazione tecnica di esonero | Giustifica l'esonero (art. 9 c. 5 lett. b/c; convenienza secondo UNI EN 15459) | il servizio è esonerato |
| Criterio millesimale | Ripartizione di quota involontaria, manutenzione (e costo del servizio): millesimi di servizio · proprietà · superficie · volume · capitari | |
| Dato dell'unità richiesto dal criterio | Millesimi di proprietà, superficie, volume o numero di occupanti (per i millesimi di servizio vedi 2.3–2.5); tutte le unità attive devono averlo, tranne le parti comuni | |
| Frazione di consumo involontario (0–1) | Quota di consumo non controllabile dall'occupante: involontario = frazione × energia del servizio, sull'intero edificio (con il fattore d'uso: frazione di progetto, vedi 2.3) | almeno un'unità è a ripartitori, oppure l'energia ACS è stimata (vedi 2.4) |
| Spesa per l'energia `a` (€) | Combustibile / teleriscaldamento / energia elettrica della pompa di calore del periodo; dalle bollette selezionate, modificabile | |
| Consumo della centrale `b` (kWh) | Energia del servizio; proposta dalla piattaforma (vedi 2.2), sempre modificabile | il servizio non è esonerato |
| Manutenzione e conduzione `h` (€) | Ripartita a millesimi; con RISC e ACS sulla stessa centrale il wizard divide la spesa totale con la Parte ACS delle spese di gestione | ci sono spese di conduzione/manutenzione |
| Costo del servizio di contabilizzazione `k_gest` | Per unità (× Σ pesi) **oppure** totale di stabile | c'è un costo del servizio da ripartire |
| Criterio del costo di servizio (unico per i tre servizi) | Vuoto = insieme alla manutenzione · non addebitare · per peso · per consumo · stesso criterio millesimale | c'è un costo del servizio e non va nel monte millesimale |
| Peso dell'unità nel costo di servizio (unico per i tre servizi) | Quota del costo; moltiplica il costo per unità | il costo del servizio è per unità o ripartito per peso |
| Gestione dell'unità senza dispositivi | Blocca · non servita (esclusa) · consumo zero con quota involontaria · consumo massimo fra le unità misurate · **consumo stimato** (predefinito: fabbisogno dell'unità, altrimenti millesimi del servizio — mai la superficie —, × consumo specifico delle unità misurate) | l'unità non ha dispositivi per il servizio |
| Fabbisogno o millesimi del servizio dell'unità | Base del consumo stimato | l'unità senza dispositivi è in «consumo stimato» |
| Prima stagione dopo l'installazione (opzione del riparto) | Intera spesa a millesimi di proprietà | l'assemblea lo decide |
| Destinazione d'uso «Parti comuni» (`PC`) dell'unità | La sua spesa va alle altre unità a millesimi di proprietà; nessuna quota involontaria | locali comuni con dispositivo |
| Millesimi di proprietà delle unità | Ripartizione della spesa delle parti comuni | ci sono parti comuni con dispositivo |

Il minimo del 50% (quota volontaria sulla spesa complessiva del servizio) non blocca il calcolo: se non è rispettato la
quota volontaria viene portata al 50% e il riparto lo segnala.

### 2.2 Energia di centrale e bollette (RISC e ACS con generatore in comune)

La piattaforma propone `b` nell'ordine: misuratori generali → bollette → totali mensili inseriti a mano.

| Parametro | Uso nel calcolo | Serve solo se |
|---|---|---|
| Misuratori generali di stabile (anche virtuali) | Energia di centrale misurata; **non più obbligatori** se ci sono bollette con coefficiente | si usano le misure di centrale |
| Il generale RISC misura RISC + ACS (sì/no) | Sì = RISC = totale − ACS; no = misuratori RISC e ACS separati | ci sono i misuratori generali |
| Coefficiente di conversione della bolletta (kWh per m³ / Smc fatturato) | Energia = consumo fatturato × coefficiente × rendimento | l'energia viene dalle bollette |
| Combustibile della centrale | Rapporto PCS/PCI del rendimento (metano 1.11, gasolio 1.07, GPL 1.09; teleriscaldamento = energia già utile) | l'energia viene dalle bollette |
| Rendimento di combustione del libretto di impianto | Rendimento = combustione / (PCS/PCI); senza = 0.85 predefinito (segnalato) | l'energia viene dalle bollette e il dato è disponibile |
| Divisione della bolletta di centrale in parte RISC e parte ACS | Ogni parte va a un solo riparto; quota ACS dai generali nel periodo della bolletta, altrimenti Parte ACS | lo stabile gestisce RISC e ACS con una bolletta unica |
| Parte ACS (%) | Quota dell'energia e della spesa di centrale per l'ACS (dato di progetto); si usa quando i generali non misurano nel periodo (senza Parte ACS: quota dell'ultimo anno dei generali); avviso se il gas dei mesi senza riscaldamento indica altro | bollette di centrale senza misura ACS in centrale |
| Parte ACS dell'energia elettrica (%) | Divisione proposta delle bollette del contatore elettrico della centrale fra RISC e ACS; vuota = Parte ACS | RISC e ACS sullo stesso contatore elettrico |
| Parte ACS delle spese di gestione (%) | Divisione della spesa di conduzione e manutenzione dell'impianto fra RISC e ACS; vuota = Parte ACS | RISC e ACS sulla stessa centrale |
| Stagione di riscaldamento (GG/MM, predefinita 15/10–15/04) | Fabbisogno di progetto dei riparti più corti; mesi senza riscaldamento per il controllo della Parte ACS | sempre (ha un valore predefinito) |
| Totali mensili di energia per servizio | Ultima fonte di `b` | mancano misuratori generali e bollette convertibili |
| Super-condominio: stabile master e criterio delle quote di stabile | La bolletta della centrale condivisa va prima divisa fra gli stabili: energia di ciascuno dal suo generale più le dispersioni a quote (somma del criterio, predefinito millesimi RISC) | una centrale serve più stabili |

### 2.3 Solo RISC

| Parametro | Uso nel calcolo | Serve solo se |
|---|---|---|
| Coefficienti KQ e KC del ripartitore (oppure K combinato) | Correggono le u.r. grezze: u.r. corrette = u.r. × KQ × KC (o × K) × fattore di base del modello | ci sono ripartitori |
| Fattore di base del modello di ripartitore | Moltiplica KQ × KC (Configurazione → Modelli misuratore; Qundis Q caloric 5.5 a due sensori, non programmato: 1 / 2.33); 1 = nessuno | modelli non programmati che lo richiedono |
| Quota involontaria dal fattore d'uso (sì/no) e fabbisogno di progetto dell'edificio (kWh) | UNI 10200:2018: fattore d'uso = energia RISC del riparto / fabbisogno (in proporzione ai giorni di riscaldamento del riparto); sotto 0.8 la frazione involontaria = 1 − (1 − frazione di progetto) / 0.8 × fattore d'uso | la relazione tecnica lo prevede |
| Millesimi di riscaldamento | Criterio "millesimi di servizio", prima scelta | criterio "millesimi di servizio" |
| Fabbisogno termico ideale (kWh, UNI/TS 11300-1) | Stesso criterio, per le unità senza millesimi | criterio "millesimi di servizio" e unità senza millesimi |
| Potenza installata (kW) | Stesso criterio, per le unità senza millesimi né fabbisogno | criterio "millesimi di servizio" e unità senza millesimi né fabbisogno |

Contabilizzazione mista (unità con contatore e unità a ripartitori): formula UNI 10200:2018 §8.7, senza fattore u.r. → kWh
(il fattore resta solo per i grafici dei consumi).

### 2.4 Solo ACS

| Parametro | Uso nel calcolo | Serve solo se |
|---|---|---|
| Contatori di acqua calda e fredda delle unità (m³) | Consumo volontario convenzionale = m³ × 1.162 kWh/(m³·K) × (temperatura dell'acqua calda − fredda) | le unità hanno contatori volumetrici |
| Energia ACS misurata in centrale | Involontario per differenza (energia − volontario convenzionale) | c'è il generale ACS |
| Frazione di consumo involontario ACS | Involontario = frazione × energia, il resto diviso sui consumi convenzionali | l'energia ACS è stimata (bollette con Parte ACS, totali mensili) |
| Millesimi ACS | Criterio "millesimi di servizio", prima scelta | criterio "millesimi di servizio" |
| Fabbisogno ACS (kWh, UNI/TS 11300-2) | Stesso criterio, per le unità senza millesimi | criterio "millesimi di servizio" e unità senza millesimi |
| Potenza installata ACS (kW) | Stesso criterio, per le unità senza millesimi né fabbisogno | criterio "millesimi di servizio" e unità senza millesimi né fabbisogno |

### 2.5 RAFF

| Parametro | Uso nel calcolo | Serve solo se |
|---|---|---|
| Coefficienti KQ e KC del ripartitore (oppure K combinato) | Come per il RISC | ci sono ripartitori |
| Millesimi raffrescamento | Criterio "millesimi di servizio", prima scelta | criterio "millesimi di servizio" |
| Fabbisogno di raffrescamento (kWh, UNI/TS 11300-1) | Stesso criterio, per le unità senza millesimi | criterio "millesimi di servizio" e unità senza millesimi |
| Potenza installata RAFF (kW) | Stesso criterio, per le unità senza millesimi né fabbisogno | criterio "millesimi di servizio" e unità senza millesimi né fabbisogno |
