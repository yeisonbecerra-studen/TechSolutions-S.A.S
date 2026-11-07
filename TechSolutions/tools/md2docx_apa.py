"""Convierte una nota Markdown a .docx con formato APA 7 (manual CUN).

Uso:
    uv run --with python-docx tools/md2docx_apa.py entrada.md [salida.docx]

Convenciones del Markdown de entrada:
  - Todo lo anterior a la línea <!-- fin-portada --> es la portada (centrada, en negrita la 1.ª línea).
  - # Nivel 1 (centrado, negrita) | ## Nivel 2 (izquierda, negrita) | ### Nivel 3 (negrita cursiva).
  - <!-- salto --> inserta un salto de página.
  - Tablas Markdown: la línea **Tabla N** y la línea *Título* previas se usan como rótulo APA;
    una línea que empiece con "*Nota.*" después de la tabla se usa como nota.
  - Las entradas bajo "Referencias" llevan sangría francesa.
  - ![texto](ruta.png) inserta una imagen.
"""
import re
import sys
from pathlib import Path

from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK, WD_LINE_SPACING
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt

FUENTE = "Times New Roman"
INLINE = re.compile(r"(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)")


def add_runs(p, texto, bold=False, italic=False):
    texto = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r"\1 (\2)", texto)  # enlaces -> texto (url)
    for parte in INLINE.split(texto):
        if not parte:
            continue
        if parte.startswith("**"):
            r = p.add_run(parte[2:-2]); r.bold = True; r.italic = italic
        elif parte.startswith("`"):
            r = p.add_run(parte[1:-1]); r.font.name = "Courier New"; r.font.size = Pt(10)
        elif parte.startswith("*"):
            r = p.add_run(parte[1:-1]); r.italic = True; r.bold = bold
        else:
            r = p.add_run(parte); r.bold = bold; r.italic = italic


def fmt(p, sangria=True, centro=False, doble=True, francesa=False, antes=0, despues=0):
    pf = p.paragraph_format
    pf.line_spacing_rule = WD_LINE_SPACING.DOUBLE if doble else WD_LINE_SPACING.SINGLE
    pf.space_before, pf.space_after = Pt(antes), Pt(despues)
    if centro:
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    if francesa:
        pf.left_indent, pf.first_line_indent = Cm(1.27), Cm(-1.27)
    elif sangria and not centro:
        pf.first_line_indent = Cm(1.27)


def bordes_tabla(tabla):
    """APA: solo líneas horizontales (arriba, bajo el encabezado y al final)."""
    tbl_pr = tabla._tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    for lado in ("top", "bottom"):
        el = OxmlElement(f"w:{lado}")
        el.set(qn("w:val"), "single"); el.set(qn("w:sz"), "8"); el.set(qn("w:color"), "000000")
        borders.append(el)
    for lado in ("left", "right", "insideH", "insideV"):
        el = OxmlElement(f"w:{lado}"); el.set(qn("w:val"), "nil"); borders.append(el)
    tbl_pr.append(borders)
    for celda in tabla.rows[0].cells:
        tc_pr = celda._tc.get_or_add_tcPr()
        tcb = OxmlElement("w:tcBorders")
        b = OxmlElement("w:bottom")
        b.set(qn("w:val"), "single"); b.set(qn("w:sz"), "6"); b.set(qn("w:color"), "000000")
        tcb.append(b); tc_pr.append(tcb)


def anchos_columnas(tabla, filas, ncol, total_cm=16.5):
    """Ancho de columna proporcional al texto (APA no exige columnas iguales) y encabezado repetido."""
    largo = [max(min(len(f[c]) if c < len(f) else 0, 60) for f in filas) + 6 for c in range(ncol)]
    piso = 2.3                                       # cm mínimos por columna
    cm = [total_cm * x / sum(largo) for x in largo]
    cortas = [c for c in cm if c < piso]
    resto = sum(c for c in cm if c >= piso)
    escala = (total_cm - piso * len(cortas)) / resto if resto else 1
    anchos = [Cm(piso if c < piso else c * escala) for c in cm]
    tabla.autofit = False
    for col, w in zip(tabla._tbl.tblGrid.findall(qn("w:gridCol")), anchos):
        col.set(qn("w:w"), str(int(w.twips if hasattr(w, "twips") else w / 635)))
    for fila in tabla.rows:
        no_partir = OxmlElement("w:cantSplit"); fila._tr.get_or_add_trPr().append(no_partir)
        for c, w in enumerate(anchos):
            fila.cells[c].width = w
    tr_pr = tabla.rows[0]._tr.get_or_add_trPr()
    el = OxmlElement("w:tblHeader"); el.set(qn("w:val"), "true"); tr_pr.append(el)


def numero_pagina(section):
    p = section.header.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    run = p.add_run()
    for tipo, texto in (("begin", None), (None, "PAGE"), ("end", None)):
        if tipo:
            el = OxmlElement("w:fldChar"); el.set(qn("w:fldCharType"), tipo)
        else:
            el = OxmlElement("w:instrText"); el.set(qn("xml:space"), "preserve"); el.text = texto
        run._r.append(el)


def salto(doc):
    """Salto de página sin crear un párrafo vacío extra (evita páginas en blanco)."""
    ultimo = doc.element.body[-2] if len(doc.element.body) > 1 else None  # [-1] es sectPr
    if ultimo is not None and ultimo.tag == qn("w:p"):
        doc.paragraphs[-1].add_run().add_break(WD_BREAK.PAGE)
    else:
        doc.add_paragraph().add_run().add_break(WD_BREAK.PAGE)


def celdas(linea):
    return [c.strip() for c in linea.strip().strip("|").split("|")]


def convertir(md_path, docx_path):
    base = Path(md_path).parent
    lineas = Path(md_path).read_text(encoding="utf-8").splitlines()
    doc = Document()

    estilo = doc.styles["Normal"]
    estilo.font.name = FUENTE
    estilo.font.size = Pt(12)
    estilo.element.rPr.rFonts.set(qn("w:eastAsia"), FUENTE)
    sec = doc.sections[0]
    sec.page_width, sec.page_height = Cm(21.59), Cm(27.94)  # carta
    for lado in ("top_margin", "bottom_margin", "left_margin", "right_margin"):
        setattr(sec, lado, Cm(2.54))
    numero_pagina(sec)

    # --- Portada -------------------------------------------------------
    if "<!-- fin-portada -->" in lineas:
        fin = lineas.index("<!-- fin-portada -->")
        portada = [l.strip() for l in lineas[:fin]]
        lineas = lineas[fin + 1:]
        for _ in range(3):
            fmt(doc.add_paragraph(), centro=True)
        for n, l in enumerate(x for x in portada if x):   # las líneas vacías del MD no cuentan
            p = doc.add_paragraph()
            fmt(p, centro=True)
            add_runs(p, l.lstrip("# ").strip(), bold=(n == 0))
            if n == 0:
                fmt(doc.add_paragraph(), centro=True)      # línea en blanco tras el título
        salto(doc)

    en_referencias = False
    i = 0
    while i < len(lineas):
        l = lineas[i].rstrip()
        s = l.strip()

        if not s or s.startswith("<!--") and s != "<!-- salto -->":
            i += 1; continue
        if s == "<!-- salto -->" or s == "---":
            if s == "<!-- salto -->":
                salto(doc)
            i += 1; continue

        m = re.match(r"^(#{1,3})\s+(.*)", s)
        if m:
            nivel, texto = len(m.group(1)), m.group(2)
            p = doc.add_paragraph()
            fmt(p, sangria=False, centro=(nivel == 1))
            add_runs(p, texto, bold=True, italic=(nivel == 3))
            p.paragraph_format.keep_with_next = True
            en_referencias = texto.lower().startswith("referencias")
            i += 1; continue

        # Rótulo de tabla/figura APA: "**Tabla N**" y en la línea siguiente "*Título*"
        if re.match(r"^\*\*(Tabla|Figura) \d+\*\*$", s):
            p = doc.add_paragraph(); fmt(p, sangria=False, doble=False, antes=12)
            add_runs(p, s); p.paragraph_format.keep_with_next = True
            if i + 1 < len(lineas) and lineas[i + 1].strip().startswith("*"):
                i += 1
                p = doc.add_paragraph(); fmt(p, sangria=False, doble=False, despues=6)
                add_runs(p, lineas[i].strip()); p.paragraph_format.keep_with_next = True
            i += 1; continue

        if s.startswith("|"):
            filas = []
            while i < len(lineas) and lineas[i].strip().startswith("|"):
                if not re.match(r"^\|?\s*:?-{2,}", lineas[i].strip()):
                    filas.append(celdas(lineas[i]))
                i += 1
            ncol = len(filas[0])
            tabla = doc.add_table(rows=len(filas), cols=ncol)
            tabla.alignment = WD_TABLE_ALIGNMENT.CENTER
            for r, fila in enumerate(filas):
                for c in range(ncol):
                    celda = tabla.cell(r, c)
                    p = celda.paragraphs[0]
                    fmt(p, sangria=False, doble=False, antes=2, despues=2)
                    if r == 0:
                        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                    add_runs(p, fila[c] if c < len(fila) else "", bold=(r == 0))
                    for run in p.runs:
                        run.font.size = Pt(10)
            bordes_tabla(tabla)
            anchos_columnas(tabla, filas, ncol)
            if i < len(lineas) and lineas[i].strip() == "":
                i += 1
            if i < len(lineas) and lineas[i].strip().startswith("*Nota"):
                p = doc.add_paragraph(); fmt(p, sangria=False, doble=False, antes=4, despues=12)
                add_runs(p, lineas[i].strip()); i += 1
            else:
                fmt(doc.add_paragraph(), sangria=False, doble=False)
            continue

        img = re.match(r"^!\[([^\]]*)\]\(([^)]+)\)", s)
        if img:
            ruta = (base / img.group(2)).resolve()
            if ruta.exists():
                doc.add_picture(str(ruta), width=Cm(15))
                doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER
            i += 1; continue

        if s.startswith("```"):
            i += 1; bloque = []
            while i < len(lineas) and not lineas[i].strip().startswith("```"):
                bloque.append(lineas[i]); i += 1
            i += 1
            p = doc.add_paragraph(); fmt(p, sangria=False, doble=False, despues=8)
            r = p.add_run("\n".join(bloque)); r.font.name = "Courier New"; r.font.size = Pt(9)
            continue

        lista = re.match(r"^(\s*)([-*]|\d+\.)\s+(.*)", l)
        if lista:
            estilo_lista = "List Number" if lista.group(2)[0].isdigit() else "List Bullet"
            p = doc.add_paragraph(style=estilo_lista)
            fmt(p, sangria=False)
            add_runs(p, lista.group(3))
            i += 1; continue

        if s.startswith(">"):
            p = doc.add_paragraph(); fmt(p, sangria=False)
            p.paragraph_format.left_indent = Cm(1.27)
            add_runs(p, s.lstrip("> "))
            i += 1; continue

        # Párrafo normal (une líneas consecutivas)
        texto = [s]; i += 1
        while i < len(lineas) and lineas[i].strip() and not re.match(
                r"^(#|\||!\[|```|>|<!--|\s*([-*]|\d+\.)\s|\*\*(Tabla|Figura) )", lineas[i].strip()):
            texto.append(lineas[i].strip()); i += 1
        p = doc.add_paragraph()
        fmt(p, sangria=not en_referencias, francesa=en_referencias)
        add_runs(p, " ".join(texto))

    doc.save(docx_path)
    print(f"Generado: {docx_path}")


if __name__ == "__main__":
    entrada = sys.argv[1]
    salida = sys.argv[2] if len(sys.argv) > 2 else str(Path(entrada).with_suffix(".docx"))
    convertir(entrada, salida)
