# Prueba el lector con facturas locales (no se copian al repo).
# Uso:
#   Rscript tests/run_parser.R <carpeta>            texto extraído con pdftools
#   Rscript tests/run_parser.R --json <archivo>     texto de tests/extract_node.js (pdf.js)
args <- commandArgs(TRUE)
source(file.path("app", "parse_invoices.R"))
if (identical(args[1], "--json")) {
  x <- jsonlite::fromJSON(args[2])
  r <- parse_invoices(x$text, x$name, x$error)
} else {
  paths <- list.files(args[1], pattern = "\\.pdf$", ignore.case = TRUE, full.names = TRUE)
  texts <- vapply(paths, function(p) tryCatch(paste(pdftools::pdf_text(p), collapse = "\n"), error = function(e) ""), "")
  r <- parse_invoices(unname(texts), basename(paths))
}
inv <- r$invoices
cat(sprintf("%d archivos, %d leídos, %d excluidos\n", nrow(inv), sum(inv$ok), sum(!inv$ok)))
for (i in which(!inv$ok)) cat(sprintf("  -- %-16s %s\n", inv$number[i], inv$msg[i]))
m <- monthly_summary(r$items, inv)
if (!is.null(m)) {
  cat(sprintf("Meses: %d | total con IVA: %.2f | fijo: %.2f | variable: %.2f | descuentos: %.2f | %% fijo: %.1f\n",
              nrow(m), sum(m$total_iva), sum(m$fijo), sum(m$variable), sum(m$descuento), 100 * sum(m$fijo) / sum(m$bruto)))
  cat(sprintf("Exceso 32,5%%: %.2f sin IVA, %.2f con IVA | Exceso 40%%: %.2f sin IVA, %.2f con IVA\n",
              sum(m$exceso_325), sum(m$exceso_325_iva), sum(m$exceso_40), sum(m$exceso_40_iva)))
  if ("--detail" %in% args) print(format(m[, c("month", "fijo", "calor", "frio", "volumen", "descuento", "n_facturas", "pct_fijo", "exceso_325")], digits = 3), row.names = FALSE)
}
