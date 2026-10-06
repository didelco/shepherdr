#!/usr/bin/env python3
"""Prepares the README header for pixelate.swift: erases the code digits from the dog's coat and draws
the masks that recolor the dog into the app logo's amber shepherd.

Only needed when the hand-made regions change; make-artwork.sh uses the files this writes, which are
committed. Requires Pillow and NumPy.

Usage: python3 scripts/make-header-masks.py [docs/assets/source/header]
Reads original.png and regions.json there (polygon, eyes, tongue, the title's "h" between the paws and
the columns of digits, all hand-placed in original.png's pixels) and writes clean.png plus the masks.
"""
import json
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

folder = sys.argv[1] if len(sys.argv) > 1 else "docs/assets/source/header"
source = Image.open(f"{folder}/original.png").convert("RGBA")
width, height = source.size
regions = json.load(open(f"{folder}/regions.json"))
rgba = np.asarray(source).astype(int)
r, g, b, a = rgba[..., 0], rgba[..., 1], rgba[..., 2], rgba[..., 3]


def polygon(points):
    image = Image.new("L", (width, height), 0)
    ImageDraw.Draw(image).polygon([tuple(p) for p in points], fill=255)
    return np.asarray(image) > 0


def circles(items):
    image = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(image)
    for x, y, radius in items:
        draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=255)
    return np.asarray(image) > 0


def dilate(mask, size):
    return np.asarray(Image.fromarray(mask.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(size))) > 0


def rows(top, bottom):
    mask = np.zeros((height, width), bool)
    mask[top:bottom] = True
    return mask


def luma(pixels):
    return 0.2126 * pixels[..., 0] + 0.7152 * pixels[..., 1] + 0.0722 * pixels[..., 2]


def filtered(pixels, *filters):
    image = Image.fromarray(pixels[..., :3].astype(np.uint8))
    for f in filters:
        image = image.filter(f)
    return np.asarray(image).astype(int)


def save(mask, name):
    Image.fromarray(np.where(mask, 255, 0).astype(np.uint8)).convert("RGB").save(f"{folder}/{name}")


outline = polygon(regions["dog"])
eyes = circles(regions["eyes"])
tongue = polygon(regions["tongue"])
x0, y0, x1, y1 = regions["title_ascender"]
ascender = np.zeros((height, width), bool)
ascender[y0:y1, x0:x1] = True

# Pixel classes of the original art.
neon = (a > 0) & (r < 50) & (g > 150) & (b < 80)              # the glowing outlines: almost pure green
lime = (a > 0) & (g > 70) & (r >= 0.5 * g)                   # the dog's yellow-green coat
dark = (a > 0) & (np.maximum(np.maximum(r, g), b) < 45)       # black outlines
falloff = (a > 0) & (r < 24) & (b < 48) & (g >= 24) & (g < 150)  # the glow's dark halo

# The title's outline and its dark surroundings never join the dog: there, the letters' green line is
# the only edge between the two, and only the paws' light coat belongs to the dog.
title_zone = dilate(neon & rows(700, height), 31) | ascender
paws = lime & (luma(rgba) > 120)
# The coat: the polygon, plus coat-colored pixels (or the glow's halo) within 16 px of it, above the title.
band = dilate(outline, 33) & rows(0, 741) & (lime | dark | falloff) & ~neon & ~title_zone
coat = ((outline & ~(title_zone & ~paws)) | band) & ~ascender
erasable = coat & ~eyes & ~tongue

# Erase the code digits from the coat, in three passes that keep its stripes and outlines.
# 1. Light digits over dark fur: an opening removes bright marks thinner than 7 px.
opened = filtered(rgba, ImageFilter.MinFilter(7), ImageFilter.MaxFilter(7))
digits = erasable & ~neon & (luma(rgba) - luma(opened) > 50) & (luma(opened) < 140)
digits = dilate(digits, 3) & erasable
clean = rgba.copy()
clean[digits, :3] = opened[digits]
# 2. Dark green digits over the light coat (the front legs): a closing removes dark marks thinner than
#    7 px, only where they are green-hued inside lime fur.
closed = filtered(clean, ImageFilter.MaxFilter(7), ImageFilter.MinFilter(7))
green_mark = (clean[..., 1] > 60) & (clean[..., 0] < 0.6 * clean[..., 1])
lime_around = (closed[..., 1] > 100) & (closed[..., 0] >= 0.5 * closed[..., 1])
digits = erasable & green_mark & lime_around & (luma(closed) - luma(clean) > 40)
digits = dilate(digits, 3) & erasable
clean[digits, :3] = closed[digits]
# 3. Whatever survives in the known digit columns goes with a median: glyph strokes are a minority in
#    a 9 px window, the coat's wider stripes are not.
columns = np.zeros((height, width), bool)
for x0, y0, x1, y1 in regions["digits"]:
    columns[y0:y1, x0:x1] = True
columns &= erasable
median = filtered(clean, ImageFilter.MedianFilter(9))
clean[columns, :3] = median[columns]
Image.fromarray(clean.astype(np.uint8)).save(f"{folder}/clean.png")

# Outlines come from the cleaned image, so erased digits never come back as outline. The glow's
# antialiased edge joins the line where it touches it.
cr, cg, cb = clean[..., 0], clean[..., 1], clean[..., 2]
neon = (a > 0) & (cr < 50) & (cg > 150) & (cb < 80)
greenish = (a > 0) & (cg > 100) & (cr < 0.5 * cg) & (cb < 0.6 * cg)
glow = neon | (greenish & dilate(neon, 5))
dog_outline = glow & dilate(outline, 45) & rows(0, 700) & ~eyes & ~tongue & ~title_zone

save(erasable, "dog-mask.png")                                   # amber coat
save(tongue, "tongue-mask.png")                                  # pink tongue
save(dog_outline, "dog-outline-mask.png")                        # the dog's brown outline
save(neon & ~dog_outline & ~eyes & ~tongue, "green-outline-mask.png")  # every other outline, one green
print(f"Wrote clean.png and four masks to {folder}")
