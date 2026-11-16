#!/usr/bin/env python3
"""Writes the Office fixtures in MinoTests/Fixtures.

  budget.xlsx   a small workbook, written part by part
  three-sheets.xlsx  three sheets, the middle one hidden
  slides.pptx   a two-slide presentation, written part by part
  notes.csv, notes.txt

two-sheets.xls and two-sheets-one-hidden.xls are TwoSheetsNoneHidden.xls and
TwoSheetsOneHidden.xls from the Apache POI test data (Apache License 2.0).

report.docx and report.rtf are made with macOS textutil from HTML:
  textutil -convert docx report.html -output report.docx

Run: python3 Scripts/make_office_fixtures.py
"""
import os
import zipfile

OUT = os.path.join(os.path.dirname(__file__), "..", "MinoTests", "Fixtures")
HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'


def write_zip(name, parts):
    path = os.path.join(OUT, name)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for part, body in parts:
            archive.writestr(part, HEAD + body)
    print("Wrote", os.path.normpath(path))


# ---------------------------------------------------------------- xlsx
rows = [
    ("Item", "Quantity", "Price"),
    ("Copper pipe 15 mm", 40, 3.2),
    ("Elbow fitting", 120, 0.85),
    ("Mixer tap", 6, 64.5),
    ("Sealant", 18, 5.75),
    ("MARKER-BUDGET-TOTAL", 184, 620.5),
]


def cell(ref, value):
    if isinstance(value, str):
        return '<c r="%s" t="inlineStr"><is><t>%s</t></is></c>' % (ref, value)
    return '<c r="%s"><v>%s</v></c>' % (ref, value)


sheet_rows = "".join(
    '<row r="%d">%s</row>' % (r + 1, "".join(cell("%s%d" % ("ABC"[c], r + 1), v) for c, v in enumerate(row)))
    for r, row in enumerate(rows)
)
write_zip("budget.xlsx", [
    ("[Content_Types].xml",
     '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
     '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
     '<Default Extension="xml" ContentType="application/xml"/>'
     '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
     '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
     '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
     '</Types>'),
    ("_rels/.rels",
     '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
     '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
     '</Relationships>'),
    ("xl/workbook.xml",
     '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
     'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
     '<sheets><sheet name="Materials" sheetId="1" r:id="rId1"/></sheets></workbook>'),
    ("xl/_rels/workbook.xml.rels",
     '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
     '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
     '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
     '</Relationships>'),
    ("xl/styles.xml",
     '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
     '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
     '<fills count="1"><fill><patternFill patternType="none"/></fill></fills>'
     '<borders count="1"><border/></borders>'
     '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
     '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
     '</styleSheet>'),
    ("xl/worksheets/sheet1.xml",
     '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
     '<cols><col min="1" max="1" width="28" customWidth="1"/></cols>'
     '<sheetData>%s</sheetData></worksheet>' % sheet_rows),
])

# Three sheets; "Hidden" must not be converted.
def sheet_xml(marker):
    return ('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
            '<row r="1">%s</row><row r="2">%s</row></sheetData></worksheet>' % (cell("A1", marker), cell("A2", 42)))


write_zip("three-sheets.xlsx", [
    ("[Content_Types].xml",
     '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
     '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
     '<Default Extension="xml" ContentType="application/xml"/>'
     '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
     + "".join('<Override PartName="/xl/worksheets/sheet%d.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' % n for n in (1, 2, 3))
     + '</Types>'),
    ("_rels/.rels",
     '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
     '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
     '</Relationships>'),
    ("xl/workbook.xml",
     '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
     'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
     '<bookViews><workbookView activeTab="0"/></bookViews>'
     '<sheets><sheet name="January" sheetId="1" r:id="rId1"/><sheet name="Hidden" sheetId="2" state="hidden" r:id="rId2"/>'
     '<sheet name="March" sheetId="3" r:id="rId3"/></sheets></workbook>'),
    ("xl/_rels/workbook.xml.rels",
     '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
     + "".join('<Relationship Id="rId%d" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet%d.xml"/>' % (n, n) for n in (1, 2, 3))
     + '</Relationships>'),
    ("xl/worksheets/sheet1.xml", sheet_xml("MARKER-JANUARY")),
    ("xl/worksheets/sheet2.xml", sheet_xml("MARKER-HIDDEN")),
    ("xl/worksheets/sheet3.xml", sheet_xml("MARKER-MARCH")),
])

# ---------------------------------------------------------------- pptx
NS = ('xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"')
EMPTY_TREE = ('<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
              '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>%s</p:spTree>')


def box(shape_id, name, x, y, w, h, text, size):
    return ('<p:sp><p:nvSpPr><p:cNvPr id="%d" name="%s"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>'
            '<p:spPr><a:xfrm><a:off x="%d" y="%d"/><a:ext cx="%d" cy="%d"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
            '<p:txBody><a:bodyPr wrap="square"/><a:lstStyle/><a:p><a:r><a:rPr lang="en-US" sz="%d"/><a:t>%s</a:t></a:r></a:p></p:txBody></p:sp>'
            % (shape_id, name, x, y, w, h, size, text))


def slide(title, body):
    shapes = box(2, "Title", 457200, 457200, 8229600, 1143000, title, 4000) + box(3, "Body", 457200, 1828800, 8229600, 3000000, body, 2400)
    return '<p:sld %s><p:cSld>%s</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>' % (NS, EMPTY_TREE % shapes)


THEME = (
    '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Mino"><a:themeElements>'
    '<a:clrScheme name="Mino"><a:dk1><a:srgbClr val="000000"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>'
    '<a:dk2><a:srgbClr val="1F3A5F"/></a:dk2><a:lt2><a:srgbClr val="EEEEEE"/></a:lt2>'
    '<a:accent1><a:srgbClr val="00838A"/></a:accent1><a:accent2><a:srgbClr val="FF9500"/></a:accent2>'
    '<a:accent3><a:srgbClr val="5856D6"/></a:accent3><a:accent4><a:srgbClr val="34A853"/></a:accent4>'
    '<a:accent5><a:srgbClr val="FF2D55"/></a:accent5><a:accent6><a:srgbClr val="636366"/></a:accent6>'
    '<a:hlink><a:srgbClr val="0A84FF"/></a:hlink><a:folHlink><a:srgbClr val="5856D6"/></a:folHlink></a:clrScheme>'
    '<a:fontScheme name="Mino"><a:majorFont><a:latin typeface="Helvetica"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
    '<a:minorFont><a:latin typeface="Helvetica"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme>'
    '<a:fmtScheme name="Mino"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst>'
    '<a:lnStyleLst><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst>'
    '<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>'
    '<a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst>'
    '</a:fmtScheme></a:themeElements></a:theme>')
CLR_MAP = '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
REL = '<Relationship Id="%s" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/%s" Target="%s"/>'


def rels(*items):
    return '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">%s</Relationships>' % "".join(REL % item for item in items)


write_zip("slides.pptx", [
    ("[Content_Types].xml",
     '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
     '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
     '<Default Extension="xml" ContentType="application/xml"/>'
     '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
     '<Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
     '<Override PartName="/ppt/slides/slide2.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
     '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
     '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
     '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
     '</Types>'),
    ("_rels/.rels", rels(("rId1", "officeDocument", "ppt/presentation.xml"))),
    ("ppt/presentation.xml",
     '<p:presentation %s><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
     '<p:sldIdLst><p:sldId id="256" r:id="rId2"/><p:sldId id="257" r:id="rId3"/></p:sldIdLst>'
     '<p:sldSz cx="9144000" cy="6858000" type="screen4x3"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>' % NS),
    ("ppt/_rels/presentation.xml.rels", rels(
        ("rId1", "slideMaster", "slideMasters/slideMaster1.xml"), ("rId2", "slide", "slides/slide1.xml"),
        ("rId3", "slide", "slides/slide2.xml"), ("rId4", "theme", "theme/theme1.xml"))),
    ("ppt/theme/theme1.xml", THEME),
    ("ppt/slideMasters/slideMaster1.xml",
     '<p:sldMaster %s><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>%s</p:cSld>%s'
     '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>' % (NS, EMPTY_TREE % "", CLR_MAP)),
    ("ppt/slideMasters/_rels/slideMaster1.xml.rels", rels(
        ("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"), ("rId2", "theme", "../theme/theme1.xml"))),
    ("ppt/slideLayouts/slideLayout1.xml",
     '<p:sldLayout %s type="blank"><p:cSld name="Blank">%s</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>' % (NS, EMPTY_TREE % "")),
    ("ppt/slideLayouts/_rels/slideLayout1.xml.rels", rels(("rId1", "slideMaster", "../slideMasters/slideMaster1.xml"))),
    ("ppt/slides/slide1.xml", slide("Workshop Plan", "Three goals for next year. MARKER-SLIDE-ONE")),
    ("ppt/slides/_rels/slide1.xml.rels", rels(("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"))),
    ("ppt/slides/slide2.xml", slide("Next Steps", "Hire, train and equip. MARKER-SLIDE-TWO")),
    ("ppt/slides/_rels/slide2.xml.rels", rels(("rId1", "slideLayout", "../slideLayouts/slideLayout1.xml"))),
])

with open(os.path.join(OUT, "notes.csv"), "w") as handle:
    handle.write("Name,Role,Start\nAlex Morgan,Plumber,2019\nSam Lee,Apprentice,2024\nMARKER-CSV,End,2026\n")
with open(os.path.join(OUT, "page.html"), "w") as handle:
    # A page that tries to run a script and to load a picture from the network.
    handle.write('<html><body><h1>Offline page</h1><p id="p">MARKER-HTML-BODY</p>'
                 '<img src="https://example.com/tracker.png" width="10" height="10">'
                 '<script>document.getElementById("p").textContent = "SCRIPT-RAN";</script></body></html>\n')
with open(os.path.join(OUT, "notes.txt"), "w") as handle:
    handle.write("Site notes\n\nThe boiler on the second floor needs a new valve.\nMARKER-TXT-END\n")
print("Wrote notes.csv and notes.txt")
