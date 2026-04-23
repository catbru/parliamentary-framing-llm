# 00_scripts_R/2_scraping_diputats.R
# Scraping de diputats del Parlament d'Andalusia per a les legislatures 10, 11 i 12.
# Extreu: slug, nom, grup_parlamentari, partit, legislatura, leg_id.
# Output: 01_dades_crues/diputats/diputats.json
#
# NOTA sobre `partit`:
# La web de la Videoteca del Parlament d'Andalusia no exposa un camp "Partido Político"
# separat del "Grupo político". Tots els elements HTML i l'API JSON només retornen el
# nom del grup parlamentari (e.g. "G.P. Popular de Andalucía", "G.P. Socialista").
# Per tant, `partit` es deriva de `grup_parlamentari` amb una taula de correspondència
# basada en el coneixement públic dels grups parlamentaris i els seus partits matriu.
# En cas que no es trobi correspondència, `partit` pren el valor de `grup_parlamentari`.

library(rvest)
library(httr2)
library(jsonlite)
library(stringr)
library(dplyr)
library(purrr)

source("00_scripts_R/00_utils.R")

BASE_URL <- "https://videoteca.parlamentodeandalucia.es"
OUT_FILE <- "01_dades_crues/diputats/diputats.json"

# Taula de correspondència grup parlamentari -> partit polític.
# La Videoteca no exposa un camp "Partido Político" independent; el deduïm del grup.
# Cobreix tots els grups presents en les legislatures 10, 11 i 12.
GRUP_A_PARTIT <- c(
  "G.P. Socialista"                                            = "PSOE",
  "G.P. Popular Andaluz"                                       = "PP",
  "G.P. Popular de Andalucía"                                  = "PP",
  "G.P. Ciudadanos"                                            = "Cs",
  "G.P. Vox en Andalucía"                                      = "Vox",
  "G.P. Podemos Andalucía"                                     = "Podemos",
  "G.P. Unidas Podemos por Andalucía"                          = "Unidas Podemos",
  "G.P. Por Andalucía"                                         = "Por Andalucía",
  "G.P. Adelante Andalucía"                                    = "Adelante Andalucía",
  "G.P. Mixto-Adelante Andalucía"                              = "Adelante Andalucía",
  "G.P. Izquierda Unida Los Verdes-Convocatoria por Andalucía" = "IU",
  "G.P. Izquierda Unida Convocatoria por Andalucía"            = "IU",
  "G.P. Coalición Andalucista-Poder Andaluz"                   = "Coalición Andalucista",
  "G.P. Mixto"                                                 = "Mixto"
)

# Funció auxiliar: retorna el partit a partir del grup parlamentari
grup_a_partit <- function(grup) {
  if (is.na(grup) || nchar(grup) == 0) return(NA_character_)
  partit <- GRUP_A_PARTIT[grup]
  if (is.na(partit)) grup else unname(partit)
}

# leg_id values descoberts a /people (dropdown "Legislatura/Mandato"):
#   12a Legislatura -> 3377
#   11a Legislatura -> 14
#   10a Legislatura -> 13
LEG_IDS <- c(
  "10" = 13L,
  "11" = 14L,
  "12" = 3377L
)

# Retorna el nombre de l'última pàgina per a un leg_id donat
get_last_page <- function(leg_id) {
  url  <- paste0(BASE_URL, "/people?leg_id=", leg_id, "&gbody_id=&politic_id=")
  resp <- safe_get(url)
  if (is.null(resp)) return(1L)

  html    <- read_html(resp_body_string(resp))
  # L'últim element de paginació amb href conté el número de la darrera pàgina
  last_href <- html |>
    html_element(".pagination li:last-child a") |>
    html_attr("href")

  if (is.na(last_href)) return(1L)
  as.integer(str_match(last_href, "page=(\\d+)")[, 2]) %||% 1L
}

# Extreu diputats d'una pàgina de llistat
scrape_page <- function(leg_id, leg_num, page) {
  url  <- paste0(BASE_URL, "/people?page=", page,
                 "&leg_id=", leg_id, "&gbody_id=&politic_id=&sort=1")
  log_msg(paste("  Pàgina", page, "- leg_id=", leg_id, "(legislatura", leg_num, ")"))
  resp <- safe_get(url)
  if (is.null(resp)) return(tibble())

  html     <- read_html(resp_body_string(resp))
  wrappers <- html |> html_elements(".person_list_wrapper")
  if (length(wrappers) == 0) return(tibble())

  map_dfr(wrappers, function(w) {
    # Slug i nom des del link principal
    link <- w |> html_element("a[href*='/people/']")
    if (is.null(link)) return(tibble())
    href <- html_attr(link, "href")
    slug <- str_match(href, "/people/([^/?#]+)$")[, 2]
    nom  <- w |> html_element(".person_name") |> html_text(trim = TRUE) |> str_squish()

    # Grup parlamentari: primer mirem el span[title] dins .person_politics
    grp_span <- w |> html_element(".person_politics span[title]")
    grup <- if (!is.null(grp_span) && length(grp_span) > 0) {
      html_attr(grp_span, "title")
    } else NA_character_

    # Fallback: img alt dins content_person_politic_img
    if (is.na(grup)) {
      img_el <- w |> html_element(".content_person_politic_img img")
      if (!is.null(img_el) && length(img_el) > 0) {
        grup <- html_attr(img_el, "alt")
      }
    }

    tibble(
      slug              = slug,
      nom               = nom,
      legislatura       = as.character(leg_num),
      leg_id            = as.integer(leg_id),
      grup_parlamentari = grup,
      partit            = grup_a_partit(grup)
    )
  })
}

# Per als diputats sense grup en el llistat, consulta la pàgina de perfil.
# Retorna una llista amb `grup_parlamentari` i `partit`.
enrich_deputy <- function(slug) {
  url  <- paste0(BASE_URL, "/people/", slug)
  resp <- safe_get(url)
  if (is.null(resp)) return(list(grup_parlamentari = NA_character_, partit = NA_character_))

  html <- read_html(resp_body_string(resp))

  # Opció 1: primer element "Grupo político" dins el modal (historial complet).
  # Nota: xml2/rvest no suporta :first-child, per això usem html_elements + [[1]]
  grup <- tryCatch({
    grups <- html |> html_elements(".groupsContainer .group")
    grup_node <- NULL
    for (g in grups) {
      title_el <- g |> html_element("h3.group-title")
      if (!is.null(title_el) && length(title_el) > 0) {
        title_text <- html_text(title_el, trim = TRUE)
        if (grepl("Grupo político", title_text, fixed = TRUE)) {
          grup_node <- g
          break
        }
      }
    }
    if (!is.null(grup_node)) {
      grup_node |>
        html_element(".group-item div") |>
        html_text(trim = TRUE) |>
        str_squish()
    } else NA_character_
  }, error = function(e) NA_character_)

  # Opció 2: .person_politics .date de la fitxa principal (grup actual)
  if (is.na(grup) || nchar(grup) == 0) {
    grup <- tryCatch({
      text <- html |>
        html_element(".person_politics .date") |>
        html_text(trim = TRUE) |>
        str_squish()
      if (!is.na(text) && !grepl("sin grupo", text, ignore.case = TRUE)) {
        str_remove(text, "^-\\s*") |> str_remove("\\(.*\\)$") |> str_squish()
      } else NA_character_
    }, error = function(e) NA_character_)
  }

  list(
    grup_parlamentari = grup,
    partit            = grup_a_partit(grup)
  )
}

# ─── Main ─────────────────────────────────────────────────────────────────────

if (!file_done(OUT_FILE)) {
  log_msg("=== Scraping diputats (legislatures 10, 11, 12) ===")

  all_deputies <- imap_dfr(LEG_IDS, function(leg_id, leg_num) {
    last_page <- get_last_page(leg_id)
    log_msg(paste("Legislatura", leg_num, "(leg_id=", leg_id, "):", last_page, "pàgines"))

    map_dfr(seq_len(last_page), function(p) {
      result <- scrape_page(leg_id, leg_num, p)
      if (p < last_page) polite_delay()
      result
    })
  })

  # Filtre de sanitat: eliminar files buides o sense slug vàlid
  all_deputies <- all_deputies |>
    filter(!is.na(slug), nchar(nom) > 2, !str_starts(slug, "http"))

  # Eliminar duplicats (mateix diputat pot aparèixer en múltiples legislatures)
  all_deputies <- distinct(all_deputies, slug, legislatura, .keep_all = TRUE)

  log_msg(paste("Total entrades (sense duplicats):", nrow(all_deputies)))

  # Enriquir els diputats sense grup parlamentari al llistat
  sense_grup <- which(is.na(all_deputies$grup_parlamentari))
  if (length(sense_grup) > 0) {
    log_msg(paste("Enriquint", length(sense_grup), "diputats sense grup des del llistat..."))
    for (i in sense_grup) {
      log_msg(paste("  Enriquint", i, "/", nrow(all_deputies), ":", all_deputies$slug[i]))
      enriched <- tryCatch(
        enrich_deputy(all_deputies$slug[i]),
        error = function(e) list(grup_parlamentari = NA_character_, partit = NA_character_)
      )
      all_deputies$grup_parlamentari[i] <- enriched$grup_parlamentari
      all_deputies$partit[i]            <- enriched$partit
      polite_delay()
    }
  }

  # Escriure output
  dir.create(dirname(OUT_FILE), showWarnings = FALSE, recursive = TRUE)
  write_json(all_deputies, OUT_FILE, auto_unbox = TRUE, pretty = TRUE)
  log_msg(paste("Desat:", OUT_FILE))
  log_msg(paste("Total diputats:", nrow(all_deputies)))
  log_msg(paste("Legislatures:", paste(sort(unique(all_deputies$legislatura)), collapse = ", ")))

} else {
  log_msg(paste("Diputats ja existeix:", OUT_FILE))
}
