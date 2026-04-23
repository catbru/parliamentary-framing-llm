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
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
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
