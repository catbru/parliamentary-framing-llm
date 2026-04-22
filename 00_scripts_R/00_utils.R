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
