# Andalusia NLP Pipeline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implementar el pipeline d'extracció de dades del Parlament d'Andalusia: `00_utils.R` + scripts 1-3 funcionals i provats contra l'API real; scripts 4-5 com a esbossos estructurats amb la lògica comentada.

**Architecture:** Scripts R autònoms que es criden individualment des de RStudio. `00_utils.R` centralitza helpers de xarxa i logging. Cada script comprova `file.exists()` abans de fer qualsevol petició i usa `tryCatch()` per continuar davant d'errors puntuals. Les dades flueixen via JSON al disc entre scripts.

**Tech Stack:** R 4.x — `rvest`, `httr2`, `jsonlite`, `stringr`, `dplyr`, `purrr`, `ellmer`, `arrow`

---

### Task 1: Setup — Estructura de directoris i `00_utils.R`

**Files:**
- Create: `00_scripts_R/00_utils.R`
- Create: directoris `01_dades_crues/` i `02_dades_processades/`

- [ ] **Step 1: Crear estructura de directoris**

Des de la terminal (o consola R amb `dir.create`):
```bash
mkdir -p 01_dades_crues/cataleg
mkdir -p 01_dades_crues/diputats
mkdir -p 01_dades_crues/sessions_esquelet
mkdir -p 01_dades_crues/intervencions_stt
mkdir -p 02_dades_processades/dataset_consolidat
mkdir -p 02_dades_processades/llm_frames
mkdir -p 00_scripts_R
```

- [ ] **Step 2: Escriure `00_scripts_R/00_utils.R`**

```r
# 00_scripts_R/00_utils.R
library(httr2)
library(stringr)

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a)) a else b

log_msg <- function(msg) {
  cat(format(Sys.time(), "[%Y-%m-%d %H:%M:%S]"), msg, "\n")
}

polite_delay <- function(seconds = 1) {
  Sys.sleep(seconds)
}

safe_get <- function(url) {
  tryCatch({
    request(url) |>
      req_user_agent("Mozilla/5.0 (compatible; RecercaParlement/1.0)") |>
      req_perform()
  }, error = function(e) {
    log_msg(paste("ERROR GET", url, ":", conditionMessage(e)))
    NULL
  })
}

file_done <- function(path) {
  file.exists(path) && file.size(path) > 10
}
```

- [ ] **Step 3: Verificar que `00_utils.R` es carrega correctament**

A la consola R (working directory = arrel del projecte):
```r
source("00_scripts_R/00_utils.R")
log_msg("Test utils")
# Esperat: [2026-04-23 HH:MM:SS] Test utils

stopifnot(is.function(log_msg))
stopifnot(is.function(polite_delay))
stopifnot(is.function(safe_get))
stopifnot(is.function(file_done))
stopifnot(is.function(`%||%`))
cat("OK: 00_utils.R carregat correctament\n")
```

- [ ] **Step 4: Commit**

```bash
git add 00_scripts_R/00_utils.R
git commit -m "feat: estructura directoris i helpers compartits (00_utils.R)"
```

---

### Task 2: Script 1 — Catàleg de vídeos i resolució `ID_MASTER`

**Files:**
- Create: `00_scripts_R/1_scraper_cataleg.R`
- Output: `01_dades_crues/cataleg/cataleg_videos.json`, `01_dades_crues/cataleg/cataleg_master.json`

- [ ] **Step 1: Inspecció prèvia de l'HTML (descoberta de selectors i paginació)**

```r
library(rvest)
library(httr2)
source("00_scripts_R/00_utils.R")

BASE_URL <- "https://videoteca.parlamentodeandalucia.es"
url <- paste0(BASE_URL, "/search?view_type=list&legs_id=3377&gbody_id=3378")
resp <- safe_get(url)
html <- read_html(resp_body_string(resp))

# Quants links de vídeo hi ha a la primera pàgina?
links <- html |> html_elements("a[href*='/watch?id=']")
cat("Links trobats:", length(links), "\n")
cat("Primer href:", links[1] |> html_attr("href"), "\n")
cat("Primer text:", links[1] |> html_text(trim = TRUE), "\n")

# Hi ha paginació? Busca links que continguin 'page='
pag <- html |> html_elements("a[href*='page=']")
cat("Links de paginació:", length(pag), "\n")
if (length(pag) > 0) cat("Exemple:", pag[1] |> html_attr("href"), "\n")
```

Anota el patró de paginació (ex: `&page=2`). Si no hi ha paginació, la funció `get_page_videos` ja gestionarà l'aturada.

- [ ] **Step 2: Escriure `00_scripts_R/1_scraper_cataleg.R`**

```r
# 00_scripts_R/1_scraper_cataleg.R
library(rvest)
library(httr2)
library(jsonlite)
library(stringr)
library(dplyr)

source("00_scripts_R/00_utils.R")

BASE_URL   <- "https://videoteca.parlamentodeandalucia.es"
OUT_VIDEOS <- "01_dades_crues/cataleg/cataleg_videos.json"
OUT_MASTER <- "01_dades_crues/cataleg/cataleg_master.json"
DEMO_MODE  <- FALSE  # TRUE = processa només les 2 primeres pàgines

# ── PART 1: Scraping del llistat ──────────────────────────────────────────────

get_page_videos <- function(page_num) {
  url  <- paste0(BASE_URL, "/search?view_type=list&legs_id=3377&gbody_id=3378&page=", page_num)
  log_msg(paste("Scraping pàgina", page_num))
  resp <- safe_get(url)
  if (is.null(resp)) return(NULL)

  html  <- read_html(resp_body_string(resp))
  items <- html |> html_elements("a[href*='/watch?id=']")
  if (length(items) == 0) return(NULL)

  hrefs  <- items |> html_attr("href")
  titols <- items |> html_text(trim = TRUE)
  ids    <- str_match(hrefs, "/watch\\?id=([A-Za-z0-9+/=_-]+)")[, 2]

  tibble(url_id = ids, titol = titols, href = hrefs) |>
    filter(!is.na(url_id), nchar(url_id) > 5, nchar(titol) > 2)
}

scrape_full_catalog <- function(max_pages = Inf) {
  all_videos <- list()
  page <- 1
  repeat {
    videos <- get_page_videos(page)
    if (is.null(videos) || nrow(videos) == 0) {
      log_msg(paste("Pàgina", page, "buida — fi de paginació"))
      break
    }
    all_videos[[page]] <- videos
    log_msg(paste("Pàgina", page, ":", nrow(videos), "vídeos"))
    if (page >= max_pages) break
    page <- page + 1
    polite_delay()
  }
  bind_rows(all_videos)
}

# ── PART 2: Resolució ID_MASTER (Pedra de Rosetta) ───────────────────────────

get_master_id <- function(url_id) {
  url  <- paste0(BASE_URL, "/watch?id=", url_id)
  resp <- safe_get(url)
  if (is.null(resp)) return(NA_integer_)

  html_text <- resp_body_string(resp)
  m <- str_match(html_text, "subject_id=(\\d+)")
  if (is.na(m[1, 1])) {
    log_msg(paste("  No subject_id per", url_id))
    return(NA_integer_)
  }
  as.integer(m[1, 2])
}

# ── EXECUCIÓ PRINCIPAL ────────────────────────────────────────────────────────

max_p <- if (DEMO_MODE) 2 else Inf

if (!file_done(OUT_VIDEOS)) {
  log_msg("=== PART 1: Scraping del catàleg ===")
  catalog <- scrape_full_catalog(max_pages = max_p)
  log_msg(paste("Total vídeos:", nrow(catalog)))
  write_json(catalog, OUT_VIDEOS, auto_unbox = TRUE, pretty = TRUE)
  log_msg(paste("Desat:", OUT_VIDEOS))
} else {
  log_msg(paste("Catàleg ja existeix:", OUT_VIDEOS))
  catalog <- as_tibble(fromJSON(OUT_VIDEOS))
}

if (!file_done(OUT_MASTER)) {
  log_msg("=== PART 2: Resolució ID_MASTER ===")
  if (!"id_master" %in% names(catalog)) catalog$id_master <- NA_integer_

  for (i in seq_len(nrow(catalog))) {
    if (!is.na(catalog$id_master[i])) next
    log_msg(paste("Resolent", i, "/", nrow(catalog), ":", catalog$url_id[i]))
    catalog$id_master[i] <- get_master_id(catalog$url_id[i])
    polite_delay()
  }

  write_json(catalog, OUT_MASTER, auto_unbox = TRUE, pretty = TRUE)
  log_msg(paste("Desat:", OUT_MASTER))
} else {
  log_msg(paste("Catàleg master ja existeix:", OUT_MASTER))
}
```

- [ ] **Step 3: Provar en DEMO_MODE (posa `DEMO_MODE <- TRUE` i executa)**

```r
source("00_scripts_R/1_scraper_cataleg.R")
```

- [ ] **Step 4: Verificar l'output**

```r
library(jsonlite)

videos <- fromJSON("01_dades_crues/cataleg/cataleg_videos.json")
stopifnot(nrow(videos) > 0)
stopifnot(all(c("url_id", "titol") %in% names(videos)))
cat("OK: cataleg_videos.json —", nrow(videos), "entrades\n")

master <- fromJSON("01_dades_crues/cataleg/cataleg_master.json")
stopifnot("id_master" %in% names(master))
n_resolts <- sum(!is.na(master$id_master))
cat("OK: cataleg_master.json —", n_resolts, "/", nrow(master), "IDs resolts\n")
# Si n_resolts == 0, el regex subject_id=(\d+) no ha trobat res → revisar el bloc JSPLAYLIST
stopifnot(n_resolts > 0)
cat("Primer ID_MASTER:", master$id_master[!is.na(master$id_master)][1], "\n")
```

- [ ] **Step 5: Executar en mode complet (`DEMO_MODE <- FALSE`) i verificar amb la mateixa bateria**

```r
# Esborra demos si vols tornar a executar des de zero:
# file.remove("01_dades_crues/cataleg/cataleg_videos.json")
# file.remove("01_dades_crues/cataleg/cataleg_master.json")
source("00_scripts_R/1_scraper_cataleg.R")
```

- [ ] **Step 6: Commit**

```bash
git add 00_scripts_R/1_scraper_cataleg.R
git commit -m "feat: scraper catàleg de vídeos + resolució ID_MASTER"
```

---

### Task 3: Script 2 — Taula de diputats

**Files:**
- Create: `00_scripts_R/2_scraping_diputats.R`
- Output: `01_dades_crues/diputats/diputats.json`

- [ ] **Step 1: Descobrir els `leg_id` per a les legislatures 10, 11 i 12**

```r
library(rvest)
library(httr2)
source("00_scripts_R/00_utils.R")

BASE_URL <- "https://videoteca.parlamentodeandalucia.es"
resp <- safe_get(paste0(BASE_URL, "/people"))
html <- read_html(resp_body_string(resp))

# Busca el dropdown de legislatura
opts <- html |> html_elements("select option")
cat("Totes les opcions de selects:\n")
for (o in opts) {
  cat(" [", html_attr(o, "value"), "]", html_text(o, trim = TRUE), "\n")
}
```

Identifica quins `value` corresponen a "Legislatura 10", "11" i "12". Substitueix els `NA_integer_` del pas 2.

- [ ] **Step 2: Escriure `00_scripts_R/2_scraping_diputats.R`**

```r
# 00_scripts_R/2_scraping_diputats.R
library(rvest)
library(httr2)
library(jsonlite)
library(stringr)
library(dplyr)
library(purrr)

source("00_scripts_R/00_utils.R")

BASE_URL <- "https://videoteca.parlamentodeandalucia.es"
OUT_FILE <- "01_dades_crues/diputats/diputats.json"

# Substitueix els NA per els valors descoberts al Step 1
LEG_IDS <- c(
  "10" = NA_integer_,   # <-- ID intern per a Legislatura 10
  "11" = NA_integer_,   # <-- ID intern per a Legislatura 11
  "12" = NA_integer_    # <-- ID intern per a Legislatura 12
)

scrape_deputies_page <- function(leg_id, leg_num) {
  url  <- paste0(BASE_URL, "/people?leg_id=", leg_id, "&gbody_id=&politic_id=")
  log_msg(paste("Scraping diputats legislatura", leg_num, "(leg_id=", leg_id, ")"))
  resp <- safe_get(url)
  if (is.null(resp)) return(tibble())

  html  <- read_html(resp_body_string(resp))
  items <- html |> html_elements("a[href*='/people/']")
  if (length(items) == 0) {
    log_msg(paste("  Sense resultats per leg_id=", leg_id))
    return(tibble())
  }

  hrefs <- items |> html_attr("href")
  noms  <- items |> html_text(trim = TRUE)
  slugs <- str_match(hrefs, "/people/([^/?#]+)$")[, 2]

  tibble(slug = slugs, nom = noms, legislatura = as.character(leg_num), leg_id = leg_id) |>
    filter(!is.na(slug), nchar(nom) > 2, !str_starts(slug, "http"))
}

enrich_deputy <- function(slug) {
  url  <- paste0(BASE_URL, "/people/", slug)
  resp <- safe_get(url)
  if (is.null(resp)) return(list(grup_parlamentari = NA_character_, partit = NA_character_))

  html <- read_html(resp_body_string(resp))

  # Prova selectors comuns per grup/partit; ajusta si cal
  grup <- tryCatch(
    html |> html_element("[class*='group'],[class*='grup'],[class*='party']") |> html_text(trim = TRUE),
    error = function(e) NA_character_
  ) %||% NA_character_

  partit <- tryCatch(
    html |> html_element("[class*='polit'],[class*='partido']") |> html_text(trim = TRUE),
    error = function(e) NA_character_
  ) %||% NA_character_

  list(grup_parlamentari = grup, partit = partit)
}

if (!file_done(OUT_FILE)) {
  log_msg("=== Scraping diputats ===")

  all_deputies <- imap_dfr(LEG_IDS, scrape_deputies_page)
  all_deputies <- distinct(all_deputies, slug, legislatura, .keep_all = TRUE)
  log_msg(paste("Total entrades (sense duplicats):", nrow(all_deputies)))

  all_deputies$grup_parlamentari <- NA_character_
  all_deputies$partit            <- NA_character_

  for (i in seq_len(nrow(all_deputies))) {
    log_msg(paste("Enriquint", i, "/", nrow(all_deputies), ":", all_deputies$slug[i]))
    info <- tryCatch(
      enrich_deputy(all_deputies$slug[i]),
      error = function(e) list(grup_parlamentari = NA_character_, partit = NA_character_)
    )
    all_deputies$grup_parlamentari[i] <- info$grup_parlamentari
    all_deputies$partit[i]            <- info$partit
    polite_delay()
  }

  write_json(all_deputies, OUT_FILE, auto_unbox = TRUE, pretty = TRUE)
  log_msg(paste("Desat:", OUT_FILE))
} else {
  log_msg(paste("Diputats ja existeix:", OUT_FILE))
}
```

- [ ] **Step 3: Executar i verificar**

```r
source("00_scripts_R/2_scraping_diputats.R")
```

```r
library(jsonlite)
diputats <- fromJSON("01_dades_crues/diputats/diputats.json")
stopifnot(nrow(diputats) > 50)
stopifnot(all(c("slug", "nom", "legislatura") %in% names(diputats)))
cat("OK:", nrow(diputats), "diputats\n")
cat("Legislatures:", paste(unique(diputats$legislatura), collapse = ", "), "\n")
print(head(diputats[, c("nom", "legislatura", "grup_parlamentari")], 5))
```

- [ ] **Step 4: Commit**

```bash
git add 00_scripts_R/2_scraping_diputats.R
git commit -m "feat: scraper diputats per legislatures 10-12"
```

---

### Task 4: Script 3 — Esquelets de sessions i transcripcions STT

**Files:**
- Create: `00_scripts_R/3_api_sessions.R`
- Output: `01_dades_crues/sessions_esquelet/{ID_MASTER}_esquelet.json`, `01_dades_crues/intervencions_stt/{ID_MASTER}_{NNN}_{nom}.json`

- [ ] **Step 1: Provar l'API de l'esquelet manualment i confirmar l'estructura JSON**

```r
library(httr2)
library(jsonlite)
source("00_scripts_R/00_utils.R")

master <- fromJSON("01_dades_crues/cataleg/cataleg_master.json")
id     <- master$id_master[!is.na(master$id_master)][1]
cat("Provant amb ID_MASTER:", id, "\n")

BASE_URL <- "https://videoteca.parlamentodeandalucia.es"
url  <- paste0(BASE_URL, "/api/masters/", id, "/timeline.json?start=0&end=999999999999")
resp <- safe_get(url)
data <- resp_body_json(resp, simplifyVector = FALSE)

# Confirma l'estructura
cat("Claus arrel:", paste(names(data), collapse = ", "), "\n")
seccions <- data$data$record$timeline$sections
cat("Seccions (punts del dia):", length(seccions), "\n")
cat("Primera secció — nom:", seccions[[1]]$name, "\n")
cat("Primera secció — sub-seccions (oradors):", length(seccions[[1]]$sections), "\n")
if (length(seccions[[1]]$sections) > 0) {
  primer_orador <- seccions[[1]]$sections[[1]]
  cat("Primer orador:", primer_orador$name, "start:", primer_orador$start, "end:", primer_orador$end, "\n")
}
```

Confirma que `data$data$record$timeline$sections` és el camí correcte. Si difereix, ajusta `fetch_stt` al pas 2.

- [ ] **Step 2: Provar l'API STT per a una intervenció concreta**

```r
# Usa els valors extrets al step 1
start_iv <- seccions[[1]]$sections[[1]]$start
end_iv   <- seccions[[1]]$sections[[1]]$end
url_stt  <- paste0(BASE_URL, "/api/masters/", id, "/timeline.json?start=", start_iv, "&end=", end_iv, "&stt=records")
resp_stt <- safe_get(url_stt)
data_stt <- resp_body_json(resp_stt, simplifyVector = FALSE)

# Confirma que hi ha array stt
seccions_stt <- data_stt$data$record$timeline$sections
cat("Seccions STT:", length(seccions_stt), "\n")
if (length(seccions_stt) > 0 && !is.null(seccions_stt[[1]]$sections)) {
  iv_stt <- seccions_stt[[1]]$sections[[1]]
  cat("Fragments STT:", length(iv_stt$stt), "\n")
  if (length(iv_stt$stt) > 0) cat("Primer fragment:", iv_stt$stt[[1]]$text, "\n")
}
```

- [ ] **Step 3: Escriure `00_scripts_R/3_api_sessions.R`**

```r
# 00_scripts_R/3_api_sessions.R
library(httr2)
library(jsonlite)
library(stringr)
library(dplyr)

source("00_scripts_R/00_utils.R")

BASE_URL    <- "https://videoteca.parlamentodeandalucia.es"
MASTER_FILE <- "01_dades_crues/cataleg/cataleg_master.json"
OUT_ESQUEL  <- "01_dades_crues/sessions_esquelet"
OUT_STT     <- "01_dades_crues/intervencions_stt"
DEMO_MODE   <- FALSE  # TRUE = processa les 2 primeres sessions

# ── PART 1: Baixada d'esquelets ───────────────────────────────────────────────

fetch_skeleton <- function(id_master) {
  out <- file.path(OUT_ESQUEL, paste0(id_master, "_esquelet.json"))
  if (file_done(out)) { log_msg(paste("  Esquelet ja existeix:", id_master)); return(invisible(NULL)) }

  url  <- paste0(BASE_URL, "/api/masters/", id_master, "/timeline.json?start=0&end=999999999999")
  resp <- safe_get(url)
  if (is.null(resp)) return(invisible(NULL))

  data <- tryCatch(
    resp_body_json(resp, simplifyVector = FALSE),
    error = function(e) { log_msg(paste("  Parse error esquelet", id_master)); NULL }
  )
  if (is.null(data)) return(invisible(NULL))

  write_json(data, out, auto_unbox = TRUE, pretty = FALSE)
  log_msg(paste("  Desat esquelet:", id_master))
}

# ── PART 2: Extracció d'intervencions i STT ───────────────────────────────────

# Extreu recursivament els nodes fulla (intervencions individuals sense sub-seccions)
extract_interventions <- function(sections) {
  result <- list()
  for (s in sections) {
    has_sub <- !is.null(s$sections) && length(s$sections) > 0
    if (has_sub) {
      result <- c(result, extract_interventions(s$sections))
    } else if (!is.null(s$name) && !str_starts(s$name, "\\[")) {
      result <- c(result, list(s))
    }
  }
  result
}

nom_fitxer_safe <- function(nom) {
  nom |>
    str_to_lower() |>
    iconv(from = "UTF-8", to = "ASCII//TRANSLIT") |>
    str_replace_all("[^a-z0-9]", "_") |>
    str_replace_all("_+", "_") |>
    str_trim("both") |>
    str_sub(1, 40)
}

fetch_stt <- function(id_master) {
  esq_path <- file.path(OUT_ESQUEL, paste0(id_master, "_esquelet.json"))
  if (!file_done(esq_path)) { log_msg(paste("  Esquelet no trobat per", id_master)); return(invisible(NULL)) }

  esq      <- fromJSON(esq_path, simplifyVector = FALSE)
  sections <- tryCatch(
    esq$data$record$timeline$sections,
    error = function(e) { log_msg(paste("  Estructura inesperada per", id_master)); NULL }
  )
  if (is.null(sections)) return(invisible(NULL))

  interventions <- extract_interventions(sections)
  log_msg(paste("  Session", id_master, ":", length(interventions), "intervencions"))

  for (i in seq_along(interventions)) {
    iv       <- interventions[[i]]
    nom_safe <- nom_fitxer_safe(iv$name %||% "unknown")
    out      <- file.path(OUT_STT, sprintf("%s_%03d_%s.json", id_master, i, nom_safe))
    if (file_done(out)) next

    url <- paste0(
      BASE_URL, "/api/masters/", id_master,
      "/timeline.json?start=", iv$start, "&end=", iv$end, "&stt=records"
    )
    resp <- safe_get(url)
    if (is.null(resp)) { log_msg(paste("    ERROR STT", i, iv$name)); next }

    data <- tryCatch(resp_body_json(resp, simplifyVector = FALSE), error = function(e) NULL)
    if (!is.null(data)) write_json(data, out, auto_unbox = TRUE, pretty = FALSE)

    polite_delay(0.5)
  }
  log_msg(paste("  Session", id_master, "completada"))
}

# ── EXECUCIÓ PRINCIPAL ────────────────────────────────────────────────────────

master <- as_tibble(fromJSON(MASTER_FILE)) |> filter(!is.na(id_master))
if (DEMO_MODE) master <- head(master, 2)
log_msg(paste("Sessions a processar:", nrow(master)))

log_msg("=== PART 1: Esquelets ===")
for (id in master$id_master) { fetch_skeleton(id); polite_delay() }

log_msg("=== PART 2: STT ===")
for (id in master$id_master) { fetch_stt(id) }

log_msg("=== FI 3_api_sessions.R ===")
```

- [ ] **Step 4: Executar en DEMO_MODE (2 sessions) i verificar**

Posa `DEMO_MODE <- TRUE` i executa:
```r
source("00_scripts_R/3_api_sessions.R")
```

```r
esq_files <- list.files("01_dades_crues/sessions_esquelet", "\\.json$")
stt_files <- list.files("01_dades_crues/intervencions_stt", "\\.json$")
stopifnot(length(esq_files) >= 1)
stopifnot(length(stt_files) >= 1)
cat("OK: esquelets:", length(esq_files), "| STT:", length(stt_files), "\n")

# Verifica que un fitxer STT té contingut real
stt_data <- fromJSON(file.path("01_dades_crues/intervencions_stt", stt_files[1]), simplifyVector = FALSE)
cat("Claus JSON STT:", paste(names(stt_data), collapse = ", "), "\n")
cat("Fitxer:", stt_files[1], "\n")
```

- [ ] **Step 5: Executar en mode complet (`DEMO_MODE <- FALSE`)**

```r
source("00_scripts_R/3_api_sessions.R")
```

- [ ] **Step 6: Commit**

```bash
git add 00_scripts_R/3_api_sessions.R
git commit -m "feat: baixada esquelets i STT per a totes les sessions"
```

---

### Task 5: Script 4 — Esbós LLM Framing (ellmer)

**Files:**
- Create: `00_scripts_R/4_llm_framing.R`

- [ ] **Step 1: Escriure l'esbós de `4_llm_framing.R`**

```r
# 00_scripts_R/4_llm_framing.R
# ESBÓS — Executa quan els fitxers STT de 3_api_sessions.R estiguin complets.
#
# Objectiu: Filtrar intervencions que mencionen Catalunya i classificar-les
# amb LLM via ellmer (structured output) seguint el Codebook del PLAN.md.

library(ellmer)
library(jsonlite)
library(stringr)
library(dplyr)
library(purrr)

source("00_scripts_R/00_utils.R")
readRenviron(".env")  # carrega OPENAI_API i LLM_MODEL

STT_DIR  <- "01_dades_crues/intervencions_stt"
OUT_DIR  <- "02_dades_processades/llm_frames"
MODEL    <- Sys.getenv("LLM_MODEL", unset = "gpt-4o-mini")
API_KEY  <- Sys.getenv("OPENAI_API")

# ── Filtre per keyword ────────────────────────────────────────────────────────

REGEX_CATALUNYA <- "(?i)catalu[\\u00f1n]a|catalanes|generalitat|independentistas|separatistas"

extract_full_text <- function(stt_path) {
  # Llegeix el JSON STT i concatena tots els fragments de text de l'array stt
  data <- tryCatch(fromJSON(stt_path, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(data)) return(NA_character_)

  # Navega l'estructura fins als arrays stt (ajustar si cal segons estructura real)
  tryCatch({
    sections_top <- data$data$record$timeline$sections
    all_text <- unlist(lapply(sections_top, function(point) {
      lapply(point$sections %||% list(), function(iv) {
        paste(sapply(iv$stt %||% list(), function(frag) frag$text %||% ""), collapse = " ")
      })
    }))
    paste(all_text, collapse = " ")
  }, error = function(e) NA_character_)
}

# ── Schema del Codebook (ellmer type definitions) ─────────────────────────────

frame_type <- type_object(
  "Anàlisi de framing polític",
  chain_of_thought = type_string(
    "Raonament explícit (màx. 3-4 frases) basat en les regles d'exclusió del codebook"
  ),
  sentiment_cat = type_enum(
    "Sentiment cap a Catalunya/institucions catalanes",
    c("Hostil_Negatiu", "Neutral_Institucional", "Empàtic_Positiu")
  ),
  primary_frame = type_enum(
    "Marc discursiu principal",
    c("Grievance_Economics", "Constitutional_Threat", "Electoral_Weaponization", "Positive_Reference", "Other")
  ),
  confidence_score = type_number("Certesa de la classificació entre 0.0 i 1.0")
)

# ── System prompt amb definicions i few-shot examples ─────────────────────────

SYSTEM_PROMPT <- "La teva tasca com a assistent d'investigació computacional és analitzar extractes
d'intervencions de diputats del Parlament d'Andalusia que contenen mencions a Catalunya.
Per a cada extracte, determina el Sentiment i el Frame seguint ESTRICTAMENT les definicions.

SENTIMENT:
- Hostil_Negatiu: Llenguatge pejoratiu o d'alarma (golpistas, chantaje, ruptura, privilegios)
- Neutral_Institucional: Fets objectius, dades, procediments sense càrrega valorativa
- Empàtic_Positiu: Solidaritat, Catalunya com a exemple positiu, crida al diàleg

FRAMES:
- Grievance_Economics: Andalusia infrafinançada per concessions a Catalunya [excloure si no hi ha comparació directa]
- Constitutional_Threat: Catalunya com amenaça a la unitat d'Espanya [excloure si crítica és només econòmica]
- Electoral_Weaponization: Pactes catalans per atacar PSOE/PP/Sumar [ha d'incloure atac a partit nacional]
- Positive_Reference: Catalunya com a model de bona pràctica [excloure si és aliança política sense model concret]
- Other: Mencions que no encaixen en cap marc anterior

EXEMPLES:
Text: 'callan mientras su jefe en Moncloa riega con miles de millones a los separatistas para mantenerse en el sillón, robándole el dinero a los hospitales de Sevilla'
→ sentiment_cat: Hostil_Negatiu, primary_frame: Electoral_Weaponization

Text: 'En Cataluña, el tejido industrial lleva años colaborando con los centros educativos, con una tasa de inserción que aquí deberíamos aspirar a replicar'
→ sentiment_cat: Empàtic_Positiu, primary_frame: Positive_Reference"

# ── EXECUCIÓ PRINCIPAL (descomenta quan les dades STT estiguin completes) ──────

# stt_files <- list.files(STT_DIR, "\\.json$", full.names = TRUE)
# log_msg(paste("Total fitxers STT:", length(stt_files)))
#
# chat <- chat_openai(
#   model         = MODEL,
#   system_prompt = SYSTEM_PROMPT,
#   api_key       = API_KEY
# )
#
# n_classificats <- 0
# for (stt_path in stt_files) {
#   nom      <- basename(stt_path)
#   out_path <- file.path(OUT_DIR, nom)
#   if (file_done(out_path)) next
#
#   text <- extract_full_text(stt_path)
#   if (is.na(text) || !str_detect(text, REGEX_CATALUNYA)) next
#
#   n_classificats <- n_classificats + 1
#   log_msg(paste("Classificant:", nom))
#   result <- tryCatch(
#     chat$extract_data(text, type = frame_type),
#     error = function(e) { log_msg(paste("  LLM error:", conditionMessage(e))); NULL }
#   )
#   if (!is.null(result)) write_json(result, out_path, auto_unbox = TRUE, pretty = TRUE)
#   polite_delay(0.3)
# }
# log_msg(paste("Intervencions classificades:", n_classificats))
```

- [ ] **Step 2: Commit**

```bash
git add 00_scripts_R/4_llm_framing.R
git commit -m "sketch: 4_llm_framing.R amb ellmer i codebook complet"
```

---

### Task 6: Script 5 — Esbós Anàlisi i Plots

**Files:**
- Create: `00_scripts_R/5_analisi_i_plots.qmd`

- [ ] **Step 1: Escriure l'esbós de `5_analisi_i_plots.qmd`**

````markdown
---
title: "Anàlisi NLP: Framing de Catalunya al Parlament d'Andalusia"
format: html
date: today
---

```{r setup}
#| include: false
library(dplyr)
library(ggplot2)
library(jsonlite)
library(purrr)
library(stringr)
library(arrow)
library(tidyr)
```

## 1. Càrrega de dades

```{r load-frames}
# Executa 4_llm_framing.R abans d'arribar aquí
llm_files <- list.files("02_dades_processades/llm_frames", "\\.json$", full.names = TRUE)
cat("Fitxers LLM disponibles:", length(llm_files), "\n")

frames_df <- map_dfr(llm_files, function(f) {
  data <- tryCatch(fromJSON(f), error = function(e) NULL)
  if (is.null(data)) return(tibble())
  nom   <- tools::file_path_sans_ext(basename(f))
  parts <- str_match(nom, "^(\\d+)_(\\d+)_(.+)$")
  tibble(
    id_master        = as.integer(parts[1, 2]),
    ordre            = as.integer(parts[1, 3]),
    diputat_slug     = parts[1, 4],
    chain_of_thought = data$chain_of_thought,
    sentiment_cat    = data$sentiment_cat,
    primary_frame    = data$primary_frame,
    confidence_score = data$confidence_score
  )
})
cat("Intervencions classificades:", nrow(frames_df), "\n")
```

## 2. Join amb catàleg (legislatura) i diputats (partit)

```{r joins}
catalog  <- fromJSON("01_dades_crues/cataleg/cataleg_master.json")   |> as_tibble()
diputats <- fromJSON("01_dades_crues/diputats/diputats.json")         |> as_tibble()

# TODO: Afegir data/legislatura des del catàleg
# frames_df <- frames_df |> left_join(select(catalog, id_master, data, ...), by = "id_master")

# TODO: Normalitzar diputat_slug i fer join amb diputats
# frames_df <- frames_df |> left_join(select(diputats, slug, nom, partit, grup_parlamentari), by = c("diputat_slug" = "slug"))
```

## 3. Variable de control: Estatus del Partit (Govern/Oposició)

```{r gov-status}
# PSOE governa legislatures 10-11 | PP governa legislatura 12
# TODO: Un cop el join de legislatura estigui fet:
# frames_df <- frames_df |>
#   mutate(
#     estatus_psoe = if_else(legislatura %in% c("10", "11"), "Govern", "Oposició"),
#     estatus_pp   = if_else(legislatura == "12", "Govern", "Oposició")
#   )
```

## 4. Evolució de frames per legislatura

```{r plot-frames}
# TODO: Descomenta quan el join legislatura estigui complet
# frames_df |>
#   count(primary_frame, legislatura) |>
#   ggplot(aes(x = legislatura, y = n, fill = primary_frame)) +
#   geom_col(position = "fill") +
#   scale_y_continuous(labels = scales::percent) +
#   labs(
#     title    = "Evolució dels frames discursius sobre Catalunya",
#     subtitle = "Parlament d'Andalusia, legislatures 10–12",
#     x = "Legislatura", y = "Proporció", fill = "Frame"
#   ) +
#   theme_minimal()
```

## 5. Evolució del sentiment per legislatura

```{r plot-sentiment}
# TODO: Descomenta quan el join legislatura estigui complet
# frames_df |>
#   count(sentiment_cat, legislatura) |>
#   ggplot(aes(x = legislatura, y = n, fill = sentiment_cat)) +
#   geom_col(position = "fill") +
#   scale_fill_manual(values = c(
#     "Hostil_Negatiu"       = "#d73027",
#     "Neutral_Institucional" = "#fee090",
#     "Empàtic_Positiu"      = "#4575b4"
#   )) +
#   labs(title = "Evolució del sentiment cap a Catalunya") +
#   theme_minimal()
```
````

- [ ] **Step 2: Commit**

```bash
git add 00_scripts_R/5_analisi_i_plots.qmd
git commit -m "sketch: 5_analisi_i_plots.qmd estructura, TODOs i control endogen"
```
