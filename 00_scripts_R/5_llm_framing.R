# 00_scripts_R/5_llm_framing.R
#
# Classifica amb LLM les intervencions que mencionen Catalunya (mencio_cat_ext).
#
# Input:   02_dades_processades/dataset_consolidat/corpus_intervencions.csv
# Output:  02_dades_processades/llm_frames/llm_progress.csv   (checkpoint incremental)
#          02_dades_processades/dataset_consolidat/corpus_amb_llm.csv  (join final)
#
# Idempotent: salta les files que ja apareguin al checkpoint.
# El checkpoint s'escriu fila a fila (append) per sobreviure interrupcions.
# DEMO_MODE: TRUE = processa només les 10 primeres intervencions pendents.

library(ellmer)
library(jsonlite)
library(stringr)
library(dplyr)

source("00_scripts_R/00_utils.R")
readRenviron(".env")

# ── Constants ─────────────────────────────────────────────────────────────────
DEMO_MODE    <- FALSE  # canvia a FALSE per processar totes les intervencions
IN_CSV       <- "02_dades_processades/dataset_consolidat/corpus_intervencions.csv"
PROGRESS_CSV <- "02_dades_processades/llm_frames/llm_progress.csv"
OUT_LLM_CSV  <- "02_dades_processades/dataset_consolidat/corpus_amb_llm.csv"
MODEL        <- Sys.getenv("LLM_MODEL", unset = "gpt-4o-mini")
API_KEY      <- Sys.getenv("OPENAI_API")

dir.create("02_dades_processades/llm_frames", showWarnings = FALSE, recursive = TRUE)

# ── Schema estructurat (ellmer) ───────────────────────────────────────────────
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
    c("Grievance_Economics", "Constitutional_Threat",
      "Electoral_Weaponization", "Positive_Reference", "Other")
  ),
  confidence_score = type_number("Certesa de la classificació entre 0.0 i 1.0")
)

# ── System prompt ─────────────────────────────────────────────────────────────
SYSTEM_PROMPT <- "La teva tasca com a assistent d'investigació computacional és analitzar
extractes d'intervencions de diputats del Parlament d'Andalusia que contenen mencions
a Catalunya. Per a cada extracte, determina el Sentiment i el Frame seguint
ESTRICTAMENT les definicions i regles d'exclusió.

SENTIMENT (variable: sentiment_cat):
- Hostil_Negatiu: Llenguatge pejoratiu, agressiu o d'alarma (golpistas, chantaje,
  ruptura, privilegios, separatistas).
- Neutral_Institucional: Fets objectius, dades estadístiques, procediments legals
  sense càrrega valorativa explícita.
- Empàtic_Positiu: Solidaritat, Catalunya com a exemple positiu, crida al diàleg
  plurinacional.

FRAMES (variable: primary_frame):
- Grievance_Economics: Andalusia infrafinançada per concessions econòmiques a
  Catalunya. EXCLUSIÓ: no usar si no hi ha comparació directa amb Andalusia.
- Constitutional_Threat: Catalunya com amenaça a la unitat d'Espanya, l'Estat de Dret
  o la igualtat dels espanyols. EXCLUSIÓ: no usar si la crítica és només econòmica.
- Electoral_Weaponization: Pactes amb partits catalans usats per atacar un rival
  polític nacional (PSOE, PP, Sumar, etc.). EXCLUSIÓ: l'atac ha d'incloure un
  partit nacional, no exclusivament el govern català.
- Positive_Reference: Catalunya com a model de bona pràctica o referent d'èxit.
  EXCLUSIÓ: no usar si la menció positiva és merament una aliança política sense
  referenciar un model de gestió concret.
- Other: Mencions que no encaixen en cap marc (resultats esportius, referències
  geogràfiques menors, tràmits).

EXEMPLES:
Text: 'callan mientras su jefe en Moncloa riega con miles de millones a los
separatistas para mantenerse en el sillón, robándole el dinero a los hospitales de
Sevilla y Jaén'
→ sentiment_cat: Hostil_Negatiu | primary_frame: Electoral_Weaponization

Text: 'En Cataluña, el tejido industrial lleva años colaborando con los centros
educativos, con una tasa de inserción laboral que aquí deberíamos aspirar a replicar'
→ sentiment_cat: Empàtic_Positiu | primary_frame: Positive_Reference"

# ── PART 1: Carrega corpus i determina pendents ───────────────────────────────
log_msg("=== 5_llm_framing.R ===")
log_msg(paste("Model:", MODEL))

corpus <- read.csv(IN_CSV, stringsAsFactors = FALSE)
log_msg(paste("Corpus carregat:", nrow(corpus), "intervencions"))

to_process <- corpus |>
  filter(mencio_cat_ext == TRUE, n_paraules >= 20) |>
  mutate(row_key = paste(id_master, intervencio_ordre, sep = "_"))
log_msg(paste("Intervencions elegibles (mencio_cat_ext + ≥20 paraules):", nrow(to_process)))

# ── PART 2: Carrega progrés existent ──────────────────────────────────────────
if (file.exists(PROGRESS_CSV)) {
  progress  <- read.csv(PROGRESS_CSV, stringsAsFactors = FALSE) |>
    mutate(id_master         = suppressWarnings(as.integer(id_master)),
           intervencio_ordre = suppressWarnings(as.integer(intervencio_ordre))) |>
    filter(!is.na(id_master), !is.na(intervencio_ordre)) |>
    mutate(row_key = paste(id_master, intervencio_ordre, sep = "_"))
  done_keys <- progress$row_key
  log_msg(paste("Progrés anterior:", length(done_keys), "ja classificades"))
} else {
  done_keys <- character(0)
  log_msg("Checkpoint buit. Iniciant des de zero.")
}

pending <- to_process |> filter(!row_key %in% done_keys)
log_msg(paste("Pendents:", nrow(pending)))

if (DEMO_MODE) {
  pending <- slice_head(pending, n = 10)
  log_msg("DEMO_MODE: limitant a 10 intervencions")
}

# ── PART 3: Classificació LLM ─────────────────────────────────────────────────
n_ok  <- 0L
n_err <- 0L

for (i in seq_len(nrow(pending))) {
  row <- pending[i, ]
  log_msg(sprintf("[%d/%d] %s (%s)", i, nrow(pending), row$orador, row$fecha))

  chat <- chat_openai(
    model         = MODEL,
    system_prompt = SYSTEM_PROMPT,
    api_key       = API_KEY
  )

  result <- tryCatch(
    chat$chat_structured(row$text, type = frame_type),
    error = function(e) {
      log_msg(paste("  LLM error:", conditionMessage(e)))
      NULL
    }
  )

  if (!is.null(result)) {
    new_row <- data.frame(
      id_master         = row$id_master,
      intervencio_ordre = row$intervencio_ordre,
      llm_sentiment_cat = result$sentiment_cat,
      llm_primary_frame = result$primary_frame,
      llm_confidence    = round(result$confidence_score, 3),
      llm_reasoning     = str_replace_all(result$chain_of_thought, "\n", " "),
      llm_ts            = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      stringsAsFactors  = FALSE
    )

    write.table(
      new_row, PROGRESS_CSV,
      append    = file.exists(PROGRESS_CSV),
      sep       = ",",
      col.names = !file.exists(PROGRESS_CSV),
      row.names = FALSE,
      quote     = TRUE,
      fileEncoding = "UTF-8"
    )

    log_msg(sprintf("  → %s / %s (conf %.2f)",
                    result$sentiment_cat, result$primary_frame,
                    result$confidence_score))
    n_ok <- n_ok + 1L
  } else {
    n_err <- n_err + 1L
  }

  if (!DEMO_MODE) polite_delay(0.5)
}

log_msg(paste("Classificades:", n_ok, "| Errors:", n_err))

# ── PART 4: Genera corpus_amb_llm.csv (join final) ───────────────────────────
if (file.exists(PROGRESS_CSV)) {
  progress_final <- read.csv(PROGRESS_CSV, stringsAsFactors = FALSE) |>
    mutate(id_master = as.integer(id_master),
           intervencio_ordre = as.integer(intervencio_ordre)) |>
    select(-any_of("row_key"))

  corpus_llm <- corpus |>
    left_join(progress_final |> select(-llm_ts),
              by = c("id_master", "intervencio_ordre"))

  write.csv(corpus_llm, OUT_LLM_CSV, row.names = FALSE, fileEncoding = "UTF-8")

  n_class <- sum(!is.na(corpus_llm$llm_sentiment_cat))
  n_total <- sum(corpus$mencio_cat_ext, na.rm = TRUE)
  log_msg(sprintf("corpus_amb_llm.csv desat: %d classificades / %d elegibles",
                  n_class, n_total))
}

log_msg("=== FI: 5_llm_framing.R ===")
