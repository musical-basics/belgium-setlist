#!/usr/bin/env python3
"""
make_solo_cards.py — title cards for the live SOLO/REG halves of the nightmare
pieces (6A Torrent Etude, 7A Für Elise, 9A Moonlight Sonata).

These pieces are played live (no backing) before their nightmare half fires, so
they need their OWN clean cards that do NOT say "Nightmare". Style matches the
main piece cards exactly: dark navy-black, Rockwell slab-serif cream title, a
gold rule, Georgia-italic gold subtitle (palette sampled from the originals).

Re-run any time; writes <folder>/TitleCard.png for each entry in CARDS.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BG, CREAM, GOLD = (8, 8, 12), (240, 236, 228), (176, 141, 87)
F_TITLE = "/System/Library/Fonts/Supplemental/Rockwell.ttc"          # slab serif (main-card title)
F_ITAL  = "/System/Library/Fonts/Supplemental/Georgia Italic.ttf"    # gold italic subtitle
W, H = 1920, 1080
TITLE_CY, DIV_Y, SUB_CY, DIV_W, DIV_TH = 452, 632, 700, 440, 4       # layout measured off the originals

def card(folder, title, subtitle, title_size=150, sub_size=58):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    ft = ImageFont.truetype(F_TITLE, title_size, index=0)
    fs = ImageFont.truetype(F_ITAL, sub_size)
    b = d.textbbox((0, 0), title, font=ft)
    d.text((W/2 - (b[2]-b[0])/2 - b[0], TITLE_CY - (b[3]-b[1])/2 - b[1]), title, font=ft, fill=CREAM)
    d.line([(W/2 - DIV_W/2, DIV_Y), (W/2 + DIV_W/2, DIV_Y)], fill=GOLD, width=DIV_TH)
    b2 = d.textbbox((0, 0), subtitle, font=fs)
    d.text((W/2 - (b2[2]-b2[0])/2 - b2[0], SUB_CY - (b2[3]-b2[1])/2 - b2[1]), subtitle, font=fs, fill=GOLD)
    os.makedirs(os.path.join(ROOT, folder), exist_ok=True)
    img.save(os.path.join(ROOT, folder, "TitleCard.png"))
    print("wrote", folder + "/TitleCard.png")

CARDS = [
    ("Torrent Etude",    "Torrent Etude",    "Frédéric Chopin"),
    ("Fur Elise",        "Für Elise",        "Ludwig van Beethoven"),
    ("Moonlight Sonata", "Moonlight Sonata", "Beethoven  ·  1st Movement"),
]

if __name__ == "__main__":
    for folder, title, subtitle in CARDS:
        card(folder, title, subtitle)
