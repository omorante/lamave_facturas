# Resumen de facturas de Ecoenergies · LAMAVE

Herramienta web de LAMAVE (La Asociación Vecinal de La Marina del Prat Vermell).
Lee las facturas de Ecoenergies en PDF y calcula cuánto pesa el término fijo y
cuánto supera los límites del RD 736/2020 (fijo entre el 25 % y el 40 %; 32,5 %
como referencia, el valor que aplicó la Sentencia 262/2024).

Funciona en el navegador con [shinylive](https://posit-dev.github.io/r-shinylive/).

## Privacidad

Todo se ejecuta en el navegador de quien la usa (R compilado a WebAssembly).
Las facturas no se suben a ningún servidor. El servidor solo entrega archivos
estáticos. Las fuentes van incluidas en la app, sin llamadas a Google Fonts.
No hay cookies ni analítica. El informe y las descargas no incluyen nombres de
archivo ni números de factura.

## Cómo funciona

- `app/www/pdftext.js`: extrae el texto de los PDF con pdf.js 4 y abre los ZIP
  con JSZip. Se usa pdf.js y no `pdftools` porque poppler se bloquea en
  WebAssembly con los PDF que no incrustan sus fuentes (las facturas antiguas).
  También genera las descargas en Excel (.xlsx) y CSV, porque `downloadHandler`
  no funciona en shinylive.
- `app/parse_invoices.R`: interpreta el texto y hace el resumen mensual.
  - Formato nuevo (desde abril de 2024), en castellano o en catalán.
  - Formato antiguo (2020 a marzo de 2024): coma decimal, varios meses por
    factura, potencia en kW, descuentos, rectificativas.
  - Cada factura se valida: los conceptos deben sumar la base imponible, y la
    base más el IVA, el total. Si no cuadra, se excluye y se indica el motivo.
- `app/app.R`: interfaz Shiny, gráficos con R base (carga más ligera).
- `build.R` y `build/`: exportan la app con la pantalla de carga de LAMAVE.

El exceso suma las diferencias de todos los meses, también las negativas.
Equivale a comparar el fijo total del periodo con el admisible para todo el
consumo del periodo.

## Desarrollo

Requiere R con `renv`.

```sh
Rscript -e 'renv::restore()'
Rscript -e 'shiny::runApp("app")'          # Shiny normal; pdf.js también extrae el texto en el navegador
Rscript build.R                              # genera site/
Rscript -e 'httpuv::runStaticServer("site")'
```

### Pruebas (con facturas locales, fuera del repo)

```sh
# Lector de R con texto de pdftools
Rscript tests/run_parser.R <carpeta-con-pdf> [--detail]

# Lector de R con el mismo texto que verá el navegador (pdf.js en Node)
npm install --prefix /tmp/pdfjs pdfjs-dist@4.10.38
PDFJS_DIST=/tmp/pdfjs/node_modules/pdfjs-dist node tests/extract_node.js <carpeta> /tmp/facturas.json
Rscript tests/run_parser.R --json /tmp/facturas.json

# Web exportada en Chrome sin interfaz (sube los PDF y guarda capturas en tests/out/)
Rscript tests/e2e_shinylive.R <carpeta-con-pdf | archivo.zip>
```

## Publicación

`.github/workflows/deploy.yml` exporta la app y la publica en GitHub Pages en
cada `push` a `main`. Para un subdominio (p. ej. `facturas.lamave.es`):

1. Settings → Pages → Source: GitHub Actions.
2. Settings → Secrets and variables → Actions → Variables: `PAGES_CNAME` = `facturas.lamave.es`.
3. DNS de lamave.es: registro `CNAME facturas → <cuenta>.github.io`.

## Licencias

- Código: GPL-3.0 (ver `LICENSE`).
- pdf.js: Apache 2.0 (`app/www/vendor/LICENSE-pdfjs.txt`).
- JSZip: MIT o GPL-3.0 (`app/www/vendor/LICENSE-jszip.md`).
- IBM Plex Sans y Playfair Display: SIL Open Font License 1.1 (`app/www/fonts/`).

Resultado orientativo. No es asesoramiento jurídico.
