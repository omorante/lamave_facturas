// Extrae el texto de los PDF de una carpeta con el mismo código que usa el
// navegador (app/www/pdftext.js) y lo guarda en JSON: [{name, text, error}].
// Requiere pdfjs-dist 4.10.38 instalado fuera del repo.
// Uso: PDFJS_DIST=<ruta a node_modules/pdfjs-dist> node tests/extract_node.js <carpeta> <salida.json>
const fs = require("fs");
const path = require("path");
const { pathToFileURL } = require("url");
const { pdfText } = require(path.join(__dirname, "..", "app", "www", "pdftext.js"));

(async () => {
  const [dir, out] = process.argv.slice(2);
  const pdfjs = await import(pathToFileURL(path.join(process.env.PDFJS_DIST, "legacy", "build", "pdf.mjs")).href);
  const files = fs.readdirSync(dir).filter(f => /\.pdf$/i.test(f)).sort();
  const res = [];
  for (const f of files) {
    try {
      res.push({ name: f, text: await pdfText(pdfjs, new Uint8Array(fs.readFileSync(path.join(dir, f)))), error: "" });
    } catch (e) {
      res.push({ name: f, text: "", error: "No se ha podido abrir el PDF." });
    }
  }
  fs.writeFileSync(out, JSON.stringify(res));
  console.log(`${res.length} PDF extraídos en ${out}`);
})();
