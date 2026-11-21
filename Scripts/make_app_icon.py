#!/usr/bin/env python3
"""Draws Mino's app icon: a white page with a folded corner and a teal "PDF"
on a teal background.

Writes, at 1024 x 1024 without transparency:
  Mino/Assets.xcassets/AppIcon.appiconset/AppIcon.png         (light)
  Mino/Assets.xcassets/AppIcon.appiconset/AppIcon-Dark.png    (dark home screen)
  Mino/Assets.xcassets/AppIcon.appiconset/AppIcon-Tinted.png  (tinted home screen, gray levels)
and the copy the app shows in Settings and the paywall:
  Mino/Assets.xcassets/AppIconArtwork.imageset/AppIconArtwork.png

The letters are Nunito Black (Scripts/fonts, SIL Open Font License).
Needs Pillow: python3 -m pip install pillow
Run: python3 Scripts/make_app_icon.py
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ICONSET = os.path.join(ROOT, "Mino", "Assets.xcassets", "AppIcon.appiconset")
ARTWORK = os.path.join(ROOT, "Mino", "Assets.xcassets", "AppIconArtwork.imageset")
FONT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts", "Nunito.ttf")

S = 2            # drawn at twice the size, then scaled down for smooth edges
N = 1024 * S

# The page and its letters, in 1024-point coordinates.
PAGE = (196, 196, 828, 828)
PAGE_RADIUS = 72
FOLD = 170
LETTERS_CENTER = (512, 512)
LETTERS_SIZE = 268
LINE = (300, 664, 724, 48)    # x0, y, x1, height


def v(x):
    return int(round(x * S))


def rgba(hex_color, alpha=255):
    h = hex_color.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (alpha,)


def gradient(top_left, bottom_right):
    small = 256
    image = Image.new("RGBA", (small, small))
    pixels = image.load()
    a, b = rgba(top_left), rgba(bottom_right)
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2 * (small - 1))
            pixels[x, y] = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))
    return image.resize((N, N), Image.BICUBIC)


def page_mask():
    x0, y0, x1, y1 = (v(c) for c in PAGE)
    mask = Image.new("L", (N, N), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([x0, y0, x1, y1], radius=v(PAGE_RADIUS), fill=255)
    draw.polygon([(x1 - v(FOLD), y0 - 2), (x1 + 2, y0 - 2), (x1 + 2, y0 + v(FOLD))], fill=0)
    return mask


def icon(background, paper, fold, letters, line, shadow_opacity):
    image = gradient(*background) if isinstance(background, tuple) else Image.new("RGBA", (N, N), rgba(background))
    mask = page_mask()

    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    shadow.putalpha(mask.point(lambda p: int(p * shadow_opacity)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(v(28)))
    image.alpha_composite(shadow, (0, v(18)))
    image.paste(Image.new("RGBA", (N, N), rgba(paper)), (0, 0), mask)

    draw = ImageDraw.Draw(image)
    x0, y0, x1, _ = PAGE
    draw.polygon([(v(x1 - FOLD), v(y0)), (v(x1), v(y0 + FOLD)), (v(x1 - FOLD), v(y0 + FOLD))], fill=rgba(fold))
    lx0, ly, lx1, lh = LINE
    draw.rounded_rectangle([v(lx0), v(ly), v(lx1), v(ly + lh)], radius=v(lh / 2), fill=rgba(line))

    font = ImageFont.truetype(FONT, v(LETTERS_SIZE))
    font.set_variation_by_name("Black")
    draw.text((v(LETTERS_CENTER[0]), v(LETTERS_CENTER[1])), "PDF", font=font, fill=rgba(letters), anchor="mm")
    return image.resize((1024, 1024), Image.LANCZOS).convert("RGB")


def main():
    light = icon(("#18C2AE", "#0B7A83"), "#FFFFFF", "#9BE7DB", "#0E8F87", "#BFEFE8", 0.28)
    dark = icon(("#0F2A2D", "#071516"), "#E9F1F0", "#5FC9BB", "#0E8F87", "#B5DCD6", 0.5)
    # Tinted: iOS colors the icon by brightness, so it is drawn in grays.
    tinted = icon("#000000", "#E6E6E6", "#8C8C8C", "#4A4A4A", "#9E9E9E", 0.0).convert("L").convert("RGB")

    light.save(os.path.join(ICONSET, "AppIcon.png"))
    dark.save(os.path.join(ICONSET, "AppIcon-Dark.png"))
    tinted.save(os.path.join(ICONSET, "AppIcon-Tinted.png"))
    os.makedirs(ARTWORK, exist_ok=True)
    light.resize((512, 512), Image.LANCZOS).save(os.path.join(ARTWORK, "AppIconArtwork.png"))
    print("Wrote the app icon and AppIconArtwork")


if __name__ == "__main__":
    main()
