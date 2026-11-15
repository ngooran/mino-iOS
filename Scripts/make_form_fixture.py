#!/usr/bin/env python3
"""Writes MinoTests/Fixtures/form.pdf by hand: one page with every kind of
form field Fill & Sign handles.

  name      text field, empty
  notes     multiline text field
  news      checkbox, off
  plan      radio group with two buttons: basic (on) and premium
  country   dropdown: Netherlands, Germany, France
  sig       signature field

Run: python3 Scripts/make_form_fixture.py
"""
import os
import sys

objects = {}


def add(number, body):
    objects[number] = body if isinstance(body, bytes) else body.encode("latin-1")


def stream(dictionary, data):
    data = data.encode("latin-1")
    return ("<< %s /Length %d >>\nstream\n" % (dictionary, len(data))).encode("latin-1") + data + b"\nendstream"


CATALOG, PAGES, FONT, ZAPF, ACROFORM, PAGE, CONTENT = 1, 2, 3, 4, 5, 6, 7
NAME, NOTES, NEWS, NEWS_ON, NEWS_OFF = 10, 11, 12, 13, 14
PLAN, BASIC, PREMIUM, DOT_ON, DOT_OFF = 15, 16, 17, 18, 19
COUNTRY, COUNTRY_AP, SIG = 20, 21, 22

labels = [
    (700, "Membership Form"),
    (648, "Full name"),
    (578, "Notes"),
    (478, "Send me the newsletter"),
    (438, "Plan:   Basic            Premium"),
    (388, "Country"),
    (318, "Signature"),
]
text = "".join(
    "BT /F1 %d Tf 72 %d Td (%s) Tj ET\n" % (22 if y == 700 else 12, y, label) for y, label in labels
)

add(CATALOG, "<< /Type /Catalog /Pages %d 0 R /AcroForm %d 0 R >>" % (PAGES, ACROFORM))
add(PAGES, "<< /Type /Pages /Count 1 /Kids [%d 0 R] >>" % PAGE)
add(FONT, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
add(ZAPF, "<< /Type /Font /Subtype /Type1 /BaseFont /ZapfDingbats >>")
add(CONTENT, stream("", text))
widgets = [NAME, NOTES, NEWS, BASIC, PREMIUM, COUNTRY, SIG]
add(PAGE, "<< /Type /Page /Parent %d 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 %d 0 R >> >> /Contents %d 0 R /Annots [%s] >>"
    % (PAGES, FONT, CONTENT, " ".join("%d 0 R" % n for n in widgets)))

add(ACROFORM, "<< /Fields [%s] /DA (/Helv 12 Tf 0 g) /DR << /Font << /Helv %d 0 R /ZaDb %d 0 R >> >> /NeedAppearances true >>"
    % (" ".join("%d 0 R" % n for n in [NAME, NOTES, NEWS, PLAN, COUNTRY, SIG]), FONT, ZAPF))

box = "/MK << /BC [0.55 0.55 0.55] /BG [0.97 0.97 0.97] >>"
add(NAME, "<< /Type /Annot /Subtype /Widget /FT /Tx /T (name) /Rect [200 640 500 664] /F 4 /P %d 0 R /DA (/Helv 12 Tf 0 g) %s >>" % (PAGE, box))
add(NOTES, "<< /Type /Annot /Subtype /Widget /FT /Tx /Ff 4096 /T (notes) /Rect [200 520 500 596] /F 4 /P %d 0 R /DA (/Helv 11 Tf 0 g) %s >>" % (PAGE, box))

check_on = "q 0 0 0 rg BT /ZaDb 14 Tf 2.5 3.5 Td (4) Tj ET Q"
add(NEWS, "<< /Type /Annot /Subtype /Widget /FT /Btn /T (news) /V /Off /AS /Off /Rect [220 474 238 492] /F 4 /P %d 0 R "
          "/MK << /BC [0 0 0] /CA (4) >> /AP << /N << /Yes %d 0 R /Off %d 0 R >> >> >>" % (PAGE, NEWS_ON, NEWS_OFF))
add(NEWS_ON, stream("/Type /XObject /Subtype /Form /BBox [0 0 18 18] /Resources << /Font << /ZaDb %d 0 R >> >>" % ZAPF,
                    "q 0 0 0 RG 1 w 0.5 0.5 17 17 re S Q " + check_on))
add(NEWS_OFF, stream("/Type /XObject /Subtype /Form /BBox [0 0 18 18]", "q 0 0 0 RG 1 w 0.5 0.5 17 17 re S Q"))

# Radio group: Radio (bit 16) + NoToggleToOff (bit 15)
add(PLAN, "<< /FT /Btn /Ff 49152 /T (plan) /V /basic /Kids [%d 0 R %d 0 R] >>" % (BASIC, PREMIUM))
dot_on = "q 0 0 0 RG 1 w 9 9 8 0 360 re Q q 0 0 0 RG 1 w 1 1 16 16 re S 0 0 0 rg 5 5 8 8 re f Q"
dot_off = "q 0 0 0 RG 1 w 1 1 16 16 re S Q"
add(DOT_ON, stream("/Type /XObject /Subtype /Form /BBox [0 0 18 18]", dot_on))
add(DOT_OFF, stream("/Type /XObject /Subtype /Form /BBox [0 0 18 18]", dot_off))
add(BASIC, "<< /Type /Annot /Subtype /Widget /Parent %d 0 R /AS /basic /Rect [150 434 168 452] /F 4 /P %d 0 R "
           "/MK << /BC [0 0 0] /CA (l) >> /AP << /N << /basic %d 0 R /Off %d 0 R >> >> >>" % (PLAN, PAGE, DOT_ON, DOT_OFF))
add(PREMIUM, "<< /Type /Annot /Subtype /Widget /Parent %d 0 R /AS /Off /Rect [270 434 288 452] /F 4 /P %d 0 R "
             "/MK << /BC [0 0 0] /CA (l) >> /AP << /N << /premium %d 0 R /Off %d 0 R >> >> >>" % (PLAN, PAGE, DOT_ON, DOT_OFF))

# Dropdown: Combo (bit 18)
add(COUNTRY, "<< /Type /Annot /Subtype /Widget /FT /Ch /Ff 131072 /T (country) /Opt [(Netherlands) (Germany) (France)] /V (Netherlands) "
             "/Rect [200 380 400 404] /F 4 /P %d 0 R /DA (/Helv 12 Tf 0 g) %s /AP << /N %d 0 R >> >>" % (PAGE, box, COUNTRY_AP))
add(COUNTRY_AP, stream("/Type /XObject /Subtype /Form /BBox [0 0 200 24] /Resources << /Font << /Helv %d 0 R >> >>" % FONT,
                       "/Tx BMC q BT /Helv 12 Tf 0 g 4 7 Td (Netherlands) Tj ET Q EMC"))

add(SIG, "<< /Type /Annot /Subtype /Widget /FT /Sig /T (sig) /Rect [200 280 440 340] /F 4 /P %d 0 R %s >>" % (PAGE, box))

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
    out += (b"%010d 00000 n \n" % offsets[number]) if number in offsets else b"0000000000 65535 f \n"
out += b"trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (top + 1, CATALOG, xref)

path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "MinoTests", "Fixtures", "form.pdf")
with open(path, "wb") as handle:
    handle.write(out)
print("Wrote", os.path.normpath(path), len(out), "bytes")
