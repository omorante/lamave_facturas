# Calculadora del término fijo de Ecoenergies · LAMAVE

Herramienta web de LAMAVE (La Asociación Vecinal de La Marina del Prat Vermell).
Lee las facturas de Ecoenergies en PDF y calcula cuánto pesa el término fijo y
cuánto supera los límites del RD 736/2020 (fijo entre el 25 % y el 40 %; 32,5 %
como referencia, el valor que aplicó la Sentencia 262/2024).

**Web:** https://omorante.github.io/lamave_facturas/

## Privacidad

Todo se ejecuta en el navegador de quien la usa. Las facturas no se suben a
ningún servidor: el servidor solo entrega los archivos de la web. No hay
cookies ni analítica, y las fuentes van incluidas. El informe y las descargas
no incluyen nombres de archivo ni números de factura.

## Cómo funciona

- `app/www/pdftext.js`: extrae el texto de los PDF con pdf.js, abre los ZIP con
  JSZip y genera las descargas en Excel y CSV.
- `app/parse_invoices.R`: interpreta las facturas y hace el resumen mensual.
  Reconoce el formato actual (desde abril de 2024, en castellano o en catalán)
  y el antiguo (2020 a marzo de 2024). Cada factura se valida: los conceptos
  deben sumar la base imponible, y la base más el IVA, el total. Si no cuadra,
  se excluye y se indica el motivo.
- `app/app.R`: interfaz en Shiny, que se ejecuta en el navegador con
  [shinylive](https://posit-dev.github.io/r-shinylive/) (R compilado a WebAssembly).

El exceso suma las diferencias de todos los meses, también las negativas.
Equivale a comparar el fijo total del periodo con el admisible para todo el
consumo del periodo.

## Desarrollo

Requiere R con `renv`.

```sh
Rscript -e 'renv::restore()'
Rscript -e 'shiny::runApp("app")'     # versión local
Rscript build.R                         # genera la web estática en site/
```

Las pruebas de `tests/` usan facturas locales, que nunca se añaden al
repositorio.

## Licencias

- Código: GPL-3.0 (ver `LICENSE`).
- pdf.js: Apache 2.0 (`app/www/vendor/LICENSE-pdfjs.txt`).
- JSZip: MIT o GPL-3.0 (`app/www/vendor/LICENSE-jszip.md`).
- IBM Plex Sans y Playfair Display: SIL Open Font License 1.1 (`app/www/fonts/`).

Resultado orientativo. No es asesoramiento jurídico.
