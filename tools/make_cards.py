#!/usr/bin/env python3
"""
make_cards.py — Title-card generator for the Belgium show.

Two jobs:
  1. Build the 3 PRE-SHOW slides (bilingual NL/EN) shown behind the academy
     students who play before Lionel comes on. 1920x1080, on-theme.
  2. Composite a "featuring <guest performers>" line onto the 4 existing
     piece cards (Dreams of a Violin, Gallop, Beethoven Virus, Four Seasons
     Nightmare) WITHOUT touching their original title/subtitle pixels — we
     open each real card, detect where its subtitle ends, and draw one more
     gold italic line below it in that card's own type style.

Re-run any time the academy sends more text — just edit PRESHOW below.
Originals of the 4 cards are backed up under backup/ before this runs.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---- shared palette (sampled from the existing cards) -----------------------
BG    = (8, 8, 12)
CREAM = (240, 236, 228)
GOLD  = (176, 141, 87)
GREY  = (150, 150, 158)

# ---- fonts ------------------------------------------------------------------
F_SERIF   = "/System/Library/Fonts/Supplemental/Georgia.ttf"
F_ITALIC  = "/System/Library/Fonts/Supplemental/Georgia Italic.ttf"
F_NY      = "/System/Library/Fonts/NewYork.ttf"
F_NY_ITAL = "/System/Library/Fonts/NewYorkItalic.ttf"

def font(path, size):
    return ImageFont.truetype(path, size)

# ---------------------------------------------------------------------------
# Generic centered vertical-stack layout engine for the pre-show slides.
# An element is a dict: {kind, ...}. kinds: 'text', 'rule', 'space'.
# ---------------------------------------------------------------------------
def wrap(text, fnt, max_w, draw):
    words = text.split()
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if draw.textlength(trial, font=fnt) <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines

def text_el(text, fnt, color, gap=22, leading=1.34):
    return {"kind": "text", "text": text, "font": fnt, "color": color,
            "gap": gap, "leading": leading}

def rule_el(width=240, gap=40, pad_top=18):
    return {"kind": "rule", "width": width, "gap": gap, "pad_top": pad_top}

def space_el(h):
    return {"kind": "space", "h": h, "gap": 0}

def measure(elements, W, draw):
    """Return total height and a per-element list of wrapped lines."""
    total = 0
    prepared = []
    for el in elements:
        if el["kind"] == "text":
            fnt = el["font"]
            asc, desc = fnt.getmetrics()
            lh = int((asc + desc) * el["leading"])
            lines = wrap(el["text"], fnt, int(W * 0.74), draw)
            h = lh * len(lines)
            prepared.append((el, lines, lh, h))
            total += h + el["gap"]
        elif el["kind"] == "rule":
            h = el["pad_top"] + 3
            prepared.append((el, None, None, h))
            total += h + el["gap"]
        else:  # space
            prepared.append((el, None, None, el["h"]))
            total += el["h"]
    return total, prepared

def render_slide(path, elements, W=1920, H=1080):
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    total, prepared = measure(elements, W, draw)
    y = (H - total) // 2
    cx = W // 2
    for el, lines, lh, h in prepared:
        if el["kind"] == "text":
            for ln in lines:
                w = draw.textlength(ln, font=el["font"])
                draw.text((cx - w / 2, y), ln, font=el["font"], fill=el["color"])
                y += lh
            y += el["gap"]
        elif el["kind"] == "rule":
            y += el["pad_top"]
            draw.line([(cx - el["width"] / 2, y), (cx + el["width"] / 2, y)],
                      fill=GOLD, width=3)
            y += 3 + el["gap"]
        else:
            y += el["h"]
    img.save(path)
    print("wrote", os.path.relpath(path, ROOT))

# ---------------------------------------------------------------------------
# PRE-SHOW slide content. NL primary (cream/gold), EN secondary (gold italic).
# ---------------------------------------------------------------------------
def preshow_elements(piece_nl, composer, played_nl, nl_desc,
                     piece_en, played_en, en_desc):
    serif_title = font(F_SERIF, 100)
    italic_comp = font(F_ITALIC, 46)
    serif_play  = font(F_SERIF, 46)
    italic_desc = font(F_ITALIC, 33)
    en_head     = font(F_ITALIC, 35)
    en_body     = font(F_ITALIC, 30)

    els = [
        text_el(piece_nl, serif_title, CREAM, gap=14),
        text_el(composer, italic_comp, GOLD, gap=4),
        rule_el(gap=34),
        text_el(played_nl, serif_play, CREAM, gap=16),
    ]
    for line in nl_desc:
        els.append(text_el(line, italic_desc, GREY, gap=8))
    els.append(space_el(40))
    # subtle EN divider dot
    els.append(text_el("·", font(F_ITALIC, 30), GOLD, gap=22))
    els.append(text_el(piece_en, en_head, GOLD, gap=8))
    els.append(text_el(played_en, en_body, GOLD, gap=8))
    for line in en_desc:
        els.append(text_el(line, en_body, GOLD, gap=6))
    return els

PRESHOW = [
    {  # P1
        "folder": "Preshow 1 - Shostakovich Waltz",
        "args": dict(
            piece_nl="Tweede Wals",
            composer="Dmitri Shostakovich",
            played_nl="Gespeeld door Ianis Merino Bessi",
            nl_desc=[
                "Ianis Merino Bessi (13) — pianoleerling in de derde graad, uit de klas van Fiona Alaimo.",
                "Enthousiast, gepassioneerd en gedreven.",
            ],
            piece_en="Second Waltz · Dmitri Shostakovich",
            played_en="Performed by Ianis Merino Bessi",
            en_desc=[
                "Ianis Merino Bessi (13) — piano student in the third grade, from the class of Fiona Alaimo.",
                "Enthusiastic, passionate and driven.",
            ],
        ),
    },
    {  # P2
        "folder": "Preshow 2 - Pachelbel Canon",
        "args": dict(
            piece_nl="Canon in D",
            composer="Johann Pachelbel",
            played_nl="Gespeeld door Elena De Pooter, Romuald Smeets en Phuc-An Nguyen",
            nl_desc=["Starters"],
            piece_en="Canon in D · Johann Pachelbel",
            played_en="Performed by Elena De Pooter, Romuald Smeets and Phuc-An Nguyen",
            en_desc=["Beginning students"],
        ),
    },
    {  # P3
        "folder": "Preshow 3 - Fur Elise",
        "args": dict(
            piece_nl="Für Elise",
            composer="Ludwig van Beethoven",
            played_nl="Gespeeld door Rithika Garbham",
            nl_desc=[],
            piece_en="Für Elise · Ludwig van Beethoven",
            played_en="Performed by Rithika Garbham",
            en_desc=[],
        ),
    },
]

# ---------------------------------------------------------------------------
# "featuring" line composited onto the 4 existing cards.
# ---------------------------------------------------------------------------
def subtitle_bottom(img):
    """Lowest row that still has card text, scanning the central column band."""
    W, H = img.size
    bg = img.getpixel((10, 10))
    x0, x1 = int(W * 0.2), int(W * 0.8)
    last = None
    px = img.load()
    for y in range(0, H, 2):
        c = 0
        for x in range(x0, x1, 3):
            r, g, b = px[x, y]
            if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > 60:
                c += 1
                if c > 3:
                    last = y
                    break
    return last

def add_featuring(card_path, text, italic_font_path, color=GOLD):
    img = Image.open(card_path).convert("RGB")
    W, H = img.size
    scale = H / 1080.0
    draw = ImageDraw.Draw(img)
    bottom = subtitle_bottom(img) or int(H * 0.66)
    size = int(40 * scale)
    fnt = font(italic_font_path, size)
    asc, desc = fnt.getmetrics()
    y = bottom + int(64 * scale)
    w = draw.textlength(text, font=fnt)
    draw.text((W / 2 - w / 2, y), text, font=fnt, fill=color)
    img.save(card_path)
    print("featuring ->", os.path.relpath(card_path, ROOT))

FEATURED = [
    ("Dreams of a Violin/TitleCard.png",
     "featuring Alicia De Pooter, violin", F_ITALIC, GOLD),
    ("Beethoven Virus/TitleCard.png",
     "featuring Gudrun Vercampt, violin   ·   Anthony Gröger, cello", F_ITALIC, GOLD),
    ("Gallop/TitleCard.png",
     "featuring Alicia De Poorter, violin   ·   Céline Uten, cello", F_ITALIC, GOLD),
    ("Four Seasons Nightmare/TitleCard.png",
     "featuring Gudrun Vercampt, violin", F_NY_ITAL, (190, 165, 120)),
]

def main():
    for slide in PRESHOW:
        folder = os.path.join(ROOT, slide["folder"])
        os.makedirs(folder, exist_ok=True)
        render_slide(os.path.join(folder, "TitleCard.png"),
                     preshow_elements(**slide["args"]))
    for rel, text, fpath, color in FEATURED:
        add_featuring(os.path.join(ROOT, rel), text, fpath, color)

if __name__ == "__main__":
    main()
