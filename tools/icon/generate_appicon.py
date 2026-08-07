#!/usr/bin/env python3
"""Renders the Just Hashi app icon.

    python3 tools/icon/generate_appicon.py

Writes Hashi/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024x1024).
Requires Pillow.

Lives outside `Hashi/` on purpose: that folder is a
PBXFileSystemSynchronizedRootGroup, so anything dropped inside it is copied
into the app bundle as a resource.

Two non-negotiables, both inherited from Just Kakuro:
  * render at 4x and downsample with LANCZOS, or the disc rims and digit
    edges alias badly at small sizes
  * save RGB with NO alpha channel — App Store artwork with alpha is
    rejected under ITMS-90717
"""

import math
from PIL import Image, ImageDraw, ImageFont

# --- measured from the shipped 1.0 icon; only island geometry has changed ---
SIZE = 1024
SCALE = 4                       # supersample factor

SEA_TOP = (23, 48, 78)          # deep prussian
SEA_BOTTOM = (10, 22, 38)       # near-black sea
ISLAND_FILL = (242, 243, 238)   # paper
ISLAND_RIM = (10, 22, 38)
DIGIT_INK = (18, 30, 43)
BRIDGE = (140, 170, 205)

RAIL_WIDTH = 26                 # bridge stroke
RAIL_OFFSET = 32                # half the gap between a double bridge's rails
RIM_WIDTH = 9                   # drawn inward from the island's outer radius

WAVE_ROWS = 9
WAVE_Y0, WAVE_PITCH_Y = 83, 105
WAVE_DASH, WAVE_PITCH_X = 47, 210
WAVE_LIFT = 42                  # channel lift over the background ≈ 0.33 alpha

# --- islands: three of them, all the same size ---
#
# Equal radii are the truthful choice as well as the tidier one: BoardView
# renders every island at one radius regardless of clue, so the old 150/118/84
# taper depicted a game that does not exist.
#
# d and R are picked so the group's bounding box is 163..861 on BOTH axes and
# therefore dead-centred on 512 by construction. Bounding-box centring is
# exactly the correction an L-shape needs — its raw centroid sits up and to the
# right. The visible corridor span is d - 2R = 162px each way, so neither
# bridge reads as a stub.
R = 134
D = 430
A = (297, 297)   # clue 2 — a double bridge to B
B = (727, 297)   # clue 3 — that double, plus a single to C
C = (727, 727)   # clue 1 — the single to B
#
# The clues are arithmetically valid and, because A and C share neither row nor
# column, no third corridor exists — so 2/3/1 admits exactly one solution: the
# picture. The icon is a legal one-move Hashi board.

DIGIT_CAP_HEIGHT = 115          # 0.43 x diameter, the shipped proportion

FONT_CANDIDATES = [
    "/System/Library/Fonts/SFCompactRounded.ttf",
    "/System/Library/Fonts/SFNSRounded.ttf",
    "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf",
]


def s(value):
    """Scale a design-space length into render space."""
    return value * SCALE


def load_font():
    for path in FONT_CANDIDATES:
        try:
            return ImageFont.truetype(path, 100)
        except OSError:
            continue
    raise SystemExit("no rounded system font found; the icon needs one")


def digit_font(font, draw):
    """The one font size every digit uses, found by cap height.

    Sized once from "0" so all three numerals match. Drawing each glyph
    centred on its own bbox is what stops "uniform size" from looking like
    "uniform left edge" — a "1" is far narrower than a "2".
    """
    target = s(DIGIT_CAP_HEIGHT)
    lo, hi = 10, 900
    while lo < hi:
        mid = (lo + hi + 1) // 2
        box = draw.textbbox((0, 0), "0", font=font.font_variant(size=mid))
        if (box[3] - box[1]) <= target:
            lo = mid
        else:
            hi = mid - 1
    return font.font_variant(size=lo)


def draw_sea(draw, size):
    for y in range(size):
        t = y / (size - 1)
        draw.line(
            [(0, y), (size, y)],
            fill=tuple(int(SEA_TOP[i] + (SEA_BOTTOM[i] - SEA_TOP[i]) * t) for i in range(3)),
        )


def draw_waves(draw, size):
    """Sparse hairline wave dashes. Static by design — restraint is the brand."""
    for row in range(WAVE_ROWS):
        y = s(WAVE_Y0 + row * WAVE_PITCH_Y)
        t = y / (size - 1)
        base = tuple(int(SEA_TOP[i] + (SEA_BOTTOM[i] - SEA_TOP[i]) * t) for i in range(3))
        ink = tuple(min(255, c + WAVE_LIFT) for c in base)
        phase = s(WAVE_PITCH_X / 2) if row % 2 else 0
        x = s(30) + phase
        while x < size:
            points = []
            span = s(WAVE_DASH)
            for step in range(0, int(span), 2):
                points.append((x + step, y - s(6) * math.sin(math.pi * step / span)))
            draw.line(points, fill=ink, width=int(s(3)))
            x += s(WAVE_PITCH_X)


def draw_island(draw, centre, radius):
    cx, cy = s(centre[0]), s(centre[1])
    r = s(radius)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r],
                 fill=ISLAND_FILL, outline=ISLAND_RIM, width=int(s(RIM_WIDTH)))


def draw_rails(draw, start, end, count):
    """Bridge rails, centre-to-centre and under the discs, so they terminate
    exactly on the rims with no seam."""
    x1, y1 = s(start[0]), s(start[1])
    x2, y2 = s(end[0]), s(end[1])
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy)
    nx, ny = -dy / length, dx / length
    offsets = (-s(RAIL_OFFSET), s(RAIL_OFFSET)) if count == 2 else (0,)
    for off in offsets:
        draw.line([(x1 + nx * off, y1 + ny * off), (x2 + nx * off, y2 + ny * off)],
                  fill=BRIDGE, width=int(s(RAIL_WIDTH)))


def draw_digit(draw, text, centre, font):
    box = draw.textbbox((0, 0), text, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    draw.text((s(centre[0]) - w / 2 - box[0], s(centre[1]) - h / 2 - box[1]),
              text, fill=DIGIT_INK, font=font)


def main():
    render = SIZE * SCALE
    image = Image.new("RGB", (render, render))
    draw = ImageDraw.Draw(image)

    draw_sea(draw, render)
    draw_waves(draw, render)

    draw_rails(draw, A, B, count=2)
    draw_rails(draw, B, C, count=1)

    for centre in (A, B, C):
        draw_island(draw, centre, R)

    font = digit_font(load_font(), draw)
    for text, centre in (("2", A), ("3", B), ("1", C)):
        draw_digit(draw, text, centre, font)

    image = image.resize((SIZE, SIZE), Image.LANCZOS)

    here = __file__.rsplit("/tools/", 1)[0]
    out = f"{here}/Hashi/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    image.save(out)          # RGB, no alpha — see the module docstring
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
