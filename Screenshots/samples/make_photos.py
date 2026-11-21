#!/usr/bin/env python3
"""Sample photos for the Photos to PDF store frame (screenshots/capture.sh passes the folder
with -demoPhotos). Drawn, not photographed: paperwork people turn into PDFs, on believable
surfaces. Every name, number and address is made up.

Run: python3 screenshots/samples/make_photos.py   (needs Pillow)
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "photos")
SUP = "/System/Library/Fonts/Supplemental/"
FONTS = {
    "mono": SUP + "Courier New.ttf",
    "monob": SUP + "Courier New Bold.ttf",
    "sans": "/System/Library/Fonts/Helvetica.ttc",
    "serif": SUP + "Georgia.ttf",
    "serifb": SUP + "Georgia Bold.ttf",
    "hand": SUP + "Bradley Hand Bold.ttf",
    "marker": SUP + "Chalkboard.ttc",
}
random.seed(11)


def font(kind, size):
    return ImageFont.truetype(FONTS[kind], size)


def noise(img, amount=10, alpha=40):
    n = Image.effect_noise(img.size, amount).convert("RGB")
    return Image.blend(img, n, alpha / 255)


def wood(size):
    w, h = size
    img = Image.new("RGB", size, (150, 104, 66))
    d = ImageDraw.Draw(img)
    y = 0
    while y < h:
        band = random.randint(6, 26)
        c = random.randint(-22, 18)
        d.rectangle([0, y, w, y + band], fill=(150 + c, int(104 + c * 0.8), int(66 + c * 0.5)))
        y += band
    for _ in range(260):
        y0 = random.uniform(0, h)
        pts = [(x, y0 + 6 * math.sin(x / random.uniform(80, 200))) for x in range(0, w + 40, 40)]
        d.line(pts, fill=(118, 80, 48), width=random.randint(1, 3))
    img = img.filter(ImageFilter.GaussianBlur(2.2))
    return noise(img, 30, 22)


def marble(size):
    w, h = size
    img = Image.new("RGB", size, (232, 231, 228))
    d = ImageDraw.Draw(img)
    for _ in range(18):
        x, y = random.uniform(0, w), random.uniform(0, h)
        pts = []
        for _ in range(60):
            x += random.uniform(-30, 50); y += random.uniform(-40, 40)
            pts.append((x, y))
        d.line(pts, fill=(196, 196, 200), width=random.randint(2, 6))
    img = img.filter(ImageFilter.GaussianBlur(5))
    return noise(img, 20, 14)


def desk(size):
    img = Image.new("RGB", size, (64, 70, 78))
    return noise(img.filter(ImageFilter.GaussianBlur(1)), 30, 20)


def wall(size):
    img = Image.new("RGB", size, (214, 208, 196))
    return noise(img, 40, 26).filter(ImageFilter.GaussianBlur(0.8))


def place(bg, sheet, quad, shadow=0.45, blur=26, offset=(18, 26)):
    """Puts `sheet` onto `bg` at the four corners `quad` (tl, tr, br, bl), with a shadow."""
    w, h = sheet.size
    # Perspective coefficients mapping the output quad to the sheet's corners.
    mat = []
    for (x, y), (u, v) in zip(quad, [(0, 0), (w, 0), (w, h), (0, h)]):
        mat.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        mat.append([0, 0, 0, x, y, 1, -v * x, -v * y])
    rhs = [c for p in [(0, 0), (w, 0), (w, h), (0, h)] for c in p]
    coeff = solve(mat, rhs)
    warped = sheet.convert("RGBA").transform(bg.size, Image.PERSPECTIVE, coeff, Image.BICUBIC)
    mask = warped.split()[3]
    sh = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    sh.putalpha(mask.point(lambda p: int(p * shadow)))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    out = bg.convert("RGBA")
    out.alpha_composite(sh, offset)
    out.alpha_composite(warped)
    return out.convert("RGB")


def solve(a, b):
    """Gaussian elimination for the 8x8 perspective system."""
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(m[r][c]))
        m[c], m[p] = m[p], m[c]
        for r in range(n):
            if r != c:
                f = m[r][c] / m[c][c]
                m[r] = [x - f * y for x, y in zip(m[r], m[c])]
    return [m[i][n] / m[i][i] for i in range(n)]


def light(img, cx, cy, strength=0.32):
    """Uneven light: bright near (cx, cy), darker toward the corners."""
    w, h = img.size
    g = Image.radial_gradient("L").resize((int(w * 1.8), int(h * 1.8)))
    g = g.crop((int(w * 0.9 - cx), int(h * 0.9 - cy), int(w * 0.9 - cx) + w, int(h * 0.9 - cy) + h))
    dark = Image.new("RGB", img.size, (0, 0, 0))
    return Image.composite(dark, img, g.point(lambda p: int(p * strength)))


def paper(size, tint=(250, 248, 242)):
    return noise(Image.new("RGB", size, tint), 14, 10)


def receipt():
    s = paper((620, 1500), (248, 247, 243))
    d = ImageDraw.Draw(s)
    y = 50
    d.text((310, y), "CORNER MARKET", font=font("monob", 46), fill=(30, 30, 30), anchor="mt"); y += 64
    for line in ["12 Harbor Street", "Tel 555-0142", "21/11/2026   09:14"]:
        d.text((310, y), line, font=font("mono", 28), fill=(50, 50, 50), anchor="mt"); y += 38
    y += 20
    d.text((40, y), "-" * 34, font=font("mono", 28), fill=(60, 60, 60)); y += 44
    items = [("Oat milk 1L", "2.49"), ("Sourdough loaf", "4.20"), ("Apples 1kg", "3.15"), ("Coffee beans", "11.90"),
             ("Eggs x12", "3.80"), ("Spinach", "1.99"), ("Dark chocolate", "2.75"), ("Olive oil", "8.40")]
    for name, price in items:
        d.text((40, y), name, font=font("mono", 30), fill=(35, 35, 35))
        d.text((580, y), price, font=font("mono", 30), fill=(35, 35, 35), anchor="ra"); y += 46
    d.text((40, y), "-" * 34, font=font("mono", 28), fill=(60, 60, 60)); y += 50
    d.text((40, y), "TOTAL", font=font("monob", 38), fill=(20, 20, 20))
    d.text((580, y), "38.68", font=font("monob", 38), fill=(20, 20, 20), anchor="ra"); y += 70
    for line in ["CARD  **** 4821", "Thank you!"]:
        d.text((310, y), line, font=font("mono", 28), fill=(50, 50, 50), anchor="mt"); y += 44
    for x in range(120, 500, 9):
        d.rectangle([x, y + 40, x + random.choice([2, 3, 5]), y + 140], fill=(25, 25, 25))
    bg = wood((1512, 2016))
    img = place(bg, s, [(420, 180), (1130, 240), (1060, 1890), (330, 1830)])
    return light(img, 700, 600)


def whiteboard():
    s = Image.new("RGB", (1800, 1200), (245, 246, 244))
    d = ImageDraw.Draw(s)
    blue, red, green, ink = (30, 70, 170), (190, 40, 40), (30, 130, 70), (40, 40, 45)
    d.text((90, 70), "Launch plan", font=font("marker", 96), fill=ink)
    boxes = [(110, 330, "Design"), (680, 330, "Build"), (1250, 330, "Test")]
    for x, y, label in boxes:
        d.rounded_rectangle([x, y, x + 440, y + 190], radius=30, outline=blue, width=9)
        d.text((x + 220, y + 95), label, font=font("marker", 72), fill=blue, anchor="mm")
    for x in (560, 1130):
        d.line([(x, 425), (x + 110, 425)], fill=blue, width=9)
        d.polygon([(x + 110, 400), (x + 150, 425), (x + 110, 450)], fill=blue)
    notes = ["- screens by Friday", "- beta to 20 people", "- store text + photos"]
    for i, n in enumerate(notes):
        d.text((130, 640 + i * 110), n, font=font("marker", 62), fill=green if i == 1 else ink)
    d.ellipse([1240, 620, 1660, 900], outline=red, width=10)
    d.text((1450, 760), "Dec 3!", font=font("marker", 84), fill=red, anchor="mm")
    s = s.filter(ImageFilter.GaussianBlur(1.1))
    bg = wall((2016, 1512))
    img = place(bg, s, [(150, 210), (1880, 170), (1910, 1330), (120, 1360)], shadow=0.3, blur=18, offset=(8, 14))
    d2 = ImageDraw.Draw(img)
    d2.rectangle([780, 1360, 1240, 1420], fill=(170, 172, 176))
    return light(img, 900, 500, 0.28)


def letter():
    s = paper((1240, 1754))
    d = ImageDraw.Draw(s)
    d.text((110, 110), "Harbor Dental Practice", font=font("serifb", 54), fill=(20, 60, 90))
    d.text((110, 180), "4 Quay Lane  ·  555-0199", font=font("sans", 28), fill=(90, 100, 110))
    d.line([(110, 240), (1130, 240)], fill=(20, 60, 90), width=4)
    d.text((110, 300), "Sam Lee\n18 Elm Road", font=font("serif", 32), fill=(30, 30, 30), spacing=10)
    d.text((1130, 300), "18 November 2026", font=font("serif", 32), fill=(30, 30, 30), anchor="ra")
    d.text((110, 450), "Appointment confirmation", font=font("serifb", 40), fill=(20, 20, 20))
    body = ("Dear Sam,\n\nThis letter confirms your check-up on Tuesday 2 December at 10:30. "
            "Please arrive ten minutes early and bring this letter with you.\n\nIf you need to change the time, "
            "call us at least one day before. We look forward to seeing you.\n\nKind regards,\n\nDr. Ana Ruiz")
    y = 540
    for para in body.split("\n"):
        words, line = para.split(" "), ""
        for w_ in words:
            test = (line + " " + w_).strip()
            if d.textlength(test, font=font("serif", 32)) > 1000:
                d.text((110, y), line, font=font("serif", 32), fill=(35, 35, 35)); y += 48; line = w_
            else:
                line = test
        d.text((110, y), line, font=font("serif", 32), fill=(35, 35, 35)); y += 48
    bg = desk((1512, 2016))
    img = place(bg, s, [(250, 230), (1300, 190), (1350, 1720), (200, 1760)], shadow=0.6)
    d2 = ImageDraw.Draw(img)
    d2.line([(1150, 1800), (1460, 1450)], fill=(25, 25, 30), width=26)
    d2.line([(1440, 1472), (1470, 1438)], fill=(200, 170, 60), width=26)
    return light(img, 760, 700, 0.36)


def recipe():
    s = paper((1500, 1000), (252, 249, 238))
    d = ImageDraw.Draw(s)
    for y in range(230, 1000, 62):
        d.line([(0, y), (1500, y)], fill=(170, 200, 225), width=3)
    d.line([(0, 170), (1500, 170)], fill=(220, 120, 120), width=4)
    d.text((80, 60), "Grandma's lemon cake", font=font("hand", 84), fill=(40, 50, 110))
    lines = ["200 g butter, 200 g sugar", "4 eggs, 200 g flour", "zest + juice of 2 lemons",
             "bake 45 min at 175°C", "glaze: icing sugar + lemon"]
    for i, l in enumerate(lines):
        d.text((90, 248 + i * 124 - 54), l, font=font("hand", 60), fill=(40, 50, 110))
    bg = marble((2016, 1512))
    img = place(bg, s, [(310, 290), (1720, 360), (1660, 1290), (250, 1210)], shadow=0.35)
    d2 = ImageDraw.Draw(img)
    d2.ellipse([1640, 80, 2000, 440], fill=(250, 214, 64))
    d2.ellipse([1690, 130, 1950, 390], fill=(252, 230, 120))
    return light(img, 1000, 600, 0.3)


def notes():
    bg = wall((1512, 2016))
    colors = [(255, 236, 120), (255, 180, 200), (170, 225, 255), (190, 240, 170)]
    texts = ["Call\nplumber", "Pay rent\n1st", "Gym\nTue/Thu", "Buy\nprinter ink", "Renew\npassport", "Mom's b-day\nSat"]
    img = bg
    for i, t in enumerate(texts):
        s = Image.new("RGB", (520, 520), colors[i % 4])
        s = noise(s, 10, 8)
        ImageDraw.Draw(s).multiline_text((260, 260), t, font=font("hand", 76), fill=(40, 40, 60), anchor="mm", align="center", spacing=12)
        cx, cy = 400 + (i % 2) * 680, 360 + (i // 2) * 620
        a = math.radians(random.uniform(-6, 6))
        r = 260
        quad = [(cx + r * math.cos(a + k) * math.sqrt(2), cy + r * math.sin(a + k) * math.sqrt(2))
                for k in (math.radians(225), math.radians(315), math.radians(45), math.radians(135))]
        img = place(img, s, quad, shadow=0.35, blur=14, offset=(10, 16))
    return light(img, 700, 800, 0.3)


def ticket():
    s = paper((1500, 620), (246, 244, 236))
    d = ImageDraw.Draw(s)
    d.rectangle([0, 0, 1500, 140], fill=(22, 82, 92))
    d.text((60, 70), "CITY CONCERT HALL", font=font("sans", 62), fill=(255, 255, 255), anchor="lm")
    d.text((60, 220), "Winter Symphony", font=font("serifb", 72), fill=(25, 25, 25))
    d.text((60, 330), "Sat 13 December 2026  ·  19:30", font=font("sans", 40), fill=(60, 60, 60))
    for k, (lab, val) in enumerate([("ROW", "F"), ("SEAT", "14"), ("GATE", "B")]):
        d.text((60 + k * 260, 430), lab, font=font("sans", 30), fill=(120, 120, 120))
        d.text((60 + k * 260, 470), val, font=font("sans", 70), fill=(25, 25, 25))
    d.line([(1120, 0), (1120, 620)], fill=(160, 160, 160), width=4)
    for x in range(1170, 1440, 11):
        d.rectangle([x, 220, x + random.choice([3, 4, 7]), 520], fill=(25, 25, 25))
    bg = desk((2016, 1512))
    return light(place(bg, s, [(230, 470), (1800, 380), (1840, 1050), (260, 1150)], shadow=0.6), 1000, 600, 0.3)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, make in [("1 receipt", receipt), ("2 whiteboard", whiteboard), ("3 letter", letter),
                       ("4 recipe", recipe), ("5 notes", notes), ("6 ticket", ticket)]:
        make().save(os.path.join(OUT, f"{name}.jpg"), quality=86)
        print("wrote", name)


if __name__ == "__main__":
    main()
