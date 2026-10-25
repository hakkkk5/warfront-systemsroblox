"""
The Cannibal Family - farmhouse interiors.

Dresses the rooms of the farmhouse (server House.luau) in place, around the
house origin (pivot "origin"): striped wallpaper peeling off in strips, wood
wainscot under the chair rail, tiles in the kitchen, bathroom and slaughter
room, dark panelling in the trophy room, crown moulding, a carpet runner and
newel posts on the stairs, and blood - a drag trail down the hall into the
slaughter room, handprints, spatter. One mesh per floor:

    FarmhouseInteriorGround   FarmhouseInteriorUpper

It all sits a few hundredths of a stud off the server's walls and adds no
collisions; the room layout below mirrors House.luau (walls at x = +-5 and
z = 0 inside a 64 x 48 shell, 1 stud thick), so keep the two in step.

    blender -b --factory-startup -P tools/blender/build_interiors.py
"""

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_props as bp  # noqa: E402
from build_props import PALETTE, Prop, srgb  # noqa: E402
from build_buildings import Face, T, RY, RZ, part, ball, lathe_post  # noqa: E402

STYLES = {
    # wallpaper: two stripe colours
    "living": ((58, 74, 58), (72, 88, 66)),
    "dining": ((92, 38, 36), (110, 50, 46)),
    "kitchen": ((184, 168, 128), (168, 152, 114)),
    "hall": ((88, 66, 50), (102, 78, 58)),
    "master": ((68, 82, 98), (82, 96, 110)),
    "kids": ((150, 104, 110), (168, 126, 128)),
}
for _name, (_a, _b) in STYLES.items():
    PALETTE["paper_" + _name + "A"] = dict(color=srgb(*_a), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave")
    PALETTE["paper_" + _name + "B"] = dict(color=srgb(*_b), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave_blood")
PALETTE.update({
    "plaster_raw": dict(color=srgb(150, 140, 122), roblox="Plaster", rough=1.0, metal=0.0, pattern="dirty"),
    "tile": dict(color=srgb(196, 192, 176), roblox="CeramicTiles", rough=0.3, metal=0.0, pattern="blood"),
    "tile_kitchen": dict(color=srgb(176, 196, 170), roblox="CeramicTiles", rough=0.3, metal=0.0, pattern="dirty"),
    "panel_dark": dict(color=srgb(52, 36, 26), roblox="Wood", rough=0.7, metal=0.0, pattern="grain"),
    "carpet": dict(color=srgb(88, 22, 20), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave_blood"),
})


def opened(a, y, openings, pad=0.05):
    for (c, w, b, t) in openings:
        if c - w / 2 - pad < a < c + w / 2 + pad and b - pad < y < t + pad:
            return True
    return False


def vertical_runs(a, y0, y1, openings):
    """The parts of the vertical line at a, from y0 to y1, outside openings."""
    runs = [(y0, y1)]
    for (c, w, b, t) in openings:
        if c - w / 2 - 0.3 < a < c + w / 2 + 0.3:
            nxt = []
            for r0, r1 in runs:
                if t <= r0 or b >= r1:
                    nxt.append((r0, r1))
                else:
                    if b > r0:
                        nxt.append((r0, b))
                    if t < r1:
                        nxt.append((t, r1))
            runs = nxt
    return [(r0, r1) for r0, r1 in runs if r1 - r0 > 0.15]


def wallpaper(p, face, a0, a1, y0, y1, style, openings, rng, width=0.55):
    """Stripes of two papers; now and then one torn short with its end curling."""
    a = a0 + width / 2
    i = 0
    while a < a1 - 0.05:
        mat = "paper_" + style + ("A" if i % 2 == 0 else "B")
        for r0, r1 in vertical_runs(a, y0, y1, openings):
            top = r1
            if rng.random() < 0.07 and r1 - r0 > 2.5:
                top = r1 - rng.uniform(1.0, min(4.0, r1 - r0 - 1.0))
                # the torn piece hanging off the wall
                face.box(p, mat, width - 0.04, 0.9, 0.03, a, top - 0.3, 0.12)
            face.box(p, mat, width - 0.03, top - r0, 0.03, a, (r0 + top) / 2, 0.03)
        a += width
        i += 1


def wainscot(p, face, a0, a1, y0, y1, openings, mat="wood_old"):
    a = a0 + 0.25
    while a < a1 - 0.05:
        for r0, r1 in vertical_runs(a, y0, y1, openings):
            face.box(p, mat, 0.46, r1 - r0, 0.06 if int(a * 2) % 2 == 0 else 0.08, a, (r0 + r1) / 2, 0.03)
        a += 0.5
    face.box(p, "trim", a1 - a0, 0.16, 0.14, (a0 + a1) / 2, y1 + 0.08, 0.03)


def tiles(p, face, a0, a1, y0, y1, openings, mat, rng, size=0.9):
    y = y0 + size / 2
    while y < y1:
        a = a0 + size / 2
        while a < a1:
            if not opened(a, y, openings):
                if rng.random() > 0.04:  # a few fallen off
                    face.box(p, mat, size - 0.06, size - 0.06, 0.05, a, y, 0.03)
            a += size
        y += size


def crown(p, face, a0, a1, y_top):
    face.box(p, "trim", a1 - a0, 0.38, 0.22, (a0 + a1) / 2, y_top - 0.19, 0.0)
    face.box(p, "trim", a1 - a0, 0.12, 0.34, (a0 + a1) / 2, y_top - 0.06, 0.0)


def splat(p, face, a, y, rng, size=0.5, drips=True):
    for _ in range(rng.randint(3, 6)):
        da, dy = rng.uniform(-size, size), rng.uniform(-size, size) * 0.7
        face.box(p, "blood", rng.uniform(0.12, 0.4) * size * 2, rng.uniform(0.1, 0.3) * size * 2, 0.02, a + da, y + dy, 0.06)
    if drips:
        for _ in range(rng.randint(1, 3)):
            ln = rng.uniform(0.6, 2.2)
            face.box(p, "blood", 0.06, ln, 0.02, a + rng.uniform(-size, size) * 0.6, y - ln / 2, 0.06)


def handprint(p, face, a, y, tilt):
    face.box(p, "blood", 0.36, 0.42, 0.02, a, y, 0.06)
    for k in range(4):
        part(p, "blood", (0.07, 0.3, 0.02), face.cf(a - 0.15 + k * 0.1, y + 0.32, 0.07) @ RZ(tilt + (k - 1.5) * 0.12))


def floor_smear(p, x, z, y, length, width, yaw, rng):
    part(p, "blood", (width, 0.02, length), T(x, y + 0.025, z) @ RY(yaw))
    for _ in range(4):
        part(p, "blood", (rng.uniform(0.2, 0.6), 0.02, rng.uniform(0.2, 0.6)),
             T(x + rng.uniform(-1, 1), y + 0.03, z + rng.uniform(-length / 2, length / 2)))




# A room: inner bounds and, per wall, its openings (centre, width, bottom, top)
# measured from the room's floor. Walls: n = the -Z side, s = +Z, w = -X, e = +X.
def room(p, rng, x0, x1, z0, z1, y0, h, style, openings, lower=None, lower_top=3.3, crown_on=True):
    walls = {
        "n": (Face("z", z0, 1), x0, x1),
        "s": (Face("z", z1, -1), x0, x1),
        "w": (Face("x", x0, 1), z0, z1),
        "e": (Face("x", x1, -1), z0, z1),
    }
    for side, (face, a0, a1) in walls.items():
        ops = [(c, w, y0 + b, y0 + t) for (c, w, b, t) in openings.get(side, [])]
        bottom = y0 + 0.62
        if lower == "wainscot":
            wainscot(p, face, a0, a1, bottom, y0 + lower_top, ops)
            paper_from = y0 + lower_top + 0.16
        elif lower in ("tile", "tile_kitchen"):
            tiles(p, face, a0, a1, bottom, y0 + lower_top, ops, lower, rng)
            paper_from = y0 + lower_top
        elif lower == "panel":
            wainscot(p, face, a0, a1, bottom, y0 + h - 0.5, ops, mat="panel_dark")
            paper_from = None
        else:
            paper_from = bottom
        if style and paper_from is not None:
            wallpaper(p, face, a0, a1, paper_from, y0 + h - 0.4, style, ops, rng)
        elif style is None and paper_from is not None and lower is not None:
            face.box(p, "plaster_raw", a1 - a0, y0 + h - 0.4 - paper_from, 0.02, (a0 + a1) / 2, (paper_from + y0 + h - 0.4) / 2, 0.02)
        if crown_on:
            crown(p, face, a0, a1, y0 + h)
    return walls


def win(c, y0=0.0):
    return (c, 4.6, 3.8 + y0, 8.7 + y0)


def door(c, w=5.4, top=9.2):
    return (c, w, -1.0, top)


def build_ground():
    p = Prop("FarmhouseInteriorGround", pivot="origin")
    rng = random.Random(41)
    h = 12.0
    room(p, rng, -31.5, -5.5, -23.5, -0.5, 0, h, "living", {
        "n": [win(-20), win(-12)], "s": [door(-18, top=9.7)], "w": [win(-6), (-6, 9.0, -1, 8.6)], "e": [door(-11.5)],
    }, lower="wainscot")
    room(p, rng, 5.5, 31.5, -23.5, -0.5, 0, h, "dining", {
        "n": [win(12), win(22)], "e": [win(-12)], "w": [door(-11.5)],
    }, lower="wainscot")
    room(p, rng, -31.5, -5.5, 0.5, 23.5, 0, h, "kitchen", {
        "n": [door(-18, top=9.7)], "s": [win(-20)], "w": [win(12)], "e": [door(4.5)],
    }, lower="tile_kitchen", lower_top=4.6)
    slaughter = room(p, rng, 5.5, 31.5, 0.5, 23.5, 0, h, None, {
        "s": [win(20)], "e": [win(12)], "w": [door(16.5)],
    }, lower="tile", lower_top=6.2)
    hall = room(p, rng, -4.5, 4.5, -23.5, 23.5, 0, h, "hall", {
        "n": [(0, 5.4, -1, 9.3)], "s": [(2.5, 5.0, -1, 9.3)],
        "w": [door(-11.5), door(4.5), (15, 15, -1, 14)], "e": [door(-11.5), door(16.5)],
    }, lower="wainscot")
    # the slaughter room: spatter up the walls, pools and a drain gutter
    for side, (face, a0, a1) in slaughter.items():
        for _ in range(5):
            splat(p, face, rng.uniform(a0 + 1, a1 - 1), rng.uniform(1.5, 7.5), rng, size=rng.uniform(0.4, 0.9))
    for _ in range(5):
        part(p, "blood", (rng.uniform(1.5, 3.5), 0.02, rng.uniform(1.2, 3)), T(rng.uniform(9, 28), 0.03, rng.uniform(4, 20)) @ RY(rng.uniform(0, 3)))
    # a drag trail from the front door down the hall to the slaughter room door
    z = -20.0
    while z < 15.5:
        x = math.sin(z * 0.35) * 0.8 + (z + 20) / 35.5 * 2.6
        floor_smear(p, x, z, 0.0, 1.6, rng.uniform(0.6, 1.0), rng.uniform(-0.2, 0.2), rng)
        z += 1.4
    face_e = hall["e"][0]
    handprint(p, face_e, 13.5, 4.2, 0.2)
    handprint(p, face_e, 14.6, 3.6, -0.3)
    handprint(p, hall["w"][0], -14.0, 4.6, 0.1)
    # the stairs: a runner up the treads and risers, newel posts
    run = 14 / 13
    for i in range(1, 14):
        z_near = 22 - i * run
        part(p, "carpet", (2.8, 0.05, run), T(-2.5, i + 0.025, z_near + run / 2))
        part(p, "carpet", (2.8, 1.0, 0.05), T(-2.5, i - 0.5, z_near + run + 0.025))
        part(p, "brass", (2.9, 0.06, 0.06), T(-2.5, i + 0.04, z_near + run - 0.05))
        if i % 4 == 2:
            part(p, "blood", (0.5, 0.02, 0.4), T(-2.0 + rng.uniform(-0.6, 0.6), i + 0.06, z_near + run / 2))
    for z0 in (22.4, 8.0):
        y0 = 0.0 if z0 > 20 else 13.0
        lathe_post(p, "wood_dark", bp.turned_leg(4.0, 0.32), 0.1, y0, z0)
        ball(p, "wood_dark", 0.3, 0.1, y0 + 4.2, z0)
    return p


def build_upper():
    p = Prop("FarmhouseInteriorUpper", pivot="origin")
    rng = random.Random(43)
    y0, h = 13.0, 11.0
    room(p, rng, -31.5, -5.5, -23.5, -0.5, y0, h, "master", {
        "n": [win(-20), win(-12)], "w": [win(-12)], "e": [door(-5.5)],
    }, lower="wainscot")
    room(p, rng, 5.5, 31.5, -23.5, -0.5, y0, h, "kids", {
        "n": [win(12), win(22)], "e": [win(-12)], "w": [door(-5.5)],
    }, lower="wainscot")
    bath = room(p, rng, -31.5, -5.5, 0.5, 23.5, y0, h, None, {
        "s": [win(-18)], "w": [win(12)], "e": [door(4.5)],
    }, lower="tile", lower_top=5.5)
    room(p, rng, 5.5, 31.5, 0.5, 23.5, y0, h, None, {
        "s": [win(18)], "e": [win(12)], "w": [door(4.5)],
    }, lower="panel")
    hall = room(p, rng, -4.5, 4.5, -23.5, 23.5, y0, h, "hall", {
        "w": [door(-5.5), door(4.5)], "e": [door(-5.5), door(4.5)],
    }, lower="wainscot")
    # something was dragged out of the bath
    face = bath["e"][0]
    for k in range(3):
        handprint(p, face, 2.5 + k * 0.9, y0 + 3.2 - k * 0.5, 0.3 - k * 0.2)
    for _ in range(3):
        splat(p, bath["s"][0], rng.uniform(-28, -10), y0 + rng.uniform(2, 6), rng)
    handprint(p, hall["e"][0], 10.0, y0 + 4.0, -0.2)
    return p


BUILDERS = {"FarmhouseInteriorGround": build_ground, "FarmhouseInteriorUpper": build_upper}

if __name__ == "__main__":
    bp.BUILDERS.update(BUILDERS)
    argv = sys.argv
    names = argv[argv.index("--") + 1:] if "--" in argv else []
    sys.argv = [argv[0], "--"] + (names or list(BUILDERS.keys()))
    bp.main()
