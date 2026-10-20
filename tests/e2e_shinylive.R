# Prueba de extremo a extremo de la web exportada (site/) en Chrome sin interfaz.
# Sube las facturas de una carpeta local y guarda una captura en tests/out/.
# Uso: Rscript tests/e2e_shinylive.R <carpeta-con-pdf> [puerto]
args <- commandArgs(TRUE)
pdfs <- if (grepl("\\.zip$", args[1])) normalizePath(args[1]) else normalizePath(list.files(args[1], pattern = "\\.pdf$", ignore.case = TRUE, full.names = TRUE))
port <- if (length(args) > 1) as.integer(args[2]) else 8123L
dir.create("tests/out", showWarnings = FALSE)

srv <- httpuv::runStaticServer("site", port = port, background = TRUE, browse = FALSE)
on.exit(httpuv::stopAllServers(), add = TRUE)

b <- chromote::ChromoteSession$new(width = 1200, height = 900)
b$Page$navigate(sprintf("http://127.0.0.1:%d/", port))
Sys.sleep(1.5)
b$screenshot("tests/out/carga.png", wait_ = TRUE)

js <- function(expr) {
  b$Runtime$evaluate(sprintf("(() => { const f = document.querySelector('iframe'); const d = f ? f.contentDocument : document; const w = f ? f.contentWindow : window; %s })()", expr))$result$value
}
wait_for <- function(expr, timeout = 180) {
  t0 <- Sys.time()
  repeat {
    v <- tryCatch(js(expr), error = function(e) NULL)
    if (isTRUE(v)) return(invisible(TRUE))
    if (difftime(Sys.time(), t0, units = "secs") > timeout) stop("Tiempo agotado esperando: ", expr)
    Sys.sleep(1)
  }
}

t0 <- Sys.time()
wait_for("return !!(d && d.querySelector('#pdf_files') && w.Shiny && w.Shiny.shinyapp && w.Shiny.shinyapp.isConnected());")
cat(sprintf("App cargada en %.0f s\n", difftime(Sys.time(), t0, units = "secs")))

doc <- b$DOM$getDocument(depth = -1, pierce = TRUE)
find_input <- function(node) {
  if (!is.null(node$attributes) && "pdf_files" %in% unlist(node$attributes) && identical(node$nodeName, "INPUT")) return(node$nodeId)
  kids <- c(node$children, if (!is.null(node$contentDocument)) list(node$contentDocument))
  for (k in kids) { r <- find_input(k); if (!is.null(r)) return(r) }
  NULL
}
id <- find_input(doc$root)
b$DOM$setFileInputFiles(files = as.list(pdfs), nodeId = id)

t1 <- Sys.time()
wait_for("return d.querySelectorAll('.card .v').length >= 5 || !!d.querySelector('.shiny-output-error-validation');", timeout = 300)
Sys.sleep(3)
cat(sprintf("Facturas procesadas en %.0f s\n", difftime(Sys.time(), t1, units = "secs")))
cat(js("return Array.from(d.querySelectorAll('.card')).map(c => c.innerText.replace(/\\n/g, ' | ')).join('\\n');"), "\n")
err <- js("const e = d.querySelector('.shiny-output-error-validation'); return e ? e.innerText : '';")
if (nzchar(err)) cat("ERROR:", err, "\n")
dl <- normalizePath("tests/out")
b$Browser$setDownloadBehavior(behavior = "allow", downloadPath = dl)
for (fmt in c("xlsx", "csv")) {
  js(sprintf("d.querySelector('#%s').click(); return true;", fmt))
  Sys.sleep(3)
  f <- file.path(dl, paste0("resumen_facturas_ecoenergies.", fmt))
  cat(sprintf("%s descargado: %s (%s bytes)\n", toupper(fmt), file.exists(f), if (file.exists(f)) file.size(f) else 0))
}
cat("Cabecera tabla de archivos:", js("const t = d.querySelectorAll('table'); return Array.from(t[t.length - 1].querySelectorAll('th')).map(x => x.innerText).join(' | ');"), "\n")
cat("Meses sin precio de frío en la tabla:", js("const t = d.querySelectorAll('table')[0]; const h = Array.from(t.querySelectorAll('th')).map(x => x.innerText); const i = h.indexOf('€/kWh frío'); return i < 0 ? 'sin columna' : Array.from(t.querySelectorAll('tbody tr')).slice(0, -1).filter(r => !r.children[i].innerText.trim()).length;"), "\n")
cat("Archivos no usados:", js("return Array.from(d.querySelectorAll('td')).filter(t => t.innerText.startsWith('No usada')).length;"), "\n")

b$Emulation$setDeviceMetricsOverride(width = 1200, height = 1400, deviceScaleFactor = 1, mobile = FALSE)
Sys.sleep(1)
b$screenshot("tests/out/arriba.png", wait_ = TRUE)
h <- js("return d.body.scrollHeight;")
b$Emulation$setDeviceMetricsOverride(width = 1200, height = as.integer(min(h, 9000)), deviceScaleFactor = 1, mobile = FALSE)
Sys.sleep(2)
b$screenshot("tests/out/captura.png", selector = "html", wait_ = TRUE)
b$close()
