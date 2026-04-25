# 00_scripts_R/1_scraper_cataleg.R
#
# Scraping del catàleg de vídeos del Parlament d'Andalusia i resolució ID_MASTER.
#
# Descobertes de la inspecció HTML (Step 1):
#  - 15 sessions per pàgina, en elements <div class="list-result-item">
#  - Títol: a.h2 > span[title]
#  - URL del vídeo: a.h2[href]
#  - id_master: extret visitant cada pàgina /watch?id=... i llegint el camp
#    resources_url del bloc JSPLAYLIST: subject_id=<N>.
#    NOTA: El subject_id del poster (img[src*="/posters/"]) és l'ID de la IMATGE
#    del poster, NO el de la sessió de vídeo → NO es pot usar per a id_master.
#  - Paginació: /search?page=N&gbody_id=3378&legs_id=<ID>&search=&view_type=list
#
# legs_id descoberts inspeccionant el <select> de la pàgina de cerca:
#   10a Legislatura → legs_id = 13
#   11a Legislatura → legs_id = 14
#   12a Legislatura → legs_id = 3377
#
library(rvest)
library(httr2)
library(jsonlite)
library(stringr)
library(dplyr)

source("00_scripts_R/00_utils.R")

BASE_URL    <- "https://videoteca.parlamentodeandalucia.es"
SEARCH_PATH <- "/search?page=%d&gbody_id=3378&legs_id=%d&search=&view_type=list"
OUT_MASTER  <- "01_dades_crues/cataleg/cataleg_master.json"
DEMO_MODE   <- FALSE  # TRUE = processa només les 2 primeres pàgines

# Mapa de legs_id → número de legislatura en àrabs
LEGS_MAP <- c("13" = "10", "14" = "11", "3377" = "12")

# ── Helpers ───────────────────────────────────────────────────────────────────

# Visita la pàgina /watch?id=... i extreu el subject_id real del bloc JSPLAYLIST.
# El camp resources_url conté subject_id=<N> que és el ID_MASTER correcte.
# (El subject_id del poster és l'ID de la imatge, no de la sessió de vídeo.)
fetch_master_id <- function(href) {
  tryCatch({
    resp <- safe_get(href)
    if (is.null(resp)) return(NA_integer_)
    body <- resp_body_string(resp)
    m <- str_match(body, "resources_url='[^']*subject_id=([0-9]+)")
    if (is.na(m[1, 2])) return(NA_integer_)
    as.integer(m[1, 2])
  }, error = function(e) NA_integer_)
}

# Extreu url_id de la URL completa del vídeo
extract_url_id <- function(href) {
  str_match(href, "[?&]id=([A-Za-z0-9+/=_-]+)")[, 2]
}

# Extreu data ISO a partir del text del div de data
parse_fecha <- function(txt) {
  txt_clean <- str_squish(iconv(txt, "latin1", "UTF-8", sub = ""))
  m <- str_match(txt_clean, "(\\d{1,2}) de (\\w+) de (\\d{4})")
  if (is.na(m[1, 1])) return(NA_character_)
  mesos <- c("enero" = 1, "febrero" = 2, "marzo" = 3, "abril" = 4,
             "mayo" = 5, "junio" = 6, "julio" = 7, "agosto" = 8,
             "septiembre" = 9, "octubre" = 10, "noviembre" = 11, "diciembre" = 12)
  mes_num <- mesos[str_to_lower(m[1, 3])]
  if (is.na(mes_num)) return(NA_character_)
  sprintf("%s-%02d-%02d", m[1, 4], mes_num, as.integer(m[1, 2]))
}

# Extreu el codi de legislatura del camp "Código 1:" i retorna número aràbic
ROMAN_TO_ARABIC <- c("X" = "10", "XI" = "11", "XII" = "12")

parse_legislatura <- function(txt) {
  m <- str_match(txt, "PL-(X{0,3}(?:IX|IV|V?I{0,3})) LEGISLATURA")
  if (is.na(m[1, 1])) return(NA_character_)
  roman <- m[1, 2]
  ROMAN_TO_ARABIC[roman] %||% roman
}

# ── Scraping del llistat ──────────────────────────────────────────────────────

get_page_videos <- function(page_num, legs_id = 3377) {
  url  <- paste0(BASE_URL, sprintf(SEARCH_PATH, page_num, legs_id))
  log_msg(paste("Scraping pàgina", page_num, "legs_id", legs_id))
  resp <- safe_get(url)
  if (is.null(resp)) return(NULL)

  html  <- read_html(resp_body_string(resp))
  items <- html |> html_elements("div.list-result-item")
  if (length(items) == 0) {
    log_msg(paste("  Pàgina", page_num, "buida"))
    return(NULL)
  }

  rows <- lapply(items, function(item) {
    # Títol i href de l'enllaç principal
    title_a <- item |> html_element("a.h2")
    if (is.null(title_a)) return(NULL)

    href  <- title_a |> html_attr("href")
    titol <- title_a |> html_element("span") |> html_attr("title")
    if (is.na(href) || is.na(titol)) return(NULL)

    # Elimina el port :443 de l'href
    href <- str_replace(href, ":443/", "/")

    url_id <- extract_url_id(href)

    # id_master des del JSPLAYLIST de la pàgina /watch (l'únic mètode fiable)
    id_master <- fetch_master_id(href)
    polite_delay(0.5)

    # Data de la sessió (text secundari)
    data_div  <- item |> html_element("div[style*='margin-top:10px']")
    data_text <- if (!is.null(data_div)) str_trim(html_text(data_div, trim = TRUE)) else NA_character_

    fecha      <- parse_fecha(data_text)
    legislatura <- parse_legislatura(data_text)

    tibble(
      url_id      = url_id,
      titol       = titol,
      id_master   = id_master,
      fecha       = fecha,
      legislatura = legislatura,
      href        = href
    )
  })

  bind_rows(Filter(Negate(is.null), rows)) |>
    filter(!is.na(url_id), nchar(url_id) > 5, !is.na(titol), nchar(titol) > 2)
}

scrape_full_catalog <- function(legs_id = 3377, max_pages = Inf) {
  all_videos <- list()
  page <- 1
  repeat {
    videos <- get_page_videos(page, legs_id = legs_id)
    if (is.null(videos) || nrow(videos) == 0) {
      log_msg(paste("Pàgina", page, "buida — fi de paginació"))
      break
    }
    all_videos[[page]] <- videos
    log_msg(paste("  →", nrow(videos), "vídeos extrets"))
    if (page >= max_pages) break
    page <- page + 1
    polite_delay()
  }
  bind_rows(all_videos)
}

# ── EXECUCIÓ PRINCIPAL ────────────────────────────────────────────────────────

max_p <- if (DEMO_MODE) 2 else Inf

if (!file_done(OUT_MASTER)) {
  log_msg("=== Scraping del catàleg complet (legislatures 10, 11, 12) ===")

  # Itera per cada legislatura i combina resultats
  all_legs <- lapply(names(LEGS_MAP), function(lid) {
    leg_num <- LEGS_MAP[lid]
    log_msg(paste("--- Legislatura", leg_num, "(legs_id =", lid, ") ---"))
    df <- scrape_full_catalog(legs_id = as.integer(lid), max_pages = max_p)
    log_msg(paste("  Legislatura", leg_num, "→", nrow(df), "sessions"))
    df
  })

  catalog <- bind_rows(all_legs) |>
    distinct(url_id, .keep_all = TRUE)

  log_msg(paste("Total sessions (deduplicat):", nrow(catalog)))
  n_resolts <- sum(!is.na(catalog$id_master))
  log_msg(paste("IDs resolts:", n_resolts, "/", nrow(catalog)))
  write_json(catalog, OUT_MASTER, auto_unbox = TRUE, pretty = TRUE)
  log_msg(paste("Desat:", OUT_MASTER))
} else {
  log_msg(paste("Catàleg master ja existeix:", OUT_MASTER))
}
