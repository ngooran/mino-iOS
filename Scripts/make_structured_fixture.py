#!/usr/bin/env python3
"""Writes MinoTests/Fixtures/structured.pdf by hand.

Five chapters (Alpha ... Echo) with:
  - one bookmark per chapter
  - a link on Alpha to Delta (a /Dest array) and on Bravo to Charlie (a GoTo action)
  - a text field "fullName" on Bravo and a checkbox "agree" on Echo

Hand-written so the structure is exactly known; PDFKit on macOS 27 did not
write outlines. Run: python3 Scripts/make_structured_fixture.py
"""
import os
import sys

CHAPTERS = ["Alpha", "Bravo", "Charlie", "Delta", "Echo"]
objects = {}


def add(number, body):
    objects[number] = body if isinstance(body, bytes) else body.encode("latin-1")


def stream(dictionary, data):
    data = data.encode("latin-1")
    return ("<< %s /Length %d >>\nstream\n" % (dictionary, len(data))).encode("latin-1") + data + b"\nendstream"


# Object numbers
CATALOG, PAGES, FONT, OUTLINES, ACROFORM = 1, 2, 3, 4, 5
PAGE = lambda i: 10 + i          # 10..14
CONTENT = lambda i: 20 + i       # 20..24
BOOKMARK = lambda i: 30 + i      # 30..34
LINK_A, LINK_B, FIELD, FIELD_AP, CHECK, CHECK_ON, CHECK_OFF = 40, 41, 42, 43, 44, 45, 46

add(CATALOG, "<< /Type /Catalog /Pages %d 0 R /Outlines %d 0 R /AcroForm %d 0 R /PageMode /UseOutlines >>" % (PAGES, OUTLINES, ACROFORM))
add(PAGES, "<< /Type /Pages /Count 5 /Kids [%s] >>" % " ".join("%d 0 R" % PAGE(i) for i in range(5)))
add(FONT, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")

annots = {0: [LINK_A], 1: [LINK_B, FIELD], 4: [CHECK]}
for i, name in enumerate(CHAPTERS):
    text = (
        "BT /F1 24 Tf 72 700 Td (Chapter %s) Tj ET\n"
        "BT /F1 13 Tf 72 660 Td (This is chapter %d of the structured fixture.) Tj ET\n"
        "BT /F1 13 Tf 72 638 Td (Marker: %s-%d) Tj ET\n" % (name, i + 1, name.upper(), i + 1)
    )
    if i == 0:
        text += "BT /F1 13 Tf 76 506 Td (Go to chapter Delta) Tj ET\n"
    if i == 1:
        text += "BT /F1 13 Tf 76 506 Td (Go to chapter Charlie) Tj ET\n"
    add(CONTENT(i), stream("", text))
    extra = " /Annots [%s]" % " ".join("%d 0 R" % n for n in annots[i]) if i in annots else ""
    add(PAGE(i), "<< /Type /Page /Parent %d 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 %d 0 R >> >> /Contents %d 0 R%s >>"
        % (PAGES, FONT, CONTENT(i), extra))

# Bookmarks
add(OUTLINES, "<< /Type /Outlines /First %d 0 R /Last %d 0 R /Count 5 >>" % (BOOKMARK(0), BOOKMARK(4)))
for i, name in enumerate(CHAPTERS):
    parts = ["/Title (Chapter %s)" % name, "/Parent %d 0 R" % OUTLINES, "/Dest [%d 0 R /XYZ 0 792 0]" % PAGE(i)]
    if i > 0:
        parts.append("/Prev %d 0 R" % BOOKMARK(i - 1))
    if i < 4:
        parts.append("/Next %d 0 R" % BOOKMARK(i + 1))
    add(BOOKMARK(i), "<< %s >>" % " ".join(parts))

# Links
add(LINK_A, "<< /Type /Annot /Subtype /Link /Rect [72 500 292 524] /Border [0 0 0] /Dest [%d 0 R /Fit] >>" % PAGE(3))
add(LINK_B, "<< /Type /Annot /Subtype /Link /Rect [72 500 292 524] /Border [0 0 0] /A << /S /GoTo /D [%d 0 R /Fit] >> >>" % PAGE(2))

# Form
add(ACROFORM, "<< /Fields [%d 0 R %d 0 R] /DA (/Helv 12 Tf 0 g) /DR << /Font << /Helv %d 0 R >> >> >>" % (FIELD, CHECK, FONT))
add(FIELD, "<< /Type /Annot /Subtype /Widget /FT /Tx /T (fullName) /V (Alex Morgan) /Rect [72 400 332 428] /F 4 /P %d 0 R "
           "/DA (/Helv 12 Tf 0 g) /MK << /BC [0.6 0.6 0.6] >> /AP << /N %d 0 R >> >>" % (PAGE(1), FIELD_AP))
add(FIELD_AP, stream("/Type /XObject /Subtype /Form /BBox [0 0 260 28] /Resources << /Font << /Helv %d 0 R >> >>" % FONT,
                     "/Tx BMC q BT /Helv 12 Tf 0 g 4 9 Td (Alex Morgan) Tj ET Q EMC"))
add(CHECK, "<< /Type /Annot /Subtype /Widget /FT /Btn /T (agree) /V /Yes /AS /Yes /Rect [72 400 94 422] /F 4 /P %d 0 R "
           "/MK << /BC [0 0 0] /CA (4) >> /AP << /N << /Yes %d 0 R /Off %d 0 R >> >> >>" % (PAGE(4), CHECK_ON, CHECK_OFF))
add(CHECK_ON, stream("/Type /XObject /Subtype /Form /BBox [0 0 22 22]",
                     "q 0 0 0 RG 1 w 0.5 0.5 21 21 re S 2 w 5 11 m 9 6 l 17 17 l S Q"))
add(CHECK_OFF, stream("/Type /XObject /Subtype /Form /BBox [0 0 22 22]", "q 0 0 0 RG 1 w 0.5 0.5 21 21 re S Q"))

# Write the file with a classic cross-reference table.
out = bytearray(b"%PDF-1.7\n%\xe2\xe3\xcf\xd3\n")
offsets = {}
top = max(objects)
for number in sorted(objects):
    offsets[number] = len(out)
    out += b"%d 0 obj\n" % number + objects[number] + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 %d\n" % (top + 1)
out += b"0000000000 65535 f \n"
for number in range(1, top + 1):
    if number in offsets:
        out += b"%010d 00000 n \n" % offsets[number]
    else:
        out += b"0000000000 65535 f \n"
out += b"trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (top + 1, CATALOG, xref)

path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "MinoTests", "Fixtures", "structured.pdf")
with open(path, "wb") as handle:
    handle.write(out)
print("Wrote", os.path.normpath(path), len(out), "bytes")
