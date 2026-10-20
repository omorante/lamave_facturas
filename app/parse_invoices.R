# Lectura de facturas de Ecoenergies (PDF) y resumen mensual.
#
# Formatos reconocidos:
#   - "nuevo" (desde abril de 2024, en castellano o en catalán): cada concepto
#     termina en "= 12.34 €" y hay "Base imponible"/"Base imposable".
#   - "antiguo" (hasta marzo de 2024): tabla CONCEPTO/CANTIDAD/IMPORTE con coma
#     decimal; a veces varios meses en una factura y el importe fuera de su
#     línea. Los importes se recalculan (kWh x precio, kW x precio) y se
#     comprueban contra el TOTAL BRUTO.
# Toda factura cuyos conceptos no sumen la base imponible se excluye y se avisa.

MESES <- c(
  enero = 1, febrero = 2, marzo = 3, abril = 4, mayo = 5, junio = 6, julio = 7,
  agosto = 8, septiembre = 9, setiembre = 9, octubre = 10, noviembre = 11,
  diciembre = 12, gener = 1, febrer = 2, "març" = 3, maig = 5, juny = 6,
  juliol = 7, agost = 8, setembre = 9, novembre = 11, desembre = 12
)
MES_RE <- paste0("\\b(", paste(unique(names(MESES)), collapse = "|"), ")\\b(?:\\s+(?:de\\s+)?(\\d{4}))?")

NUM <- "-?\\d+(?:[.,]\\d+)*"

# "1.234,56", "1234,56" y "1234.56" -> 1234.56
to_num <- function(x) {
  x <- gsub("[^0-9,.-]", "", x)
  both <- grepl(",", x) & grepl(".", x, fixed = TRUE)
  x[both] <- gsub(".", "", x[both], fixed = TRUE)
  suppressWarnings(as.numeric(sub(",", ".", x, fixed = TRUE)))
}

first_match <- function(pattern, text, group = 1) {
  m <- regmatches(text, regexec(pattern, text, perl = TRUE))[[1]]
  if (length(m) > group) m[group + 1] else NA_character_
}

find_month <- function(line) {
  m <- regmatches(line, regexec(MES_RE, line, perl = TRUE, ignore.case = TRUE))[[1]]
  if (!length(m)) return(NULL)
  list(m = unname(MESES[tolower(m[2])]), y = if (nzchar(m[3])) as.integer(m[3]) else NA_integer_)
}

empty_items <- function() {
  data.frame(month = character(), kind = character(), amount = numeric(),
             qty = numeric(), price = numeric(), stringsAsFactors = FALSE)
}

item <- function(month, kind, amount, qty = NA_real_, price = NA_real_) {
  data.frame(month = month, kind = kind, amount = amount, qty = qty,
             price = price, stringsAsFactors = FALSE)
}

classify <- function(line) {
  low <- tolower(line)
  if (grepl("descuento|descompte|bonificaci", low)) return("descuento")
  if (grepl("fijo|fix|potencia|\\br2\\b", low)) return("fijo")
  if (grepl("m3|volum|r1'", low)) return("volumen")
  if (grepl("fr[ií]o|fred", low)) return("frio")
  if (grepl("calor", low)) return("calor")
  "otro"
}

qty_price <- function(line) {
  m <- regmatches(line, regexec(paste0("(", NUM, ")\\s*(kWh|m3|kW)(?:/mes)?\\s*x\\s*(", NUM, ")\\s*€?\\s*/\\s*(kWh|m3|kW)"),
                                line, perl = TRUE))[[1]]
  if (!length(m)) return(NULL)
  list(qty = to_num(m[2]), unit = m[3], price = to_num(m[4]))
}

parse_new <- function(lines, text) {
  start <- first_match("(\\d{4}-\\d{2})-\\d{2}\\s*-\\s*\\d{4}-\\d{2}-\\d{2}", text)
  if (is.na(start)) {
    d <- first_match("del\\s+\\d{2}/(\\d{2}/\\d{4})\\s+al", text)
    if (!is.na(d)) start <- paste0(substr(d, 4, 7), "-", substr(d, 1, 2))
  }
  items <- empty_items()
  for (ln in lines) {
    amt <- first_match(paste0("=\\s*(", NUM, ")\\s*€"), ln)
    if (is.na(amt)) next
    qp <- qty_price(ln)
    items <- rbind(items, item(start, classify(ln), to_num(amt),
                               if (is.null(qp)) NA_real_ else qp$qty,
                               if (is.null(qp)) NA_real_ else qp$price))
  }
  # Factura de solo calor sin etiqueta en la línea de consumo
  unl <- items$kind == "otro" & !is.na(items$qty)
  if (sum(unl) == 1 && !any(items$kind == "calor")) items$kind[unl] <- "calor"
  iva <- regmatches(text, regexec(paste0("IVA\\s*(\\d+(?:[.,]\\d+)?)\\s*%\\s+(", NUM, ")"), text, perl = TRUE))[[1]]
  list(
    format = "nuevo", items = items,
    base = to_num(first_match(paste0("Base\\s+impo(?:nible|sable)\\s+(", NUM, ")"), text)),
    iva_rate = if (length(iva)) to_num(iva[2]) else NA_real_,
    total = to_num(first_match(paste0("(?m)^\\s*Total\\s+(", NUM, ")\\s*€?\\s*$"), text))
  )
}

parse_old <- function(lines, text, number) {
  issue <- first_match(paste0(number, "\\s+(\\d{2}/\\d{2}/\\d{2,4})"), text)
  issue_m <- if (is.na(issue)) NA_integer_ else as.integer(substr(issue, 4, 5))
  issue_y <- if (is.na(issue)) NA_integer_ else {
    y <- as.integer(sub(".*/", "", issue)); if (y < 100) y + 2000L else y
  }
  period <- first_match("del\\s+\\d{2}/(\\d{2}/\\d{4})\\s+al", text)
  period_m <- if (is.na(period)) NULL else list(m = as.integer(substr(period, 1, 2)), y = as.integer(substr(period, 4, 7)))

  raw <- list()
  add <- function(kind, mo, amount, qty = NA_real_, price = NA_real_) {
    raw[[length(raw) + 1]] <<- list(kind = kind, m = if (is.null(mo)) NA_integer_ else mo$m,
                                    y = if (is.null(mo)) NA_integer_ else mo$y,
                                    amount = amount, qty = qty, price = price)
  }
  cur_kind <- NA_character_; cur_month <- period_m; pending_amount <- FALSE
  tail3 <- paste0("\\s(", NUM, ")\\s+(", NUM, ")\\s+(", NUM, ")\\s*$")
  for (ln in lines) {
    low <- tolower(ln)
    qp <- qty_price(ln)
    is_concept <- grepl("\\br[12]\\b|r1'|término|termino|potencia|consumo|descuento|rectificaci", low) &&
      is.null(qp) && !grepl("lectura|tarifas aplicadas", low)
    if (is_concept) {
      cur_kind <- classify(ln)
      mo <- find_month(ln)
      if (!is.null(mo)) cur_month <- mo
      tl <- regmatches(ln, regexec(tail3, ln, perl = TRUE))[[1]]
      rect <- grepl("rectificaci", low)
      if (length(tl) && (cur_kind %in% c("fijo", "descuento") || rect)) {
        add(cur_kind, cur_month, to_num(tl[4]))
        pending_amount <- FALSE
      } else {
        pending_amount <- rect
      }
      next
    }
    if (!is.null(qp) && !is.na(cur_kind)) {
      kind <- switch(qp$unit, kW = "fijo", m3 = "volumen", if (cur_kind %in% c("frio", "calor")) cur_kind else "calor")
      add(kind, cur_month, round(qp$qty * qp$price + 1e-9, 2), qp$qty, qp$price)
      next
    }
    if (pending_amount) {
      tl <- regmatches(ln, regexec(paste0("^\\s*\\d+\\s+(", NUM, ")\\s+(", NUM, ")\\s*$"), ln, perl = TRUE))[[1]]
      if (length(tl)) { add(cur_kind, cur_month, to_num(tl[3])); pending_amount <- FALSE }
    }
  }

  items <- empty_items()
  if (length(raw)) {
    known <- do.call(rbind, lapply(raw, function(r) data.frame(m = r$m, y = r$y)))
    for (r in raw) {
      m <- r$m; y <- r$y
      if (is.na(m) && !is.null(period_m)) { m <- period_m$m; y <- period_m$y }
      if (!is.na(m) && is.na(y)) {
        same <- known$y[known$m == m & !is.na(known$y)]
        y <- if (length(same)) same[1] else if (!is.na(issue_y)) issue_y - as.integer(m > issue_m) else NA_integer_
      }
      month <- if (is.na(m) || is.na(y)) NA_character_ else sprintf("%04d-%02d", y, m)
      items <- rbind(items, item(month, r$kind, r$amount, r$qty, r$price))
    }
  }
  list(
    format = "antiguo", items = items,
    base = to_num(first_match(paste0("TOTAL BRUTO\\s+(", NUM, ")"), text)),
    iva_rate = to_num(first_match("IVA\\s+SRV\\s+(\\d+)", text)),
    total = to_num(first_match(paste0("TOTAL A PAGAR\\s+(", NUM, ")"), text))
  )
}

bad_invoice <- function(file, msg) list(
  invoice = data.frame(file = file, number = NA_character_, type = NA_character_,
                       format = NA_character_, months = NA_character_, base = NA_real_,
                       iva_rate = NA_real_, total = NA_real_, ok = FALSE, msg = msg,
                       stringsAsFactors = FALSE),
  items = empty_items())

# Devuelve list(invoice = data.frame de 1 fila, items = data.frame)
parse_invoice_text <- function(text, file = NA_character_) {
  bad <- function(msg) bad_invoice(file, msg)
  if (!nzchar(trimws(text))) return(bad("El PDF no contiene texto (puede ser una imagen escaneada)."))
  number <- first_match("\\b([A-Z]{3}\\d{12})\\b", text)
  if (!grepl("ecoenergies|R1|R2", text, ignore.case = TRUE)) return(bad("No parece una factura de Ecoenergies."))
  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  p <- if (grepl("Base\\s+impo(nible|sable)", text) || grepl("(Término|Terme)\\s+fi(jo|x)[^\n]*=", text)) {
    parse_new(lines, text)
  } else if (grepl("TOTAL BRUTO", text)) {
    parse_old(lines, text, if (is.na(number)) "^$" else number)
  } else {
    return(bad("Formato de factura no reconocido."))
  }
  it <- p$items
  msg <- character()
  if (!nrow(it)) msg <- c(msg, "No se han encontrado conceptos facturados.")
  if (nrow(it) && any(is.na(it$month))) msg <- c(msg, "No se ha podido determinar el mes de algún concepto.")
  if (is.na(p$base)) p$base <- if (!is.na(p$total) && !is.na(p$iva_rate)) round(p$total / (1 + p$iva_rate / 100), 2) else NA_real_
  if (is.na(p$iva_rate)) p$iva_rate <- 21
  if (nrow(it) && !is.na(p$base)) {
    tol <- 0.01 * nrow(it) + 0.011
    if (abs(sum(it$amount) - p$base) > tol) {
      msg <- c(msg, sprintf("Los conceptos suman %.2f € y la base imponible es %.2f €.", sum(it$amount), p$base))
    }
  } else if (is.na(p$base)) {
    msg <- c(msg, "No se ha encontrado la base imponible.")
  }
  if (!is.na(p$total) && !is.na(p$base) && abs(p$base * (1 + p$iva_rate / 100) - p$total) > 0.03) {
    msg <- c(msg, sprintf("La base (%.2f €) más IVA no coincide con el total (%.2f €).", p$base, p$total))
  }
  list(
    invoice = data.frame(file = file, number = number, type = substr(number, 1, 3),
                         format = p$format, months = paste(sort(unique(it$month)), collapse = ", "),
                         base = p$base, iva_rate = p$iva_rate, total = p$total,
                         ok = !length(msg), msg = paste(msg, collapse = " "),
                         stringsAsFactors = FALSE),
    items = if (nrow(it)) cbind(number = number, file = file, it, stringsAsFactors = FALSE) else it
  )
}

# texts: texto de cada PDF; errors: "" o el motivo por el que no se pudo leer.
parse_invoices <- function(texts, names, errors = rep("", length(texts))) {
  res <- Map(function(t, n, e) if (nzchar(e)) bad_invoice(n, e) else parse_invoice_text(t, n),
             texts, names, errors)
  inv <- do.call(rbind, lapply(res, `[[`, "invoice"))
  items <- do.call(rbind, lapply(res, function(r) if (nrow(r$items)) r$items else NULL))
  rownames(inv) <- NULL
  # Misma factura subida dos veces
  dup <- inv$ok & !is.na(inv$number) & duplicated(inv$number)
  inv$ok[dup] <- FALSE
  inv$msg[dup] <- "Factura repetida (mismo número que otro archivo)."
  if (is.null(items)) items <- cbind(number = character(), file = character(), empty_items())
  items <- items[items$file %in% inv$file[inv$ok], , drop = FALSE]
  rownames(items) <- NULL
  list(invoices = inv, items = items)
}

# Resumen por mes. El exceso compara el término fijo facturado con el que
# correspondería si fuera el 32,5 % (o el 40 %) del coste sin IVA. Se suman las
# diferencias de todos los meses, también las negativas: equivale a comparar el
# fijo total del periodo con el admisible para todo el consumo del periodo.
monthly_summary <- function(items, invoices) {
  if (!nrow(items)) return(NULL)
  months <- sort(unique(items$month))
  s <- function(m, k) sum(items$amount[items$month == m & items$kind %in% k])
  # Precio unitario que figura en la factura (aparece aunque el consumo sea 0),
  # ponderado por consumo si hay varias líneas en el mes.
  wprice <- function(m, k) {
    x <- items[items$month == m & items$kind == k & !is.na(items$price), ]
    if (!nrow(x)) return(NA_real_)
    q <- ifelse(is.na(x$qty), 0, x$qty)
    if (sum(q) > 0) sum(x$price * q) / sum(q) else mean(x$price)
  }
  iva <- setNames(invoices$iva_rate, invoices$number)
  df <- data.frame(
    month = months,
    fijo = vapply(months, s, 0, k = "fijo"),
    calor = vapply(months, s, 0, k = "calor"),
    frio = vapply(months, s, 0, k = "frio"),
    volumen = vapply(months, s, 0, k = "volumen"),
    otro = vapply(months, s, 0, k = "otro"),
    descuento = vapply(months, s, 0, k = "descuento"),
    n_facturas = vapply(months, function(m) length(unique(items$number[items$month == m])), 0L),
    iva_rate = vapply(months, function(m) {
      r <- iva[unique(items$number[items$month == m])]; if (all(is.na(r))) 21 else mean(r, na.rm = TRUE)
    }, 0),
    precio_calor = vapply(months, wprice, 0, k = "calor"),
    precio_frio = vapply(months, wprice, 0, k = "frio"),
    precio_volumen = vapply(months, wprice, 0, k = "volumen"),
    stringsAsFactors = FALSE, row.names = NULL
  )
  df$variable <- df$calor + df$frio + df$volumen + df$otro
  df$bruto <- df$fijo + df$variable
  df$neto <- df$bruto + df$descuento
  df$pct_fijo <- ifelse(df$bruto > 0, 100 * df$fijo / df$bruto, NA_real_)
  factor <- ifelse(df$bruto > 0, df$neto / df$bruto, 1)
  df$exceso_325 <- (df$fijo - df$variable * 0.325 / 0.675) * factor
  df$exceso_40 <- (df$fijo - df$variable * 0.40 / 0.60) * factor
  df$exceso_325_iva <- df$exceso_325 * (1 + df$iva_rate / 100)
  df$exceso_40_iva <- df$exceso_40 * (1 + df$iva_rate / 100)
  df$total_iva <- df$neto * (1 + df$iva_rate / 100)
  df
}
