# Disseny: Pipeline NLP Parlament d'Andalusia

**Data:** 2026-04-23
**Estat:** Aprovat

## Resum

Pipeline en R per extreure, estructurar i analitzar les intervencions del Parlament d'Andalusia. Scripts 1-3 s'implementen i es proven completament; scripts 4-5 queden com a esbossos estructurats.

## Arquitectura

### Estructura de fitxers

```
00_scripts_R/
├── 00_utils.R              # helpers compartits (delay, logging, file.exists guard)
├── 1_scraper_cataleg.R     # [COMPLET + PROVAT]
├── 2_scraping_diputats.R   # [COMPLET + PROVAT]
├── 3_api_sessions.R        # [COMPLET + PROVAT]
├── 4_llm_framing.R         # [ESBÓS]
└── 5_analisi_i_plots.qmd   # [ESBÓS]

01_dades_crues/
├── cataleg/
│   ├── cataleg_videos.json
│   └── cataleg_master.json
├── diputats/
│   └── diputats.json
├── sessions_esquelet/
│   └── {ID_MASTER}_esquelet.json
└── intervencions_stt/
    └── {ID_MASTER}_{ordre}_{nom}.json

02_dades_processades/
├── dataset_consolidat/
│   └── corpus_complet.parquet
└── llm_frames/
    └── {ID_MASTER}_{ordre}_{nom}.json
```

### Principis

- **Autònom:** cada script és independent, s'executa per separat des de RStudio
- **Resilient:** `file.exists()` + `tryCatch()` a tots els bucles de xarxa; si s'interromp, es reprèn on s'ha quedat
- **Stack:** R + `rvest`, `httr2`, `jsonlite`, `stringr`, `dplyr`, `purrr`
- **API LLM:** OpenAI (clau a `.env` com `OPENAI_API`)

## Flux de dades per script

### `00_utils.R`
Funcions compartides: `safe_get()` (httr2 + tryCatch), `polite_delay()` (Sys.sleep configurable, defecte 1s), `log_msg()` (timestamp + missatge a consola).

### `1_scraper_cataleg.R`
1. Pagina `/search?view_type=list&legs_id=3377&gbody_id=3378` amb `rvest`
2. Extreu tots els `href` amb patró `/watch?id=...` → array d'IDs Base64
3. Desa metadades bàsiques (títol, data) → `cataleg_videos.json`
4. Per cada ID Base64: GET `/watch?id=...`, extreu `subject_id=(\d+)` del bloc `<!-- JSPLAYLIST -->` amb regex
5. Afegeix `ID_MASTER` a cada registre → `cataleg_master.json`

### `2_scraping_diputats.R`
1. Itera legislatures 10, 11, 12 via `/people?leg_id=...`
2. Per cada diputat al llistat: extreu nom normalitzat, slug, grup parlamentari, partit
3. (Opcional) GET a `/people/{slug}` per metadades addicionals
4. Desa → `diputats.json`

### `3_api_sessions.R`
1. Llegeix `cataleg_master.json`
2. **Pas 1 (Esquelet):** Per cada `ID_MASTER`, si no existeix `{ID}_esquelet.json`:
   GET `/api/masters/{ID}/timeline.json?start=0&end=999999999999` → desa JSON
3. **Pas 2 (STT):** Llegeix l'esquelet, itera intervencions; per cada una, si no existeix `{ID}_{ordre}_{nom}.json`:
   GET `/api/masters/{ID}/timeline.json?start={start}&end={end}&stt=records` → desa JSON
4. Delay entre peticions per no sobrecarregar el servidor

### `4_llm_framing.R` (ESBÓS)
- Filtre regex: `(?i)catalu[ñn]a|catalanes|generalitat|independentistas`
- Per cada intervenció filtrada: construeix prompt (system + few-shot examples del Codebook)
- Crida API OpenAI amb `response_format = json_schema` forçant l'schema del Codebook
- Output: `{ID}_{ordre}_{nom}.json` a `02_dades_processades/llm_frames/`

### `5_analisi_i_plots.qmd` (ESBÓS)
- Llegeix `corpus_complet.parquet` + fitxers `llm_frames/`
- Creuament amb `diputats.json` per afegir `partit` i `legislatura`
- Creuament amb variable `estatus_partit` (Govern/Oposició) per control endogen
- Visualitzacions: evolució temporal de frames per partit, heatmaps sentiment × legislatura

## JSON Schema (Codebook LLM)

```json
{
  "type": "object",
  "properties": {
    "chain_of_thought": { "type": "string" },
    "sentiment_cat": {
      "type": "string",
      "enum": ["Hostil_Negatiu", "Neutral_Institucional", "Empàtic_Positiu"]
    },
    "primary_frame": {
      "type": "string",
      "enum": ["Grievance_Economics", "Constitutional_Threat", "Electoral_Weaponization", "Positive_Reference", "Other"]
    },
    "confidence_score": { "type": "number" }
  },
  "required": ["chain_of_thought", "sentiment_cat", "primary_frame", "confidence_score"],
  "additionalProperties": false
}
```

## Decisions tècniques

| Decisió | Elecció | Motiu |
|---|---|---|
| Arquitectura | Scripts autònoms + `00_utils.R` | Resiliència, facilitat de reprendre, sense dependencies extra |
| Scraping catàleg | `rvest` (R) | Stack R obligatori per CLAUDE.md |
| Legislatures incloses | 10, 11, 12 | Les úniques amb STT disponible |
| Delay entre peticions | 1s (configurable) | Respecte al servidor, evitar bloquejos |
| Format intermedi | JSON per fitxer | Traçabilitat, reprendre sense perdre progrés |
| Format anàlisi | `.parquet` | Càrrega ràpida en R, millor que llegir milers de JSONs |
