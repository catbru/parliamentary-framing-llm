# 00_scripts_R/1_scraper_cataleg.R
#
# Scraping del catàleg de vídeos del Parlament d'Andalusia i resolució ID_MASTER.
#
# Descobertes de la inspecció HTML (Step 1):
#  - 15 sessions per pàgina, en elements <div class="list-result-item">
#  - Títol: a.h2 > span[title]
#  - URL del vídeo: a.h2[href]
#  - id_master: extret directament de la URL del poster (img[src*="/posters/"]),
#    que conté un token base64 amb {"subject_klass":"item","subject_id":<N>}
#    → NO cal visitar cada pàgina /watch?id=... per separat.
#  - Paginació: /search?page=N&gbody_id=3378&legs_id=3377&search=&view_type=list
#    (11 pàgines en total a data d'inspecció)
#
library(rvest)
library(httr2)
library(jsonlite)
library(stringr)
library(dplyr)

source("00_scripts_R/00_utils.R")

BASE_URL   <- "https://videoteca.parlamentodeandalucia.es"
SEARCH_PATH <- "/search?page=%d&gbody_id=3378&legs_id=3377&search=&view_type=list"
OUT_VIDEOS <- "01_dades_crues/cataleg/cataleg_videos.json"
OUT_MASTER <- "01_dades_crues/cataleg/cataleg_master.json"
DEMO_MODE  <- FALSE  # TRUE = processa només les 2 primeres pàgines

# ── Helpers ───────────────────────────────────────────────────────────────────

# Descodifica el token base64 del poster i retorna el subject_id (int)
decode_poster_id <- function(src) {
  tryCatch({
    b64 <- str_match(src, "/posters/([A-Za-z0-9+/=]+)")[, 2]
    if (is.na(b64)) return(NA_integer_)
    json_str <- rawToChar(jsonlite::base64_dec(b64))
    parsed   <- fromJSON(json_str)
    as.integer(parsed$subject_id)
  }, error = function(e) NA_integer_)
}

# Extreu url_id de la URL completa del vídeo
extract_url_id <- function(href) {
  str_match(href, "[?&]id=([A-Za-z0-9+/=_-]+)")[, 2]
}

# ── PART 1: Scraping del llistat ──────────────────────────────────────────────

get_page_videos <- function(page_num) {
  url  <- paste0(BASE_URL, sprintf(SEARCH_PATH, page_num))
  log_msg(paste("Scraping pàgina", page_num))
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

    url_id <- extract_url_id(href)

    # id_master des de la imatge del poster (element germà en el pare)
    parent     <- xml2::xml_parent(item)
    poster_img <- parent |> html_element("img[src*='/posters/']")
    id_master  <- if (!is.null(poster_img) && !is.na(poster_img)) {
      decode_poster_id(poster_img |> html_attr("src"))
    } else {
      NA_integer_
    }

    # Data de la sessió (text secundari)
    data_div <- item |> html_element("div[style*='margin-top:10px']")
    data_text <- if (!is.null(data_div)) str_trim(html_text(data_div, trim = TRUE)) else NA_character_

    tibble(
      url_id    = url_id,
      titol     = titol,
      href      = href,
      id_master = id_master,
      data_text = data_text
    )
  })

  bind_rows(Filter(Negate(is.null), rows)) |>
    filter(!is.na(url_id), nchar(url_id) > 5, !is.na(titol), nchar(titol) > 2)
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
    log_msg(paste("  →", nrow(videos), "vídeos extrets"))
    if (page >= max_pages) break
    page <- page + 1
    polite_delay()
  }
  bind_rows(all_videos)
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

# ── PART 2: Consolidació ID_MASTER ───────────────────────────────────────────
# En aquest script, l'id_master s'extreu directament durant el scraping.
# Part 2 consolida i verifica (si calgués visitar pàgines individuals, ho faria aquí).

if (!file_done(OUT_MASTER)) {
  log_msg("=== PART 2: Resolució ID_MASTER ===")

  # Si manquen id_master (cas excepcional), intentar via pàgina individual
  if (!"id_master" %in% names(catalog)) catalog$id_master <- NA_integer_

  missing_idx <- which(is.na(catalog$id_master))
  if (length(missing_idx) > 0) {
    log_msg(paste("Resolent", length(missing_idx), "id_master faltants via pàgina individual..."))
    for (i in missing_idx) {
      url  <- paste0(BASE_URL, "/watch?id=", catalog$url_id[i])
      log_msg(paste("  GET", url))
      resp <- safe_get(url)
      if (!is.null(resp)) {
        html_text_raw <- resp_body_string(resp)
        # Cerca subject_id=N en el text cru de la pàgina
        m <- str_match(html_text_raw, "subject_id[\"']?\\s*:\\s*(\\d+)")
        if (!is.na(m[1, 1])) {
          catalog$id_master[i] <- as.integer(m[1, 2])
        } else {
          log_msg(paste("    No subject_id per", catalog$url_id[i]))
        }
      }
      polite_delay()
    }
  } else {
    log_msg("Tots els id_master ja resolts des del llistat")
  }

  n_resolts <- sum(!is.na(catalog$id_master))
  log_msg(paste("IDs resolts:", n_resolts, "/", nrow(catalog)))
  write_json(catalog, OUT_MASTER, auto_unbox = TRUE, pretty = TRUE)
  log_msg(paste("Desat:", OUT_MASTER))
} else {
  log_msg(paste("Catàleg master ja existeix:", OUT_MASTER))
}
