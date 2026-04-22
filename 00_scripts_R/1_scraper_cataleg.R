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

# Extreu el codi de legislatura del camp "Código 1:"
parse_legislatura <- function(txt) {
  m <- str_match(txt, "PL-(X{0,3}(?:IX|IV|V?I{0,3})) LEGISLATURA")
  if (is.na(m[1, 1])) return(NA_character_)
  m[1, 2]
}

# ── Scraping del llistat ──────────────────────────────────────────────────────

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

    # Elimina el port :443 de l'href
    href <- str_replace(href, ":443/", "/")

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

if (!file_done(OUT_MASTER)) {
  log_msg("=== Scraping del catàleg complet ===")
  catalog <- scrape_full_catalog(max_pages = max_p)
  log_msg(paste("Total vídeos:", nrow(catalog)))
  n_resolts <- sum(!is.na(catalog$id_master))
  log_msg(paste("IDs resolts:", n_resolts, "/", nrow(catalog)))
  write_json(catalog, OUT_MASTER, auto_unbox = TRUE, pretty = TRUE)
  log_msg(paste("Desat:", OUT_MASTER))
} else {
  log_msg(paste("Catàleg master ja existeix:", OUT_MASTER))
}
