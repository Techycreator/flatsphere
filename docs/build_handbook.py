"""Builds docs/Flatsphere_Handbook.docx from docs/HANDBOOK.md. Run after every edit: python docs\\build_handbook.py"""
import re
from pathlib import Path

from docx import Document
from docx.enum.section import WD_ORIENT
from docx.shared import Pt

root = Path(__file__).parent
lines = (root / "HANDBOOK.md").read_text(encoding="utf-8").splitlines()
doc = Document()
doc.sections[0].orientation = WD_ORIENT.LANDSCAPE
doc.sections[0].page_width, doc.sections[0].page_height = doc.sections[0].page_height, doc.sections[0].page_width
doc.styles["Normal"].font.size = Pt(10)


def runs(par, text):
    for part in re.split(r"(\*\*[^*]+\*\*|`[^`]+`|\*[^*]+\*)", text):
        if part.startswith("**") and part.endswith("**") and len(part) > 4:
            par.add_run(part[2:-2]).bold = True
        elif part.startswith("`") and part.endswith("`") and len(part) > 2:
            par.add_run(part[1:-1]).font.name = "Consolas"
        elif part.startswith("*") and part.endswith("*") and len(part) > 2:
            par.add_run(part[1:-1]).italic = True
        else:
            par.add_run(part)


def flush_table(rows):
    rows = [r for r in rows if not re.fullmatch(r"\|[\s\-:|]+\|", r)]
    cells = [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]
    table = doc.add_table(rows=len(cells), cols=len(cells[0]))
    table.style = "Light Grid Accent 1"
    for i, row in enumerate(cells):
        for j, text in enumerate(row[: len(cells[0])]):
            cell = table.cell(i, j)
            cell.text = ""
            runs(cell.paragraphs[0], text)
            for r in cell.paragraphs[0].runs:
                r.font.size = Pt(8 if len(cells[0]) > 8 else 9)
                if i == 0:
                    r.bold = True


buffer = []
for line in lines + [""]:
    if line.startswith("|"):
        buffer.append(line)
        continue
    if buffer:
        flush_table(buffer)
        buffer = []
    if not line.strip():
        continue
    if line.startswith("# "):
        doc.add_heading(line[2:], 0)
    elif line.startswith("## "):
        doc.add_heading(line[3:], 1)
    elif line.startswith("### "):
        doc.add_heading(line[4:], 2)
    elif line.startswith("> "):
        runs(doc.add_paragraph(style="Intense Quote"), line[2:])
    elif re.match(r"^\s*[-*] ", line):
        runs(doc.add_paragraph(style="List Bullet"), re.sub(r"^\s*[-*] ", "", line))
    elif re.match(r"^\d+\. ", line):
        runs(doc.add_paragraph(style="List Number"), re.sub(r"^\d+\. ", "", line))
    else:
        runs(doc.add_paragraph(), line.replace("\\*", "*"))

out = root / "Flatsphere_Handbook.docx"
doc.save(out)
print("saved", out)
