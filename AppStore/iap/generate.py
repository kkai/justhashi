#!/usr/bin/env python3
"""1024x1024 in-app purchase image: the rules lesson's board, solved.

    python3 AppStore/iap/generate.py

Writes just-hashi-full.png next to this file.

Same board the app's first lesson ships and the website lets you play, so it is
a real puzzle rather than a mock-up. Palette from Theme.swift.

RGB with no alpha: App Store artwork with transparency is rejected under
ITMS-90717.
"""

import math
import os
from PIL import Image, ImageDraw, ImageFont

SIZE = 1024
SCALE = 4

SEA_TOP = (23, 48, 78)
SEA_BOTTOM = (10, 22, 38)
ISLAND = (242, 243, 238)
RIM = (10, 22, 38)
INK = (18, 30, 43)
BRIDGE = (140, 170, 205)
LABEL = (206, 216, 226)

# The rules lesson board (TutorialPuzzles.rulesBoard), solved:
#   2 . 4 . 1     0=1 double, 1=2 single, 1=3 single
#       |
#   . . 1 . .
ISLANDS = [
    {"col": 0, "row": 0, "clue": 2},
    {"col": 2, "row": 0, "clue": 4},
    {"col": 4, "row": 0, "clue": 1},
    {"col": 2, "row": 2, "clue": 1},
]
BRIDGES = [(0, 1, 2), (1, 2, 1), (1, 3, 1)]

R = 86
PITCH = 190
RIM_WIDTH = 6
RAIL_WIDTH = 17
RAIL_OFFSET = 21
LABEL_TEXT = "Every lesson, drill and hint"

FONT_CANDIDATES = [
    "/System/Library/Fonts/SFCompactRounded.ttf",
    "/System/Library/Fonts/SFNSRounded.ttf",
    "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf",
]


def s(v):
    return v * SCALE


def load_font():
    for path in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, 100)
        except OSError:
            continue
    raise SystemExit("no rounded system font found")


def main():
    render = SIZE * SCALE
    image = Image.new("RGB", (render, render))
    draw = ImageDraw.Draw(image)

    for y in range(render):
        t = y / (render - 1)
        draw.line([(0, y), (render, y)],
                  fill=tuple(int(SEA_TOP[i] + (SEA_BOTTOM[i] - SEA_TOP[i]) * t) for i in range(3)))

    # Wave texture, same construction as the app icon.
    for row in range(9):
        y = s(83 + row * 105)
        t = y / (render - 1)
        base = tuple(int(SEA_TOP[i] + (SEA_BOTTOM[i] - SEA_TOP[i]) * t) for i in range(3))
        ink = tuple(min(255, c + 38) for c in base)
        x = s(30) + (s(105) if row % 2 else 0)
        while x < render:
            span = s(47)
            pts = [(x + d, y - s(6) * math.sin(math.pi * d / span)) for d in range(0, int(span), 2)]
            draw.line(pts, fill=ink, width=int(s(3)))
            x += s(210)

    # Centre the board, leaving room for one line of type below it.
    cols = max(i["col"] for i in ISLANDS)
    rows = max(i["row"] for i in ISLANDS)
    ox = (SIZE - cols * PITCH) / 2
    oy = (SIZE - rows * PITCH) / 2 - 46

    def cx(i):
        return ox + i["col"] * PITCH

    def cy(i):
        return oy + i["row"] * PITCH

    for a, b, count in BRIDGES:
        A, B = ISLANDS[a], ISLANDS[b]
        x1, y1, x2, y2 = s(cx(A)), s(cy(A)), s(cx(B)), s(cy(B))
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy)
        nx, ny = -dy / length, dx / length
        offsets = (-s(RAIL_OFFSET), s(RAIL_OFFSET)) if count == 2 else (0,)
        for off in offsets:
            draw.line([(x1 + nx * off, y1 + ny * off), (x2 + nx * off, y2 + ny * off)],
                      fill=BRIDGE, width=int(s(RAIL_WIDTH)))

    for i in ISLANDS:
        x, y, r = s(cx(i)), s(cy(i)), s(R)
        draw.ellipse([x - r, y - r, x + r, y + r],
                     fill=ISLAND, outline=RIM, width=int(s(RIM_WIDTH)))

    font = load_font()
    digit_font = font.font_variant(size=int(s(74)))
    for i in ISLANDS:
        text = str(i["clue"])
        box = draw.textbbox((0, 0), text, font=digit_font)
        w, h = box[2] - box[0], box[3] - box[1]
        draw.text((s(cx(i)) - w / 2 - box[0], s(cy(i)) - h / 2 - box[1]),
                  text, fill=INK, font=digit_font)

    label_font = font.font_variant(size=int(s(46)))
    box = draw.textbbox((0, 0), LABEL_TEXT, font=label_font)
    draw.text((render / 2 - (box[2] - box[0]) / 2 - box[0], s(SIZE - 148)),
              LABEL_TEXT, fill=LABEL, font=label_font)

    image = image.resize((SIZE, SIZE), Image.LANCZOS)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "just-hashi-full.png")
    image.save(out)          # RGB, no alpha
    check = Image.open(out)
    print(f"wrote {out}  {check.size} {check.mode}  {os.path.getsize(out)} bytes")


if __name__ == "__main__":
    main()
