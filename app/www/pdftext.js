// Extrae el texto de las facturas en el navegador con pdf.js y lo pasa a R.
// pdftools (poppler) se bloquea en WebAssembly con los PDF que no incrustan sus
// fuentes, como las facturas antiguas de Ecoenergies; pdf.js los lee bien.
// itemsToLines() rehace las líneas a partir de la posición de cada texto, con
// varias columnas separadas por espacios, como el texto de pdftools.
// También genera las descargas (Excel y CSV): downloadHandler no funciona en shinylive.
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
    // isEvalSupported: false neutraliza la vulnerabilidad CVE-2024-4367 de versiones antiguas.
    // verbosity 0: sin avisos por las fuentes no incrustadas (no afectan al texto).
    const pdf = await pdfjs.getDocument({ data: data, isEvalSupported: false, disableFontFace: true, verbosity: 0 }).promise;
    const pages = [];
    for (let p = 1; p <= pdf.numPages; p++) {
      const page = await pdf.getPage(p);
      pages.push(itemsToLines((await page.getTextContent()).items));
    }
    await pdf.destroy();
    return pages.join("\n");
  }

  // ---- Tablas descargables: cols es una lista de columnas (null = vacío) ----
  function asRows(msg) {
    const cols = msg.cols.map(c => Array.isArray(c) ? c : [c]);
    const n = cols.length ? cols[0].length : 0;
    const rows = [];
    for (let i = 0; i < n; i++) rows.push(cols.map(c => c[i]));
    return rows;
  }

  function toCsv(msg) {
    const q = v => (v === null || v === undefined) ? "" :
      (typeof v === "number" ? String(v) : '"' + String(v).replace(/"/g, '""') + '"');
    return [msg.header.map(q).join(",")].concat(asRows(msg).map(r => r.map(q).join(","))).join("\r\n");
  }

  function colName(i) {
    let s = "";
    for (i += 1; i > 0; i = Math.floor((i - 1) / 26)) s = String.fromCharCode(65 + (i - 1) % 26) + s;
    return s;
  }

  // XLSX mínimo (Office Open XML): se abre igual en cualquier Excel, Numbers,
  // LibreOffice o Google Sheets, sin depender del separador regional.
  function toXlsx(JSZip, msg) {
    const esc = s => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
    const cell = (v, r, c, style) => {
      const ref = colName(c) + r;
      if (v === null || v === undefined || v === "") return "";
      if (typeof v === "number" && isFinite(v)) return '<c r="' + ref + '"' + (style ? ' s="' + style + '"' : "") + "><v>" + v + "</v></c>";
      return '<c r="' + ref + '" t="inlineStr"' + (style ? ' s="' + style + '"' : "") + "><is><t>" + esc(v) + "</t></is></c>";
    };
    const rows = [msg.header].concat(asRows(msg));
    const sheetRows = rows.map((r, i) => '<row r="' + (i + 1) + '">' + r.map((v, j) => cell(v, i + 1, j, i === 0 ? 1 : 0)).join("") + "</row>").join("");
    const widths = msg.header.map((h, j) => '<col min="' + (j + 1) + '" max="' + (j + 1) + '" width="' + Math.max(10, String(h).length + 2) + '" customWidth="1"/>').join("");
    const ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';
    const rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
    const head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
    const zip = new JSZip();
    const add = (name, data) => zip.file(name, data, { createFolders: false });  // sin entradas de carpeta
    add("[Content_Types].xml", head +
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
      '<Default Extension="xml" ContentType="application/xml"/>' +
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>' +
      "</Types>");
    add("_rels/.rels", head + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rId1" Type="' + rel + '/officeDocument" Target="xl/workbook.xml"/></Relationships>');
    add("xl/workbook.xml", head + "<workbook " + ns + ' xmlns:r="' + rel + '"><sheets><sheet name="' + esc(msg.sheet || "Resumen") + '" sheetId="1" r:id="rId1"/></sheets></workbook>');
    add("xl/_rels/workbook.xml.rels", head + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rId1" Type="' + rel + '/worksheet" Target="worksheets/sheet1.xml"/>' +
      '<Relationship Id="rId2" Type="' + rel + '/styles" Target="styles.xml"/></Relationships>');
    add("xl/styles.xml", head + "<styleSheet " + ns + ">" +
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>' +
      '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>' +
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
      '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>' +
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>');
    add("xl/worksheets/sheet1.xml", head + "<worksheet " + ns + "><cols>" + widths + "</cols><sheetData>" + sheetRows + "</sheetData></worksheet>");
    return zip.generateAsync({ type: "blob", mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = { itemsToLines: itemsToLines, pdfText: pdfText, toCsv: toCsv, toXlsx: toXlsx };
    return;
  }

  // ---- Navegador ----
  // pdf.js 4 se distribuye como módulo: se carga al elegir el primer archivo.
  let pdfjsPromise = null;
  function loadPdfjs() {
    if (!pdfjsPromise) {
      pdfjsPromise = import(new URL("vendor/pdf.min.js", document.baseURI).href).then(m => {
        m.GlobalWorkerOptions.workerSrc = new URL("vendor/pdf.worker.min.js", document.baseURI).href;
        return m;
      });
    }
    return pdfjsPromise;
  }

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
    let pdfjs = null;
    if (jobs.length) {
      setStatus("Preparando el lector de PDF…");
      try { pdfjs = await loadPdfjs(); } catch (err) { pdfjs = null; }
    }
    for (let i = 0; i < jobs.length; i++) {
      setStatus("Leyendo " + (i + 1) + " de " + jobs.length + "…");
      names.push(jobs[i].name);
      try {
        if (!pdfjs) throw new Error("pdf.js no disponible");
        texts.push(await pdfText(pdfjs, await jobs[i].get()));
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

  function save(blob, name) {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = name;
    document.body.appendChild(a);
    a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }

  async function downloadTable(msg) {
    if (msg.format === "xlsx") {
      save(await toXlsx(root.JSZip, msg), msg.name);
    } else {
      // CSV estándar (coma y punto decimal); el BOM indica UTF-8 (tildes, €)
      save(new Blob(["\uFEFF" + toCsv(msg)], { type: "text/csv;charset=utf-8" }), msg.name);
    }
  }

  function register() {
    root.Shiny.addCustomMessageHandler("extract_status", msg => setStatus(msg));
    root.Shiny.addCustomMessageHandler("download_table", downloadTable);
  }
  if (root.Shiny) register(); else document.addEventListener("shiny:connected", register);
})(typeof window !== "undefined" ? window : this);
