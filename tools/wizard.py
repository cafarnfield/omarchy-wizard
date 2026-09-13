#!/usr/bin/env python3
"""Draw the arcane 8-bit wizard, in the same palette as the village masthead.

Every frame is composed from the same primitives with a handful of pose
parameters, so the walk bob, hem sway and staff raise stay pixel-aligned
across frames instead of drifting the way hand-drawn variants do. Running
this file rewrites the plugin's Sprites.js; nothing else reads the PNGs,
which exist only for eyeballing the art.

    python3 ~/.config/omarchy/branding/wizard.py

The wizard lives at ~/.config/omarchy/plugins/chris.wizard/.
"""
import math
import os

from PIL import Image

W, H = 26, 30

PALETTE = {
    'K': (26, 22, 42),      # outline
    'P': (108, 92, 171),    # robe / hat  (village ROOF)
    'D': (74, 58, 115),     # robe shadow (village WALL)
    'L': (140, 122, 200),   # robe highlight (village TRIM)
    'S': (233, 186, 140),   # skin
    'N': (186, 140, 104),   # skin shadow
    'W': (233, 227, 255),   # beard (village MOON)
    'G': (168, 162, 205),   # beard shadow
    'B': (124, 96, 68),     # staff
    'T': (86, 66, 46),      # staff shadow
    'C': (187, 154, 247),   # orb (village ARCANE)
    'A': (233, 227, 255),   # orb core
    'Y': (255, 214, 138),   # hat star (village WINDOW lamplight)
    'E': (26, 22, 42),      # eye
    'M': (169, 180, 214),   # pewter / metal
    'R': (224, 106, 122),   # ember red
    'F': (111, 216, 200),   # fish teal
    'V': (127, 201, 138),   # leaf green
    'Q': (232, 220, 184),   # parchment
    'X': (38, 32, 58),      # cat black
    'x': (72, 62, 105),     # cat rim light
    'o': (255, 214, 138),   # cat eye
    '1': (216, 212, 192),   # bone
    '2': (22, 19, 32),      # Death's robe
    '3': (46, 40, 66),      # robe fold
    '4': (122, 226, 255),   # the little blue lights in his eye sockets
    '5': (58, 98, 104),     # something in the lake
    '6': (94, 148, 150),    # its suckers, catching the light
}

def blank():
    return [['.'] * W for _ in range(H)]

def px(g, x, y, c):
    x, y = int(round(x)), int(round(y))
    if 0 <= x < W and 0 <= y < H:
        g[y][x] = c

def rect(g, x0, y0, x1, y1, c):
    for y in range(int(round(y0)), int(round(y1)) + 1):
        for x in range(int(round(x0)), int(round(x1)) + 1):
            px(g, x, y, c)

ORB = [".XXXX.",
       "XXXXXX",
       "XXXXXX",
       "XXXXXX",
       "XXXXXX",
       ".XXXX."]

def stamp(g, rows, x0, y0, c, key='X'):
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch == key:
                px(g, x0 + i, y0 + j, c)

def outline(g, c='K'):
    solid = [[g[y][x] != '.' for x in range(W)] for y in range(H)]
    for y in range(H):
        for x in range(W):
            if solid[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and solid[ny][nx]:
                    g[y][x] = c
                    break

def draw_hat(g, dy):
    """Cone leaning right, over a wide brim."""
    for r in range(9):
        cx = 17.2 - r * 0.30
        half = 0.5 + r * 0.62
        rect(g, cx - half, dy + r, cx + half, dy + r, 'P')
        px(g, cx + half, dy + r, 'D')
        if r >= 3:
            px(g, cx - half, dy + r, 'L')
    px(g, 16, dy + 6, 'Y'); px(g, 15, dy + 7, 'Y'); px(g, 17, dy + 7, 'Y')
    rect(g, 10, dy + 9, 22, dy + 9, 'P')
    rect(g, 10, dy + 10, 22, dy + 10, 'D')


def draw_face(g, dy, eyes):
    """Face tucked under the brim."""
    rect(g, 12, dy + 11, 20, dy + 15, 'S')
    px(g, 12, dy + 11, 'N'); px(g, 20, dy + 11, 'N')
    ey = dy + 12
    if eyes == 'open':
        px(g, 14, ey, 'E'); px(g, 18, ey, 'E')
    elif eyes == 'closed':
        rect(g, 13, ey, 14, ey, 'N'); rect(g, 18, ey, 19, ey, 'N')
    else:
        px(g, 14, ey, 'E'); rect(g, 18, ey, 19, ey, 'N')
    px(g, 16, dy + 13, 'N'); px(g, 16, dy + 14, 'N')


def draw_beard(g, dy, last_row):
    """Moustache, then a beard that widens and tapers to a point.

    `last_row` clips it: seated in a boat the point disappears behind the rim,
    and drawing the full beard there would hang it through the hull.
    """
    rect(g, 13, dy + 15, 15, dy + 15, 'W')
    rect(g, 17, dy + 15, 19, dy + 15, 'W')
    px(g, 13, dy + 15, 'G'); px(g, 19, dy + 15, 'G')
    for (y, x0, x1) in [(16, 12, 20), (17, 11, 21), (18, 11, 21), (19, 11, 21),
                        (20, 12, 20), (21, 12, 20), (22, 13, 19), (23, 14, 18),
                        (24, 15, 17)]:
        if y > last_row:
            break
        rect(g, x0, dy + y, x1, dy + y, 'W')
        px(g, x0, dy + y, 'G'); px(g, x1, dy + y, 'G')
    px(g, 13, dy + 19, 'G'); px(g, 19, dy + 19, 'G')


def boat(oar=0, bob=0, eyes='open', cat=False, rider=True, rod=False):
    """The wizard seated in a rowboat, staff stowed upright against the rim."""
    g = blank()
    dy = 2 + bob
    rim = 22

    # Staff, shortened so it stops at the rim rather than spearing the hull.
    rect(g, 8, 9, 9, rim - 1, 'B')
    px(g, 8, 14, 'T')
    stamp(g, ORB, 6, 4, 'C')
    rect(g, 7, 5, 8, 6, 'A')

    if rider:
        draw_hat(g, dy)
        draw_face(g, dy, eyes)
        draw_beard(g, dy, 19)

    # Hull first; the oars go on top of it so the shafts stay visible where
    # they cross the rim, which is the part that reads as rowing.
    hull = [(rim, 4, 21), (rim + 1, 4, 21), (rim + 2, 5, 20),
            (rim + 3, 6, 19), (rim + 4, 8, 17), (rim + 5, 10, 15)]
    for (y, x0, x1) in hull:
        rect(g, x0, y, x1, y, 'B')
        px(g, x0, y, 'T'); px(g, x1, y, 'T')
    rect(g, 4, rim, 21, rim, 'T')          # rim plank, in shadow
    rect(g, 3, rim - 2, 4, rim - 1, 'B')   # prow and stern curl up
    rect(g, 21, rim - 2, 22, rim - 1, 'B')

    left = right = []
    left_blade = right_blade = (0, 0)
    if rod:
        # Rod out over the side, line dropping to the water.
        for i in range(9):
            px(g, 21 + i // 2, 14 - i, 'B')
        for y in range(14, 30):
            px(g, 25, y, 'M')
        px(g, 25, 29, 'A')
        rect(g, 19, dy + 16, 22, dy + 17, 'S')
    elif oar == 0:
        left = [(6, 19), (5, 19), (4, 18), (3, 18), (2, 17)]
        right = [(19, 19), (20, 19), (21, 18), (22, 18), (23, 17)]
        left_blade, right_blade = (0, 16), (24, 16)
    else:
        left = [(6, 21), (5, 22), (4, 22), (3, 23), (2, 23)]
        right = [(19, 21), (20, 22), (21, 22), (22, 23), (23, 23)]
        left_blade, right_blade = (0, 24), (24, 24)
    if not rod:
        for (ox, oy) in left + right:
            px(g, ox, oy, 'B')
        for (bx, by) in (left_blade, right_blade):
            rect(g, bx, by, bx + 1, by + 1, 'T')

    if cat:
        # Soot aboard, curled in the stern. Drawn before the hull so the
        # gunwale cuts her off at the waterline -- all you see of a cat in a
        # boat is the part above the rim, and layering a whole cat sprite on
        # top instead put her across his face.
        curl = [
            ".X.....X.",
            "XXXXXXXXX",
            "XXoXXXXXX",
            ".XXXXXXX.",
            ".XXXXXXX.",
        ]
        for j, row in enumerate(curl):
            for i, ch in enumerate(row):
                if ch == '.':
                    continue
                px(g, 2 + i, 16 + j, 'X' if ch == 'X' else 'o')
        # Rim her top edge, or a black cat against the dark inside of a boat
        # is just a gold dot floating in a shadow.
        for i in range(9):
            for j in range(3):
                if g[16 + j][2 + i] == 'X':
                    g[16 + j][2 + i] = 'x'
                    break

    outline(g)
    return g


def wizard(bob=0, eyes='open', hem=0, staffdy=0, armUp=False, orb='on'):
    g = blank()
    dy = bob
    sy = staffdy

    # --- staff: drawn first so hand and robe paint over it ---
    rect(g, 8, 8 + sy, 9, 28, 'B')
    px(g, 8, 13 + sy, 'T'); px(g, 8, 19 + sy, 'T'); px(g, 8, 25, 'T')
    stamp(g, ORB, 6, 3 + sy, 'C')
    if orb == 'bright':
        stamp(g, ORB, 6, 3 + sy, 'A')
        px(g, 6, 4 + sy, 'C'); px(g, 11, 4 + sy, 'C')
        px(g, 6, 7 + sy, 'C'); px(g, 11, 7 + sy, 'C')
    else:
        rect(g, 7, 4 + sy, 8, 5 + sy, 'A')

    draw_hat(g, dy)
    draw_face(g, dy, eyes)
    draw_beard(g, dy, 24)

    # --- robe: trapezoid filling in behind the beard ---
    hx0, hx1 = [(8, 24), (9, 24), (8, 23), (9, 23)][hem % 4]
    top_y, bot_y = dy + 16, 28
    for y in range(top_y, bot_y + 1):
        t = (y - top_y) / float(bot_y - top_y)
        x0 = int(round(12 - t * (12 - hx0)))
        x1 = int(round(20 + t * (hx1 - 20)))
        for x in range(x0, x1 + 1):
            if g[y][x] == '.':
                px(g, x, y, 'P')
        if g[y][x0] == 'P': px(g, x0, y, 'L')
        if g[y][x1] == 'P': px(g, x1, y, 'D')
    for y in range(dy + 23, 28):          # centre fold
        if g[y][16] == 'P': rect(g, 16, y, 17, y, 'D')
    rect(g, hx0, 28, hx1, 28, 'D')        # hem band, flat on the floor

    # --- sleeves and hands ---
    # Both sleeves stay clear of the face box (x 12..20, y 11..15); a raised
    # arm drawn any further in reads as a blindfold rather than a gesture.
    hy = dy + (16 if armUp else 19)
    rect(g, 10, hy - 1, 11, hy + 2, 'P')            # left sleeve
    px(g, 10, hy - 1, 'L'); px(g, 10, hy + 2, 'L')
    rect(g, 8, hy, 11, hy + 1, 'S')                 # hand on the staff
    rect(g, 8, hy + 1, 11, hy + 1, 'N')
    if armUp:
        rect(g, 21, dy + 12, 22, dy + 17, 'P')      # right sleeve, raised
        px(g, 22, dy + 12, 'D'); px(g, 22, dy + 17, 'D')
        rect(g, 21, dy + 9, 23, dy + 11, 'S')
        rect(g, 21, dy + 11, 23, dy + 11, 'N')
    else:
        rect(g, 20, dy + 18, 21, dy + 21, 'P')      # right sleeve, at rest
        px(g, 21, dy + 18, 'D'); px(g, 21, dy + 21, 'D')
        rect(g, 20, dy + 21, 22, dy + 22, 'S')
        rect(g, 20, dy + 22, 22, dy + 22, 'N')

    outline(g)
    return g

FRAMES = [
    ('idle1',  dict()),
    ('idle2',  dict(bob=1, hem=1, staffdy=1)),
    ('blink',  dict(eyes='closed')),
    ('walk1',  dict(hem=0)),
    ('walk2',  dict(bob=1, hem=2, staffdy=1)),
    ('walk3',  dict(hem=1)),
    ('walk4',  dict(bob=1, hem=3, staffdy=1)),
    ('cast1',  dict(staffdy=-2, armUp=True)),
    ('cast2',  dict(hem=1, staffdy=-3, armUp=True, orb='bright')),
    ('cast3',  dict(bob=1, staffdy=-3, armUp=True, orb='bright', eyes='wink')),
    ('sleep1', dict(bob=1, hem=1, eyes='closed', staffdy=1)),
    ('sleep2', dict(bob=1, hem=2, eyes='closed', staffdy=2)),
    ('held1',  dict(hem=2, armUp=True)),
    ('held2',  dict(bob=1, hem=3, armUp=True)),
]

DEATH_FRAMES = [
    ('death1', dict()),
    ('death2', dict(bob=1)),
    ('death_pet1', dict(pet=True)),
    ('death_pet2', dict(pet=True, bob=1)),
]

PORTAL_FRAMES = [
    ('portal1', dict(open_amount=0.18, swirl=0.0)),
    ('portal2', dict(open_amount=0.45, swirl=1.1)),
    ('portal3', dict(open_amount=0.75, swirl=2.2)),
    ('portal4', dict(open_amount=1.0, swirl=3.3)),
    ('portal5', dict(open_amount=1.0, swirl=4.9)),
    ('portal6', dict(open_amount=1.0, swirl=6.5)),
]

BOAT_FRAMES = [
    ('row1', dict(oar=0)),
    ('row2', dict(oar=1, bob=1)),
    ('row3', dict(oar=1)),
    ('row4', dict(oar=0, bob=1)),
    ('rowcat1', dict(oar=0, cat=True)),
    ('rowcat2', dict(oar=1, bob=1, cat=True)),
    ('rowcat3', dict(oar=1, cat=True)),
    ('rowcat4', dict(oar=0, bob=1, cat=True)),
    ('rowrod1', dict(oar=1, rod=True)),
    ('rowrod2', dict(oar=1, bob=1, rod=True)),
    ('boatempty', dict(oar=1, rider=False)),
]

WATER_FRAMES = [
    ('tent1', dict(rise=0.25)),
    ('tent2', dict(rise=0.6, curl=0.3)),
    ('tent3', dict(rise=1.0, curl=0.7)),
    ('tent4', dict(rise=1.0, curl=-0.5)),
    ('tent5', dict(rise=0.55, curl=-0.2)),
]

BED_FRAMES = [
    ('bed1', dict(bob=0)),
    ('bed2', dict(bob=1)),
    ('bedalone1', dict(bob=0, cat=False)),
    ('bedalone2', dict(bob=1, cat=False)),
]

SWIM_FRAMES = [
    ('swim1', dict(phase=0)),
    ('swim2', dict(phase=1, bob=1)),
]

def to_img(g, scale):
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    p = im.load()
    for y in range(H):
        for x in range(W):
            c = g[y][x]
            if c != '.':
                p[x, y] = PALETTE[c] + (255,)
    return im.resize((W * scale, H * scale), Image.NEAREST)

# Items he can pick up and use. Drawn on their own 11x11 grid, since they are
# shown held up beside him rather than composed into his body.
IW = IH = 11

ITEMS = {
    "lantern": [
        "....MMM....",
        ".....M.....",
        "...MMMMM...",
        "...M...M...",
        "...M.Y.M...",
        "...MYYYM...",
        "...MYYYM...",
        "...M.Y.M...",
        "...MMMMM...",
        "....M.M....",
        "...........",
    ],
    "fish": [
        "...........",
        "...........",
        "........M..",
        "..MMM..MM..",
        ".MFFFM.MMM.",
        "MFFEFFFMMM.",
        ".MFFFM.MMM.",
        "..MMM..MM..",
        "........M..",
        "...........",
        "...........",
    ],
    "crystal": [
        "...........",
        ".....A.....",
        "....ACA....",
        "....ACA....",
        "...ACCCA...",
        "...ACCCA...",
        "...ACCCA...",
        "...ACCCA...",
        "....ACA....",
        ".....A.....",
        "...........",
    ],
    "book": [
        "...........",
        "...........",
        "..QQQ.QQQ..",
        ".QQQQQQQQQ.",
        "QQQQQ.QQQQQ",
        "QQQQQ.QQQQQ",
        "QQQQQ.QQQQQ",
        ".PPPPPPPPP.",
        "..PPPPPPP..",
        "...........",
        "...........",
    ],
    "key": [
        "...........",
        "...YYY.....",
        "..Y...Y....",
        "..Y...Y....",
        "...YYY.....",
        "....Y......",
        "....Y......",
        "....YY.....",
        "....Y.Y....",
        "....YY.....",
        "...........",
    ],
    "mushroom": [
        "...........",
        "...RRRRR...",
        "..RRQRRQR..",
        ".RRRRRRRRR.",
        ".RQRRRRRQR.",
        "..RRRRRRR..",
        "....WWW....",
        "....WWW....",
        "...WWWWW...",
        "...........",
        "...........",
    ],
}


def item_grid(name):
    """Item pixels with the same auto-outline the wizard gets."""
    rows = ITEMS[name]
    g = [['.'] * IW for _ in range(IH)]
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != '.':
                g[y][x] = ch
    solid = [[g[y][x] != '.' for x in range(IW)] for y in range(IH)]
    for y in range(IH):
        for x in range(IW):
            if solid[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < IW and 0 <= ny < IH and solid[ny][nx]:
                    g[y][x] = 'K'
                    break
    return g





def portal(open_amount=1.0, swirl=0.0):
    """An arcane doorway: a bright ring around a spiral of deeper purple.

    Sized on the wizard's own grid so it lines up with him when he steps
    through. `open_amount` runs 0 to 1 as it irises open from a vertical
    slit; `swirl` rotates the vortex inside it.
    """
    g = blank()
    cx, cy = 12.5, 16.0
    ry = 13.0
    rx = max(0.6, 6.5 * open_amount)

    for y in range(H):
        for x in range(W):
            dx, dy = (x - cx) / rx, (y - cy) / ry
            r = math.sqrt(dx * dx + dy * dy)
            if r > 1.0:
                continue
            if r > 0.82:
                # The rim: brightest where the ring is widest.
                g[y][x] = 'A' if abs(dy) < 0.72 else 'C'
                continue
            angle = math.atan2(dy, dx)
            # A spiral: angle advanced by radius, so the arms curl inward.
            v = math.sin(angle * 2.0 + r * 7.0 - swirl)
            if v > 0.55:
                g[y][x] = 'C'
            elif v > 0.05:
                g[y][x] = 'P'
            elif v > -0.5:
                g[y][x] = 'D'
            else:
                g[y][x] = 'K'

    outline(g)
    return g


# A black cat, drawn on her own small grid. Pure black would disappear into a
# dark wallpaper, so she is a very dark purple carrying a rim light along her
# back -- the same trick the village art uses to keep silhouettes readable.
CW, CH = 15, 12

CATS = {
    "cat_walk1": [
        "...............",
        ".X.........X.X.",
        ".XX.......XXXXX",
        "..X.......XoXXX",
        "..XXXXXXXXXXXXX",
        "..XXXXXXXXXXXX.",
        "..XXXXXXXXXXX..",
        "...X..X..X..X..",
        "...X..X..X..X..",
        "...............",
        "...............",
        "...............",
    ],
    "cat_walk2": [
        "...............",
        "..XX.......X.X.",
        ".XX.......XXXXX",
        ".X........XoXXX",
        "..XXXXXXXXXXXXX",
        "..XXXXXXXXXXXX.",
        "..XXXXXXXXXXX..",
        "..XX...XX..XX..",
        ".X..X.X..X.X...",
        "...............",
        "...............",
        "...............",
    ],
    "cat_sit": [
        "...............",
        ".....X...X.....",
        "....XXX.XXX....",
        "....XXXXXXX....",
        "....XoXXXoX....",
        "....XXXXXXX....",
        ".....XXXXX.....",
        "....XXXXXXX....",
        "...XXXXXXXX.X..",
        "...XXXXXXXX.XX.",
        "..XXXXXXXXXX.X.",
        "..XXXXXXXXXX...",
    ],
    "cat_curl": [
        "...............",
        "...............",
        ".....XXXXX.....",
        "...XXXXXXXXX...",
        "..XXXXXXXXXXX..",
        ".XXXXXXXXXXXXX.",
        ".XXoXXXXXXXXXX.",
        ".XXXXXXXXXXXXX.",
        "..XXXXXXXXXXX..",
        "...XXXXXXXXX.X.",
        "....XXXXXXX.XX.",
        "...............",
    ],
}


def cat_grid(name):
    """Cat pixels with the same auto-outline everything else gets."""
    rows = CATS[name]
    g = [['.'] * CW for _ in range(CH)]
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != '.':
                g[y][x] = ch
    # Catch the light on the topmost pixel of each column. Painting the
    # highlight as an interior row instead reads as a stripe down her back
    # rather than as a rim, which is what the first two attempts looked like.
    for x in range(CW):
        for y in range(CH):
            if g[y][x] == 'X':
                g[y][x] = 'x'
                break

    solid = [[g[y][x] != '.' for x in range(CW)] for y in range(CH)]
    for y in range(CH):
        for x in range(CW):
            if solid[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < CW and 0 <= ny < CH and solid[ny][nx]:
                    g[y][x] = 'K'
                    break
    return g


def death(bob=0, pet=False, glow=True):
    """Death: a hood with two blue lights in it, and a scythe.

    Drawn on the wizard's own 26x30 grid so the two of them stand together at
    the same scale. `pet` drops his near arm down to scratch the cat's ears.
    """
    g = blank()
    dy = bob

    # --- scythe: long haft, blade sweeping off the top ---
    rect(g, 7, 4, 8, 29, 'B')
    px(g, 7, 12, 'T'); px(g, 7, 20, 'T')
    for (bx, by) in [(9, 3), (10, 2), (11, 2), (12, 2), (13, 3),
                     (14, 4), (15, 5), (15, 6)]:
        px(g, bx, by, 'M')
        px(g, bx, by + 1, 'M')
    px(g, 9, 4, 'M'); px(g, 10, 3, 'M')

    # --- hood: a cowl, widest at the shoulders ---
    cowl = [(2, 14, 18), (3, 13, 19), (4, 12, 20), (5, 12, 20),
            (6, 11, 21), (7, 11, 21), (8, 11, 21), (9, 10, 22),
            (10, 10, 22), (11, 10, 22), (12, 10, 22), (13, 10, 22)]
    for (y, x0, x1) in cowl:
        rect(g, x0, dy + y, x1, dy + y, '2')
        px(g, x0, dy + y, '3')

    # --- the dark inside the hood, and the skull in it ---
    rect(g, 13, dy + 6, 19, dy + 13, '2')
    rect(g, 14, dy + 7, 18, dy + 11, '1')     # cranium
    rect(g, 15, dy + 12, 17, dy + 13, '1')    # jaw
    px(g, 14, dy + 13, '1'); px(g, 18, dy + 13, '1')
    rect(g, 15, dy + 9, 15, dy + 10, '2')     # eye sockets
    rect(g, 17, dy + 9, 17, dy + 10, '2')
    if glow:
        px(g, 15, dy + 9, '4')
        px(g, 17, dy + 9, '4')
    px(g, 16, dy + 11, '2')                   # nasal cavity
    px(g, 15, dy + 13, '2'); px(g, 17, dy + 13, '2')   # teeth gaps

    # --- robe, falling straight and wide ---
    top_y, bot_y = dy + 13, 29
    for y in range(top_y, bot_y + 1):
        t = (y - top_y) / float(bot_y - top_y)
        x0 = int(round(10 - t * 5))
        x1 = int(round(22 + t * 3))
        for x in range(x0, x1 + 1):
            if g[y][x] == '.':
                px(g, x, y, '2')
        px(g, x0, y, '3')
    rect(g, 5, 29, 25, 29, '3')

    # --- hands ---
    if pet:
        # Reaching down for the cat. The hand has to clear the robe entirely:
        # a bone hand held against that much black is invisible at this size.
        rect(g, 9, dy + 17, 11, dy + 21, '3')
        rect(g, 6, dy + 21, 10, dy + 23, '3')
        rect(g, 4, dy + 23, 7, dy + 26, '1')
        px(g, 4, dy + 26, '2'); px(g, 6, dy + 26, '2')
    else:
        rect(g, 8, dy + 16, 10, dy + 18, '2')
        rect(g, 7, dy + 17, 9, dy + 18, '1')

    outline(g)
    return g


def tentacle(rise=1.0, curl=0.0):
    """Something in the lake, minding its own business.

    Rises out of the water on a tapering curve; `curl` sways the tip.
    """
    g = blank()
    base_y = 29
    top_y = int(round(base_y - 24 * rise))
    for y in range(base_y, top_y - 1, -1):
        t = (base_y - y) / max(1.0, float(base_y - top_y))
        # Straight at the waterline, leaning further over as it goes up.
        cx = 13 + math.sin(t * 2.4 + curl) * 5.0 * t
        half = max(0.5, 3.2 * (1.0 - t * 0.75))
        rect(g, cx - half, y, cx + half, y, '5')
        px(g, cx - half, y, '6')
        if y % 3 == 0 and t > 0.15:
            px(g, cx + half - 1, y, '6')
    # A curl at the very tip.
    if rise > 0.55:
        tipx = 13 + math.sin(2.4 + curl) * 5.0
        px(g, tipx + 1, top_y, '5')
        px(g, tipx + 2, top_y + 1, '5')
    outline(g)
    return g


def swimmer(phase=0, bob=0):
    """Landis in the lake, hat and all, having parted company with his boat."""
    g = blank()
    dy = 8 + bob
    draw_hat(g, dy)
    draw_face(g, dy, 'open')
    draw_beard(g, dy, 17)

    # Arms out of the water, one higher than the other.
    if phase == 0:
        rect(g, 5, dy + 12, 8, dy + 13, 'S'); rect(g, 5, dy + 13, 8, dy + 13, 'N')
        rect(g, 22, dy + 15, 24, dy + 16, 'S')
    else:
        rect(g, 5, dy + 15, 8, dy + 16, 'S')
        rect(g, 22, dy + 12, 24, dy + 13, 'S'); rect(g, 22, dy + 13, 24, dy + 13, 'N')

    # Waterline: everything below it is lake, so cut him off and foam it.
    line = dy + 18
    for y in range(line, H):
        for x in range(W):
            g[y][x] = '.'
    for x in range(3, 23):
        if (x + phase * 3) % 4 != 0:
            px(g, x, line, 'A')
        if (x + phase * 2) % 5 == 0:
            px(g, x, line - 1, 'A')
    outline(g)
    return g


def bedroll(bob=0, cat=True):
    """Landis turned in for the night, hat over his eyes, cat on his chest."""
    g = blank()
    base = 28 - bob

    # Mat, and the pack he uses as a pillow.
    rect(g, 2, base - 1, 24, base, 'D')
    rect(g, 20, base - 5, 24, base - 1, 'B')
    px(g, 20, base - 5, 'T'); px(g, 24, base - 5, 'T')

    # Blanket, humped over him and tucked at the far end.
    for (y, x0, x1) in [(base - 2, 4, 21), (base - 3, 6, 20), (base - 4, 9, 19)]:
        rect(g, x0, y, x1, y, 'P')
        px(g, x0, y, 'L')
        px(g, x1, y, 'D')

    # His head, at the near end, with the hat pulled down over his face.
    rect(g, 4, base - 6, 9, base - 3, 'S')
    rect(g, 4, base - 4, 9, base - 2, 'W')            # beard spilling out
    px(g, 5, base - 4, 'G'); px(g, 8, base - 4, 'G')
    # Hat tipped down over his eyes: a proper cone, or he reads as a loose
    # beard lying in a blanket.
    brim = base - 7
    rect(g, 3, brim, 11, brim, 'P')
    rect(g, 3, brim + 1, 11, brim + 1, 'D')
    for i in range(5):
        rect(g, 4 + i, brim - 1 - i, 10 - i, brim - 1 - i, 'P')
        px(g, 10 - i, brim - 1 - i, 'D')
    px(g, 7, brim - 3, 'Y')

    # Staff laid down alongside him.
    rect(g, 2, base - 8, 3, base - 8, 'B')
    stamp(g, ORB, 0, base - 11, 'C')

    if cat:
        # Soot, curled on the blanket. She sleeps on him, obviously.
        curl = [
            "..XXXXX..",
            ".XXXXXXX.",
            "XXoXXXXXX",
            ".XXXXXXX.",
        ]
        for j, row in enumerate(curl):
            for i, ch in enumerate(row):
                if ch == '.':
                    continue
                px(g, 11 + i, base - 8 + j, 'X' if ch == 'X' else 'o')
        for i in range(9):
            if g[base - 8][11 + i] == 'X':
                g[base - 8][11 + i] = 'x'

    outline(g)
    return g


FIRE = {
    "fire1": [
        "...........",
        "...........",
        ".....Y.....",
        "....YRY....",
        "...YRRRY...",
        "...YRRRY...",
        "..YRRRRRY..",
        "..BBTTTBB..",
        ".BBBTTTBBB.",
        "...........",
        "...........",
    ],
    "fire2": [
        "...........",
        ".....Y.....",
        "....YYY....",
        "....YRY....",
        "...YRRRY...",
        "..YRRRRRY..",
        "..YRRRRRY..",
        "..BBTTTBB..",
        ".BBBTTTBBB.",
        "...........",
        "...........",
    ],
    "fire3": [
        "...........",
        "...........",
        "....YY.....",
        "...YRRY....",
        "...YRRY....",
        "..YRRRRY...",
        "..YRRRRRY..",
        "..BBTTTBB..",
        ".BBBTTTBBB.",
        "...........",
        "...........",
    ],
}


def fire_grid(name):
    rows = FIRE[name]
    g = [['.'] * IW for _ in range(IH)]
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch != '.':
                g[y][x] = ch
    solid = [[g[y][x] != '.' for x in range(IW)] for y in range(IH)]
    for y in range(IH):
        for x in range(IW):
            if solid[y][x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < IW and 0 <= ny < IH and solid[ny][nx]:
                    g[y][x] = 'K'
                    break
    return g


# The plugin root is the repository root, one level up from tools/.
PLUGIN = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def preview(scale=6, cols=7):
    """A cast sheet: everyone and everything, at one scale."""
    big = [
        wizard(),
        boat(oar=1, cat=True),
        bedroll(),
        death(pet=True),
        portal(open_amount=1.0, swirl=3.3),
        tentacle(rise=1.0, curl=0.7),
        swimmer(0),
    ]
    small = ([cat_grid(n) for n in ("cat_sit", "cat_walk1", "cat_curl")]
             + [fire_grid("fire2")]
             + [item_grid(n) for n in sorted(ITEMS)])

    pad = 6
    top_h = H * scale
    bot_h = IH * scale
    width = max(len(big) * (W * scale + pad),
                len(small) * (CW * scale + pad))
    sheet = Image.new("RGBA", (width, top_h + bot_h + pad * 3), (26, 22, 42, 255))

    for i, g in enumerate(big):
        im = to_img(g, scale)
        sheet.paste(im, (i * (W * scale + pad), 0), im)

    x = 0
    for g in small:
        gw, gh = len(g[0]), len(g)
        im = Image.new("RGBA", (gw, gh), (0, 0, 0, 0))
        px_ = im.load()
        for y in range(gh):
            for xx in range(gw):
                if g[y][xx] != '.':
                    px_[xx, y] = PALETTE[g[y][xx]] + (255,)
        im = im.resize((gw * scale, gh * scale), Image.NEAREST)
        sheet.paste(im, (x, top_h + pad * 2), im)
        x += gw * scale + pad

    return sheet


def bottom_pad(rows):
    """Empty rows at the foot of a frame.

    Frames are all drawn on one grid, so a pose that does not reach the bottom
    of it leaves a gap under the sprite. Positioning by the grid rather than by
    the content makes that gap look like hovering -- and because the gap
    differs between poses, it makes the cat bob as she starts and stops.
    """
    pad = 0
    for row in reversed(rows):
        if set(row) == {'.'}:
            pad += 1
        else:
            break
    return pad


def emit_js(path):
    order = ([n for n, _ in FRAMES] + [n for n, _ in BOAT_FRAMES]
             + [n for n, _ in PORTAL_FRAMES] + [n for n, _ in DEATH_FRAMES]
             + [n for n, _ in WATER_FRAMES] + [n for n, _ in SWIM_FRAMES]
             + [n for n, _ in BED_FRAMES])
    out = []
    out.append("// Generated by branding/wizard.py -- edit that, not this file.")
    out.append(".pragma library")
    out.append("")
    out.append("var W = %d" % W)
    out.append("var H = %d" % H)
    out.append("")
    out.append("var PALETTE = {")
    out.append(",\n".join('  "%s": "#%02x%02x%02x"' % (k, r, g, b) for k, (r, g, b) in PALETTE.items()))
    out.append("}")
    out.append("")
    out.append("var IW = %d" % IW)
    out.append("var IH = %d" % IH)
    out.append("")
    out.append("var ITEMS = {")
    out.append(",\n".join(
        '  "%s": [\n%s\n  ]' % (name, ",\n".join('    "%s"' % ''.join(r) for r in item_grid(name)))
        for name in sorted(ITEMS)))
    out.append("}")
    out.append("")
    out.append("var ITEM_NAMES = %s" % str(sorted(ITEMS)).replace("'", '"'))
    out.append("")
    out.append("var CW = %d" % CW)
    out.append("var CH = %d" % CH)
    out.append("")
    out.append("var CATS = {")
    out.append(",\n".join(
        '  "%s": [\n%s\n  ]' % (name, ",\n".join('    "%s"' % ''.join(r) for r in cat_grid(name)))
        for name in sorted(CATS)))
    out.append("}")
    out.append("")
    out.append("var CAT_WALK = [\"cat_walk1\", \"cat_walk2\"]")
    out.append("")
    out.append("var FRAME_PAD = {")
    pads = []
    for name, kw in (FRAMES + BOAT_FRAMES + PORTAL_FRAMES + DEATH_FRAMES
                     + WATER_FRAMES + SWIM_FRAMES + BED_FRAMES):
        if name.startswith("row") or name.startswith("boat"):
            g = boat(**kw)
        elif name.startswith("portal"):
            g = portal(**kw)
        elif name.startswith("death"):
            g = death(**kw)
        elif name.startswith("tent"):
            g = tentacle(**kw)
        elif name.startswith("swim"):
            g = swimmer(**kw)
        elif name.startswith("bed"):
            g = bedroll(**kw)
        else:
            g = wizard(**kw)
        pads.append('  "%s": %d' % (name, bottom_pad([''.join(r) for r in g])))
    out.append(",\n".join(pads))
    out.append("}")
    out.append("")
    out.append("var CAT_PAD = {")
    out.append(",\n".join('  "%s": %d' % (n, bottom_pad([''.join(r) for r in cat_grid(n)]))
                           for n in sorted(CATS)))
    out.append("}")
    out.append("")
    out.append("var FRAMES = {")
    parts = []
    for name, kw in (FRAMES + BOAT_FRAMES + PORTAL_FRAMES + DEATH_FRAMES
                     + WATER_FRAMES + SWIM_FRAMES + BED_FRAMES):
        if name.startswith("row") or name.startswith("boat"):
            g = boat(**kw)
        elif name.startswith("portal"):
            g = portal(**kw)
        elif name.startswith("death"):
            g = death(**kw)
        elif name.startswith("tent"):
            g = tentacle(**kw)
        elif name.startswith("swim"):
            g = swimmer(**kw)
        elif name.startswith("bed"):
            g = bedroll(**kw)
        else:
            g = wizard(**kw)
        rows = ",\n".join('    "%s"' % ''.join(r) for r in g)
        parts.append('  "%s": [\n%s\n  ]' % (name, rows))
    out.append(",\n".join(parts))
    out.append("}")
    out.append("")
    out.append("var WALK = %s" % str([n for n in order if n.startswith("walk")]).replace("'", '"'))
    out.append("var IDLE = %s" % str([n for n in order if n.startswith("idle")]).replace("'", '"'))
    out.append("var CAST = %s" % str([n for n in order if n.startswith("cast")]).replace("'", '"'))
    out.append("var SLEEP = %s" % str([n for n in order if n.startswith("sleep")]).replace("'", '"'))
    out.append("var HELD = %s" % str([n for n in order if n.startswith("held")]).replace("'", '"'))
    out.append("var ROW = [\"row1\", \"row2\", \"row3\", \"row4\"]")
    out.append("var ROW_CAT = [\"rowcat1\", \"rowcat2\", \"rowcat3\", \"rowcat4\"]")
    out.append("var PORTAL = %s" % str([n for n, _ in PORTAL_FRAMES]).replace("'", '"'))
    out.append("var DEATH = [\"death1\", \"death2\"]")
    out.append("var DEATH_PET = [\"death_pet1\", \"death_pet2\"]")
    out.append("var TENTACLE = %s" % str([n for n, _ in WATER_FRAMES]).replace("'", '"'))
    out.append("var SWIM = %s" % str([n for n, _ in SWIM_FRAMES]).replace("'", '"'))
    out.append("var ROW_ROD = [\"rowrod1\", \"rowrod2\"]")
    out.append("var BED = [\"bed1\", \"bed2\"]")
    out.append("var BED_ALONE = [\"bedalone1\", \"bedalone2\"]")
    out.append("")
    out.append("var FIRE = {")
    out.append(",\n".join(
        '  "%s": [\n%s\n  ]' % (n, ",\n".join('    "%s"' % ''.join(r) for r in fire_grid(n)))
        for n in sorted(FIRE)))
    out.append("}")
    out.append("")
    out.append("var FIRE_NAMES = %s" % str(sorted(FIRE)).replace("'", '"'))
    out.append("")
    out.append("var FIRE_PAD = {")
    out.append(",\n".join('  "%s": %d' % (n, bottom_pad([''.join(r) for r in fire_grid(n)]))
                           for n in sorted(FIRE)))
    out.append("}")
    out.append("")
    open(path, "w").write("\n".join(out) + "\n")


if __name__ == "__main__":
    import sys
    if "--preview" in sys.argv:
        out = os.path.join(PLUGIN, "sprite-sheet.png")
        preview().save(out)
        print("wrote " + out)
    emit_js(PLUGIN + "/Sprites.js")
    print("wrote " + PLUGIN + "/Sprites.js")
