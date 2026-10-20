// Extrae el texto de las facturas en el navegador con pdf.js y lo pasa a R.
// pdftools (poppler) se bloquea en WebAssembly con los PDF que no incrustan sus
// fuentes, como las facturas antiguas de Ecoenergies; pdf.js los lee bien.
// itemsToLines() rehace las líneas a partir de la posición de cada texto, con
// varias columnas separadas por espacios, como el texto de pdftools.
(function (root) {
  "use strict";

  function itemsToLines(items) {
    const rows = [];
    for (const it of items) {
      if (!it.str || !it.str.trim()) continue;
      const x = it.transform[4], y = it.transform[5];
      const h = Math.abs(it.transform[3]) || Math.abs(it.transform[0]) || 8;
      let row = rows.find(r => Math.abs(r.y - y) <= Math.max(2, h * 0.3));
      if (!row) { row = { y: y, items: [] }; rows.push(row); }
      row.items.push({ x: x, w: it.width, s: it.str, h: h });
    }
    rows.sort((a, b) => b.y - a.y);
    return rows.map(r => {
      r.items.sort((a, b) => a.x - b.x);
      let line = "", end = null;
      for (const it of r.items) {
        if (end !== null) {
          const gap = it.x - end;
          line += gap > it.h * 0.8 ? "   " : (gap > it.h * 0.12 ? " " : "");
        }
        line += it.s;
        end = it.x + it.w;
      }
      return line;
    }).join("\n");
  }

  async function pdfText(pdfjs, data) {
    // verbosity 0: sin avisos por las fuentes no incrustadas (no afectan al texto)
    const pdf = await pdfjs.getDocument({ data: data, isEvalSupported: false, disableFontFace: true, verbosity: 0 }).promise;
    const pages = [];
    for (let p = 1; p <= pdf.numPages; p++) {
      const page = await pdf.getPage(p);
      pages.push(itemsToLines((await page.getTextContent()).items));
    }
    await pdf.destroy();
    return pages.join("\n");
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = { itemsToLines: itemsToLines, pdfText: pdfText };
    return;
  }

  // ---- Navegador ----
  root.pdfjsLib.GlobalWorkerOptions.workerSrc = "vendor/pdf.worker.min.js";

  function setStatus(msg) {
    const el = document.getElementById("extract_status");
    if (el) el.textContent = msg;
  }

  async function handle(files) {
    const names = [], texts = [], errors = [];
    const jobs = [];
    for (const f of files) {
      if (/\.zip$/i.test(f.name)) {
        try {
          const zip = await root.JSZip.loadAsync(await f.arrayBuffer());
          Object.values(zip.files).forEach(e => {
            if (!e.dir && /\.pdf$/i.test(e.name) && !/__MACOSX/.test(e.name)) {
              jobs.push({ name: e.name.split("/").pop(), get: () => e.async("uint8array") });
            }
          });
        } catch (err) {
          names.push(f.name); texts.push(""); errors.push("No se ha podido abrir el archivo ZIP.");
        }
      } else if (/\.pdf$/i.test(f.name)) {
        jobs.push({ name: f.name, get: async () => new Uint8Array(await f.arrayBuffer()) });
      }
    }
    for (let i = 0; i < jobs.length; i++) {
      setStatus("Leyendo " + (i + 1) + " de " + jobs.length + ": " + jobs[i].name);
      names.push(jobs[i].name);
      try {
        texts.push(await pdfText(root.pdfjsLib, await jobs[i].get()));
        errors.push("");
      } catch (err) {
        texts.push("");
        errors.push("No se ha podido abrir el PDF.");
      }
    }
    setStatus(jobs.length ? "Calculando…" : "");
    root.Shiny.setInputValue("pdf_texts", { names: names, texts: texts, errors: errors, t: Date.now() }, { priority: "event" });
  }

  document.addEventListener("change", e => {
    if (e.target && e.target.id === "pdf_files" && e.target.files.length) {
      const files = Array.from(e.target.files);
      e.target.value = "";  // permite volver a elegir los mismos archivos
      handle(files);
    }
  });
  document.addEventListener("dragover", e => {
    if (e.target.closest && e.target.closest(".upload")) { e.preventDefault(); e.target.closest(".upload").classList.add("drag"); }
  });
  document.addEventListener("dragleave", e => {
    if (e.target.closest && e.target.closest(".upload")) e.target.closest(".upload").classList.remove("drag");
  });
  document.addEventListener("drop", e => {
    const box = e.target.closest && e.target.closest(".upload");
    if (!box) return;
    e.preventDefault(); box.classList.remove("drag");
    if (e.dataTransfer.files.length) handle(Array.from(e.dataTransfer.files));
  });
  // CSV generado en R: el BOM hace que Excel lo abra como UTF-8 (tildes, €)
  function downloadCsv(msg) {
    const blob = new Blob(["\uFEFF" + msg.content], { type: "text/csv;charset=utf-8" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = msg.name;
    document.body.appendChild(a);
    a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }

  function register() {
    root.Shiny.addCustomMessageHandler("extract_status", msg => setStatus(msg));
    root.Shiny.addCustomMessageHandler("download_csv", downloadCsv);
  }
  if (root.Shiny) register(); else document.addEventListener("shiny:connected", register);
})(typeof window !== "undefined" ? window : this);
