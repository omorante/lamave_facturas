# Exporta la app a site/ con la pantalla de carga de LAMAVE.
# Uso: Rscript build.R
read <- function(f) paste(readLines(file.path("build", f), encoding = "UTF-8", warn = FALSE), collapse = "\n")

unlink("site", recursive = TRUE)
shinylive::export("app", "site", template_params = list(
  title = "Calculadora del término fijo de Ecoenergies · LAMAVE",
  include_in_head = read("head.html"),
  include_before_body = read("before_body.html"),
  include_after_body = read("after_body.html")
))

# Recursos de la pantalla de carga (la app tiene los suyos dentro de app.json)
file.copy("build/favicon.png", "site/favicon.png", overwrite = TRUE)
dir.create("site/fonts", showWarnings = FALSE)
file.copy(list.files("app/www/fonts", full.names = TRUE), "site/fonts", overwrite = TRUE)
