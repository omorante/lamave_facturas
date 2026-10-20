library(shiny)
source("parse_invoices.R")

COL <- c(fijo = "#9B2335", calor = "#E08E45", frio = "#3B7EA1", otro = "#8C7F75",
         tinta = "#1A1008", rejilla = "#D9CFC2", banda = "#7A8B5A")
MES_ABR <- c("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")

eur <- function(x, d = 2) paste0(formatC(x, format = "f", digits = d, big.mark = ".", decimal.mark = ","), " €")
pct <- function(x, d = 1) paste0(formatC(x, format = "f", digits = d, decimal.mark = ","), " %")
num <- function(x, d = 4) ifelse(is.na(x), "", formatC(x, format = "f", digits = d, decimal.mark = ","))
mes_label <- function(m) paste(MES_ABR[as.integer(substr(m, 6, 7))], substr(m, 3, 4))

all_months <- function(from, to) {
  format(seq(as.Date(paste0(from, "-01")), as.Date(paste0(to, "-01")), by = "month"), "%Y-%m")
}

section <- function(label, title) div(class = "section-title", h2(label), div(title))

ui <- fluidPage(
  title = "Resumen de facturas de Ecoenergies · LAMAVE",
  lang = "es",
  tags$head(
    tags$meta(name = "viewport", content = "width=device-width, initial-scale=1"),
    tags$link(rel = "stylesheet", href = "lamave.css"),
    tags$script(src = "vendor/pdf.min.js"),
    tags$script(src = "vendor/jszip.min.js"),
    tags$script(src = "pdftext.js")
  ),
  div(class = "wrap",
    div(class = "top",
      a(class = "logo", href = "https://lamave.es", span(class = "la", "LA"), span(class = "mave", "MAVE")),
      a(class = "back noprint", href = "https://lamave.es", "← Volver a lamave.es")
    ),
    div(class = "hero",
      section("Grupo Ecoenergies", "Calculadora del término fijo"),
      h1("Resumen de tus facturas de Ecoenergies"),
      p(class = "lead", "Cuánto pagas de término fijo y cuánto supera los límites del RD 736/2020.")
    ),
    div(class = "box noprint",
      h3("Tus facturas no salen de tu ordenador"),
      p("La herramienta funciona entera en tu navegador. Los PDF se leen aquí mismo y no se envían a ningún servidor: ni a LAMAVE ni a nadie. Al cerrar la página no queda nada guardado.")
    ),
    div(class = "upload",
      tags$label(class = "control-label", `for` = "pdf_files",
                 "Elige tus facturas en PDF (varias a la vez) o un archivo ZIP. También puedes arrastrarlas aquí."),
      div(class = "pick",
        tags$label(class = "btn btn-lamave", `for` = "pdf_files", icon("folder-open"), "Elegir archivos"),
        tags$input(id = "pdf_files", type = "file", multiple = NA, accept = ".pdf,.PDF,.zip,application/pdf,application/zip"),
        span(id = "extract_status", class = "status")
      ),
      p(class = "hint", "Sirve para facturas de calor y frío o solo de calor, en castellano o en catalán, desde 2020. Cuantos más meses subas, más fiable es el resultado.")
    ),
    uiOutput("results"),
    div(class = "foot",
      span("La Asociación Vecinal de La Marina del Prat Vermell"),
      span("Resultado orientativo. No es asesoramiento jurídico."),
      span("LAMAVE")
    )
  )
)

server <- function(input, output, session) {

  # El texto de los PDF llega ya extraído desde el navegador (www/pdftext.js)
  parsed <- reactive({
    x <- input$pdf_texts
    req(x)
    names <- as.character(unlist(x$names))
    validate(need(length(names) > 0, "No se ha encontrado ningún PDF en los archivos elegidos."))
    res <- parse_invoices(as.character(unlist(x$texts)), names, as.character(unlist(x$errors)))
    session$sendCustomMessage("extract_status", sprintf("%d archivo(s) leído(s).", length(names)))
    res
  })

  monthly <- reactive({
    p <- parsed()
    validate(need(nrow(p$items) > 0,
                  "No se ha podido leer ninguna factura. Comprueba que sean facturas de Ecoenergies en el PDF original, no escaneadas."))
    monthly_summary(p$items, p$invoices)
  })

  output$results <- renderUI({
    m <- monthly(); inv <- parsed()$invoices
    span_txt <- paste(mes_label(m$month[1]), "–", mes_label(m$month[nrow(m)]))
    gaps <- setdiff(all_months(m$month[1], m$month[nrow(m)]), m$month)
    multi <- m$month[m$n_facturas > 1]
    n_excl <- sum(!inv$ok)
    pfix <- 100 * sum(m$fijo) / sum(m$bruto)
    over40 <- sum(m$pct_fijo > 40, na.rm = TRUE)

    tagList(
      section("Resultado", "Resumen"),
      div(class = "cards",
        div(class = "card", div(class = "k", "Facturas leídas"), div(class = "v", sum(inv$ok)),
            div(class = "s", sprintf("de %d archivos · %s", nrow(inv), span_txt))),
        div(class = "card", div(class = "k", "Pagado a Ecoenergies"), div(class = "v", eur(sum(m$total_iva), 0)),
            div(class = "s", "IVA incluido")),
        div(class = "card", div(class = "k", "Peso del término fijo"), div(class = "v", pct(pfix, 0)),
            div(class = "s", sprintf("%d de %d meses por encima del 40 %%", over40, nrow(m)))),
        div(class = "card main", div(class = "k", "Fijo por encima del 32,5 %"), div(class = "v", eur(sum(m$exceso_325_iva), 0)),
            div(class = "s", sprintf("IVA incluido · %s sin IVA", eur(sum(m$exceso_325))))),
        div(class = "card", div(class = "k", "Por encima del 40 %"), div(class = "v", eur(sum(m$exceso_40_iva), 0)),
            div(class = "s", "el máximo del RD, IVA incluido"))
      ),
      p(class = "note", tags$b("No incluye lo que pagas a través de la comunidad"),
        " (mantenimiento de la subestación y electricidad del bombeo). Según los datos de un edificio del barrio, son aproximadamente entre 10 y 20 € más al mes por vivienda, según su tamaño. Depende de cada comunidad."),
      if (length(gaps) || length(multi) || n_excl) div(class = "box warn",
        h3("Revisa esto"),
        tags$ul(
          if (n_excl) tags$li(sprintf("%d archivo(s) no se han podido usar. El motivo está en la tabla de archivos, al final.", n_excl)),
          if (length(gaps)) tags$li(paste0("Faltan facturas de: ", paste(mes_label(gaps), collapse = ", "), ".")),
          if (length(multi)) tags$li(paste0("Hay más de una factura para: ", paste(mes_label(multi), collapse = ", "),
                                            ". Se han sumado. Puede ser una rectificación o un cobro duplicado: compruébalo."))
        )
      ),
      div(class = "noprint", style = "margin-top:14px;",
        actionButton("xlsx", "Descargar tabla (Excel)", icon = icon("file-excel"), class = "btn-lamave"),
        actionButton("csv", "CSV", icon = icon("download"), class = "btn-lamave"),
        tags$button(class = "btn btn-lamave", onclick = "window.print()", icon("print"), "Imprimir o guardar en PDF")
      ),
      section("Mes a mes", "Cuánto pagas"),
      plotOutput("p_coste", height = "320px"),
      section("Término fijo", "Peso sobre el total"),
      p("La franja verde es lo que indica el RD 736/2020: un término fijo entre el 25 % y el 40 % del coste. La línea discontinua es el 32,5 %, el punto medio que aplicó la Sentencia 262/2024."),
      plotOutput("p_pct", height = "300px"),
      section("Término fijo", "Pagado de más (acumulado)"),
      plotOutput("p_exceso", height = "280px"),
      section("Término variable", "Precio de la energía"),
      plotOutput("p_precio", height = "280px"),
      section("Detalle", "Tabla por mes"),
      p(style = "font-size:13px;", "Importes sin IVA, salvo el total."),
      div(class = "table-scroll", tableOutput("t_mes")),
      section("Método", "Cómo se calcula"),
      div(class = "box",
        p("Para cada mes se suman el término fijo (R2) y los términos variables de calor, frío y volumen (R1). El peso del fijo es el fijo dividido entre esa suma, sin IVA."),
        p("El RD 736/2020 (art. 6.4) dice que el coste variable debería situarse entre el 60 % y el 75 % del total; es decir, el fijo entre el 25 % y el 40 %. La Sentencia 262/2024 del Juzgado de Primera Instancia nº 13 de Barcelona aplicó a Ecoenergies el punto medio: el 32,5 %."),
        p("El exceso es la diferencia entre el fijo facturado y el que correspondería al 32,5 % (o al 40 %) del coste con el mismo consumo. Se suman todos los meses, también los que quedan por debajo del límite, que restan. Si hubo descuentos, se aplican en proporción."),
        p("Cada factura se comprueba: sus conceptos tienen que sumar la base imponible, y la base más el IVA, el total. Si no cuadra, la factura no se usa y se indica el motivo. Si subes dos veces la misma factura, se cuenta una sola vez."),
        p("Solo se tiene en cuenta lo facturado por Ecoenergies. Lo que se paga a través de la comunidad (mantenimiento de la subestación y electricidad del bombeo) no aparece en estas facturas."),
        p("Privacidad: tus facturas se leen en tu navegador y no se envían a ningún sitio. El informe no incluye tu nombre, tu dirección ni los números de factura. La web no usa cookies ni analítica. Está alojada en GitHub Pages; como cualquier servidor web, GitHub registra la dirección IP de las visitas por seguridad."),
        p(tags$b("Es una estimación orientativa, no un dictamen jurídico."),
          " Ecoenergies sostiene que el RD 736/2020 no se aplica a su servicio, y la sentencia solo obliga en el caso de quien reclamó. Revisa los datos con tus facturas antes de usarlos en una reclamación.")
      ),
      section("Comprobación", "Archivos"),
      div(class = "table-scroll", tableOutput("t_arch"))
    )
  })

  axis_months <- function(x, months) {
    n <- length(months); step <- max(1, ceiling(n / 14))
    at <- seq(1, n, by = step)
    axis(1, at = x[at], labels = mes_label(months[at]), las = 2, cex.axis = .85, tick = FALSE, col.axis = COL[["tinta"]])
  }
  setup <- function() par(mar = c(4.5, 4.8, 1.2, 1), family = "sans", bty = "n", col.lab = COL[["tinta"]], col.axis = COL[["tinta"]])
  grid_y <- function(at) abline(h = at, col = COL[["rejilla"]], lwd = .8)
  y_ticks <- function(top) pretty(c(0, top), n = 5)

  output$p_coste <- renderPlot({
    m <- monthly(); setup()
    mat <- rbind(m$fijo, m$calor, m$frio + m$volumen, m$otro)
    keep <- rowSums(mat) > 0
    cols <- c(COL[["fijo"]], COL[["calor"]], COL[["frio"]], COL[["otro"]])[keep]
    labs <- c("Término fijo", "Calor", "Frío (kWh + m3)", "Otros")[keep]
    top <- max(colSums(mat)) * 1.18; ticks <- y_ticks(top)
    x <- barplot(mat[keep, , drop = FALSE], col = cols, border = NA, ylim = c(0, max(ticks)), axes = FALSE,
                 space = .25, ylab = "€ al mes (sin IVA)")
    grid_y(ticks)
    barplot(mat[keep, , drop = FALSE], col = cols, border = NA, add = TRUE, axes = FALSE, space = .25)
    axis(2, at = ticks, las = 1, cex.axis = .85, lwd = 0); axis_months(x, m$month)
    legend("topleft", legend = labs, fill = cols, border = NA, bty = "n", horiz = TRUE, cex = .9)
  }, bg = "transparent")

  output$p_pct <- renderPlot({
    m <- monthly(); setup()
    x <- barplot(m$pct_fijo, border = NA, ylim = c(0, 100), axes = FALSE, space = .25, col = NA, ylab = "% del coste sin IVA")
    rect(par("usr")[1], 25, par("usr")[2], 40, col = adjustcolor(COL[["banda"]], .28), border = NA)
    grid_y(c(20, 60, 80, 100))
    barplot(m$pct_fijo, col = COL[["fijo"]], border = NA, add = TRUE, axes = FALSE, space = .25)
    abline(h = 32.5, lty = 2, lwd = 1.5, col = COL[["tinta"]])
    axis(2, las = 1, cex.axis = .85, at = c(0, 25, 40, 60, 80, 100), lwd = 0); axis_months(x, m$month)
  }, bg = "transparent")

  output$p_exceso <- renderPlot({
    m <- monthly(); setup()
    a <- cumsum(m$exceso_325_iva); b <- cumsum(m$exceso_40_iva); x <- seq_along(a)
    ticks <- pretty(range(0, a, b) * c(1, 1.12))
    plot(x, a, type = "n", ylim = range(ticks), axes = FALSE, xlab = "", ylab = "€ acumulados (IVA incluido)")
    grid_y(ticks)
    polygon(c(x, rev(x)), c(a, rep(0, length(a))), col = adjustcolor(COL[["fijo"]], .15), border = NA)
    lines(x, a, lwd = 2.5, col = COL[["fijo"]]); lines(x, b, lwd = 2, lty = 2, col = COL[["tinta"]])
    axis(2, at = ticks, las = 1, cex.axis = .85, lwd = 0); axis_months(x, m$month)
    legend("topleft", c("Por encima del 32,5 %", "Por encima del 40 %"), col = c(COL[["fijo"]], COL[["tinta"]]),
           lwd = c(2.5, 2), lty = c(1, 2), bty = "n", cex = .9)
  }, bg = "transparent")

  output$p_precio <- renderPlot({
    m <- monthly()
    y <- c(m$precio_calor, m$precio_frio)
    validate(need(any(!is.na(y)), "Las facturas no indican el precio por kWh."))
    setup(); x <- seq_len(nrow(m))
    ticks <- pretty(c(0, max(y, na.rm = TRUE) * 1.15))
    plot(x, m$precio_calor, type = "n", ylim = range(ticks), axes = FALSE, xlab = "", ylab = "€/kWh (sin IVA)")
    grid_y(ticks)
    lines(x, m$precio_calor, type = "b", pch = 16, cex = .8, col = COL[["calor"]], lwd = 2)
    has_frio <- any(!is.na(m$precio_frio))
    if (has_frio) lines(x, m$precio_frio, type = "b", pch = 16, cex = .8, col = COL[["frio"]], lwd = 2)
    axis(2, at = ticks, las = 1, cex.axis = .85, lwd = 0); axis_months(x, m$month)
    legend("topleft", c("Calor", if (has_frio) "Frío"), col = c(COL[["calor"]], if (has_frio) COL[["frio"]]),
           lwd = 2, pch = 16, bty = "n", horiz = TRUE, cex = .9, text.width = max(strwidth(c("Calor", "Frío"))) * 1.6)
  }, bg = "transparent")

  month_table <- function(m) {
    data.frame(
      "Mes" = mes_label(m$month), "Total con IVA" = eur(m$total_iva), "Fijo" = eur(m$fijo),
      "Calor" = eur(m$calor), "Frío" = eur(m$frio + m$volumen),
      "Descuento" = ifelse(m$descuento != 0, eur(m$descuento), ""),
      "% fijo" = pct(m$pct_fijo), "Exceso 32,5 %" = eur(m$exceso_325),
      "€/kWh calor" = num(m$precio_calor), "€/kWh frío" = num(m$precio_frio), check.names = FALSE)
  }

  output$t_mes <- renderTable({
    m <- monthly()
    tab <- rbind(month_table(m), data.frame(
      "Mes" = "Total", "Total con IVA" = eur(sum(m$total_iva)), "Fijo" = eur(sum(m$fijo)),
      "Calor" = eur(sum(m$calor)), "Frío" = eur(sum(m$frio + m$volumen)),
      "Descuento" = ifelse(sum(m$descuento) != 0, eur(sum(m$descuento)), ""),
      "% fijo" = pct(100 * sum(m$fijo) / sum(m$bruto)), "Exceso 32,5 %" = eur(sum(m$exceso_325)),
      "€/kWh calor" = "", "€/kWh frío" = "", check.names = FALSE))
    if (all(m$descuento == 0)) tab$Descuento <- NULL
    if (all(is.na(m$precio_frio))) tab$`€/kWh frío` <- NULL
    tab
  }, striped = TRUE, spacing = "s", align = "l")

  output$t_arch <- renderTable({
    inv <- parsed()$invoices
    # Sin nombres de archivo ni números de factura: el informe se puede compartir
    # sin datos que permitan identificar a quien lo genera.
    data.frame("Archivo" = paste("nº", seq_len(nrow(inv))),
               "Meses" = vapply(strsplit(inv$months, ", "), function(x) paste(mes_label(x[nzchar(x)]), collapse = ", "), ""),
               "Total" = ifelse(is.na(inv$total), "", eur(inv$total)),
               "Estado" = ifelse(inv$ok, "Leída", paste("No usada:", inv$msg)), check.names = FALSE)
  }, striped = TRUE, spacing = "s", align = "l")

  # downloadHandler no funciona en shinylive: R manda la tabla y el navegador
  # genera el Excel o el CSV (www/pdftext.js, mensaje "download_table").
  send_table <- function(format) {
    m <- monthly()
    out <- list(
      "Mes" = m$month, "Total con IVA (€)" = round(m$total_iva, 2), "Término fijo (€)" = m$fijo,
      "Calor (€)" = m$calor, "Frío kWh (€)" = m$frio, "Frío m3 (€)" = m$volumen, "Otros (€)" = m$otro,
      "Descuento (€)" = m$descuento, "% fijo" = round(m$pct_fijo, 1),
      "Exceso 32,5 % sin IVA (€)" = round(m$exceso_325, 4), "Exceso 40 % sin IVA (€)" = round(m$exceso_40, 4),
      "Precio calor (€/kWh)" = round(m$precio_calor, 6), "Precio frío (€/kWh)" = round(m$precio_frio, 6),
      "Precio frío (€/m3)" = round(m$precio_volumen, 6), "Facturas en el mes" = m$n_facturas)
    session$sendCustomMessage("download_table", list(
      format = format, name = paste0("resumen_facturas_ecoenergies.", format), sheet = "Resumen",
      header = names(out), cols = lapply(unname(out), as.list)))
  }
  observeEvent(input$xlsx, send_table("xlsx"))
  observeEvent(input$csv, send_table("csv"))
}

shinyApp(ui, server)
