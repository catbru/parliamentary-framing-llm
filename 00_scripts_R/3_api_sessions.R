# 00_scripts_R/3_api_sessions.R
#
# Baixada d'esquelets de sessions i intervencions amb STT.
#
# Estructura real de l'API (verificada per inspecció directa):
#   Esquelet: GET /api/masters/{ID}/timeline.json?start=0&end=999999999999
#     → data.record.timeline.sections (2 nivells: punts de l'ordre del dia → oradors)
#     → Marcadors de sistema: seccions amb nom que comença amb "[" ([START],[END],[GAP])
#
#   STT:      GET /api/masters/{ID}/timeline.json?start={start}&end={end}&stt=records
#     → Mateixa estructura; els nodes fulla (oradors) contenen `stt: [{start,end,text},...]`
#     → L'array stt pot ser buit si no hi ha transcripció disponible per a la sessió.
#
# Output:
#   01_dades_crues/sessions_esquelet/{ID_MASTER}_esquelet.json  (un per sessió)
#   01_dades_crues/intervencions_stt/{ID_MASTER}_{NNN}_{nom}.json  (un per intervenció)

library(httr2)
library(jsonlite)
library(stringr)
library(dplyr)

source("00_scripts_R/00_utils.R")

BASE_URL    <- "https://videoteca.parlamentodeandalucia.es"
MASTER_FILE <- "01_dades_crues/cataleg/cataleg_master.json"
OUT_ESQUEL  <- "01_dades_crues/sessions_esquelet"
OUT_STT     <- "01_dades_crues/intervencions_stt"
DEMO_MODE   <- FALSE  # TRUE = processa només les 2 primeres sessions

# ── Assegurar directoris de sortida ───────────────────────────────────────────
dir.create(OUT_ESQUEL, showWarnings = FALSE, recursive = TRUE)
dir.create(OUT_STT,    showWarnings = FALSE, recursive = TRUE)

# ── PART 1: Baixada d'esquelets ───────────────────────────────────────────────

fetch_skeleton <- function(id_master) {
  out <- file.path(OUT_ESQUEL, paste0(id_master, "_esquelet.json"))
  if (file_done(out)) {
    log_msg(paste("  Esquelet ja existeix:", id_master))
    return(invisible(NULL))
  }

  url  <- paste0(BASE_URL, "/api/masters/", id_master,
                 "/timeline.json?start=0&end=999999999999")
  resp <- safe_get(url)
  if (is.null(resp)) return(invisible(NULL))

  data <- tryCatch(
    resp_body_json(resp, simplifyVector = FALSE),
    error = function(e) {
      log_msg(paste("  Error de parse en esquelet", id_master, ":", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(data)) return(invisible(NULL))

  write_json(data, out, auto_unbox = TRUE, pretty = FALSE)
  log_msg(paste("  Esquelet desat:", id_master))
}

# ── PART 2: Extracció d'intervencions i STT ───────────────────────────────────

# Recorre recursivament les seccions i extreu els nodes fulla (intervencions individuals).
# Els nodes fulla són aquells sense sub-seccions i amb nom que no comença amb "[".
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

# Converteix un nom d'orador en un string segur per a noms de fitxer
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
  if (!file_done(esq_path)) {
    log_msg(paste("  Esquelet no trobat per a", id_master))
    return(invisible(NULL))
  }

  esq <- tryCatch(
    fromJSON(esq_path, simplifyVector = FALSE),
    error = function(e) {
      log_msg(paste("  Error llegint esquelet", id_master, ":", conditionMessage(e)))
      NULL
    }
  )
  if (is.null(esq)) return(invisible(NULL))

  sections <- tryCatch(
    esq$data$record$timeline$sections,
    error = function(e) {
      log_msg(paste("  Estructura inesperada per a", id_master))
      NULL
    }
  )
  if (is.null(sections)) return(invisible(NULL))

  interventions <- extract_interventions(sections)
  log_msg(paste("  Sessió", id_master, ":", length(interventions), "intervencions"))

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
    if (is.null(resp)) {
      log_msg(paste("    ERROR STT", i, iv$name))
      next
    }

    data <- tryCatch(
      resp_body_json(resp, simplifyVector = FALSE),
      error = function(e) {
        log_msg(paste("    Parse error STT", i, iv$name, ":", conditionMessage(e)))
        NULL
      }
    )
    if (!is.null(data)) {
      write_json(data, out, auto_unbox = TRUE, pretty = FALSE)
    }

    polite_delay(0.5)
  }
  log_msg(paste("  Sessió", id_master, "completada"))
}

# ── PRINCIPAL ─────────────────────────────────────────────────────────────────

master <- as_tibble(fromJSON(MASTER_FILE)) |> filter(!is.na(id_master))
if (DEMO_MODE) master <- head(master, 2)
log_msg(paste("Sessions a processar:", nrow(master)))

log_msg("=== PART 1: Esquelets ===")
for (id in master$id_master) {
  fetch_skeleton(id)
  polite_delay()
}

log_msg("=== PART 2: STT ===")
for (id in master$id_master) {
  fetch_stt(id)
}

log_msg("=== FI: 3_api_sessions.R ===")
