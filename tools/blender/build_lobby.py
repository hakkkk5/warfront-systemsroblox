"""
The Cannibal Family - the lobby's truck stop (server Lobby.luau).

The signature pieces of the truck stop, each modelled in place around the
lobby origin (pivot "origin", Roblox axes, studs) over the collision parts
Lobby.luau builds in its stand-ins:

    TruckStopDiner      chrome railcar diner: fluted steel, a barrel roof,
                        checker floor, booths, a counter with stools, the
                        jukebox, the kitchen through the pass window
    TruckStopMotel      six rooms and an office: brick and stucco, a mansard
                        front, teal doors, a walkway on white posts
    TruckStopPylon      the roadside sign: I-beam posts, a round-ended
                        cabinet edged with bulbs, a starburst on top
    TruckStopBillboard  legs and bracing, a catwalk with railings and
                        floodlights, the scaffold and ladder of the climb

Lettering and neon tubes stay Roblox parts (SurfaceGui and Neon) in
Lobby.luau; everything else plain is the auto-remodel (LobbyParts).

    blender -b --factory-startup -P tools/blender/build_lobby.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import build_props as bp  # noqa: E402
from build_props import PALETTE, Prop, srgb  # noqa: E402
from build_buildings import Face, T, RX, RY, RZ, part, at, cyl, ball, beam, band, cyl_between  # noqa: E402

PALETTE.update({
    "ts_chrome": dict(color=srgb(200, 202, 206), roblox="Metal", rough=0.2, metal=1.0, pattern="scratch"),
    "ts_red": dict(color=srgb(170, 30, 36), roblox="SmoothPlastic", rough=0.4, metal=0.0, pattern="chipped"),
    "ts_vinyl": dict(color=srgb(150, 24, 30), roblox="Leather", rough=0.5, metal=0.0, pattern="dirty"),
    "ts_formica": dict(color=srgb(214, 208, 192), roblox="SmoothPlastic", rough=0.3, metal=0.0, pattern="dirty"),
    "ts_cream": dict(color=srgb(226, 216, 190), roblox="SmoothPlastic", rough=0.6, metal=0.0, pattern="dirty"),
    "ts_mint": dict(color=srgb(150, 196, 176), roblox="SmoothPlastic", rough=0.6, metal=0.0, pattern="dirty"),
    "ts_tile_w": dict(color=srgb(230, 226, 214), roblox="SmoothPlastic", rough=0.3, metal=0.0, pattern="dirty"),
    "ts_tile_b": dict(color=srgb(26, 26, 28), roblox="SmoothPlastic", rough=0.3, metal=0.0, pattern="scratch"),
    "ts_stucco": dict(color=srgb(196, 170, 140), roblox="Plaster", rough=1.0, metal=0.0, pattern="dirty"),
    "ts_teal": dict(color=srgb(40, 120, 120), roblox="Wood", rough=0.7, metal=0.0, pattern="chipped"),
    "ts_white": dict(color=srgb(232, 228, 216), roblox="Wood", rough=0.7, metal=0.0, pattern="chipped"),
    "ts_steel": dict(color=srgb(70, 72, 76), roblox="Metal", rough=0.5, metal=0.8, pattern="rust"),
    "ts_grating": dict(color=srgb(90, 92, 96), roblox="DiamondPlate", rough=0.6, metal=0.8, pattern="rust"),
    "ts_bulb": dict(color=srgb(255, 236, 196), roblox="SmoothPlastic", rough=0.2, metal=0.0, pattern="none"),
    "ts_glass": dict(color=srgb(70, 84, 92), roblox="Glass", rough=0.05, metal=0.0, pattern="none", transparency=0.55),
    "ts_curtain": dict(color=srgb(150, 96, 52), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave"),
    "ts_board": dict(color=srgb(40, 34, 30), roblox="Wood", rough=0.9, metal=0.0, pattern="grain_old"),
})


def box(p, mat, x0, x1, y0, y1, z0, z1):
    """An axis-aligned box between two corners (Roblox space)."""
    at(p, mat, (abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)), (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)


def ribs(p, mat, face, a0, a1, y0, y1, gaps=(), pitch=0.6, out=0.04):
    """Vertical flutes on a face, skipping gaps (a0, a1 along the face)."""
    a = a0 + pitch / 2
    while a < a1:
        if not any(g0 - 0.1 < a < g1 + 0.1 for g0, g1 in gaps):
            face.box(p, mat, 0.14, y1 - y0, 0.06, a, (y0 + y1) / 2, out)
        a += pitch


def frame_around(p, mat, face, c, w, y0, y1, depth=0.18, t=0.3):
    """A trim frame round an opening (centre c, width w, y0..y1)."""
    for s in (-1, 1):
        face.box(p, mat, t, y1 - y0 + 2 * t, depth, c + s * (w / 2 + t / 2), (y0 + y1) / 2, 0)
    for y in (y0 - t / 2, y1 + t / 2):
        face.box(p, mat, w + 2 * t, t, depth, c, y, 0)


# ============================================================================ diner
WIN = (19.5, 26.5, 41.5, 48.5)
X0, X1, Z0, Z1 = 14.0, 54.0, 18.0, 40.0  # outer faces of the walls
FLOOR = 0.5


def build_diner():
    p = Prop("TruckStopDiner", pivot="origin")
    front, back = Face("z", Z0, -1), Face("z", Z1, 1)
    west, east = Face("x", X0, -1), Face("x", X1, 1)
    gaps_front = [(c - 3, c + 3) for c in WIN] + [(31.8, 36.2)]
    # outside: a red base, fluted steel below and above the windows, a red
    # enamel band, chrome window frames
    for face, lo, hi in ((front, X0, X1), (back, X0, X1), (west, Z0, Z1), (east, Z0, Z1)):
        door = [(31.8, 36.2)] if face is front else []
        band(p, face, "ts_red", lo, hi, 0.0, 1.0, 0.12, door)
        ribs(p, "ts_chrome", face, lo, hi, 1.0, 3.6, door, out=0.05)
        band(p, face, "ts_chrome", lo, hi, 1.0, 3.7, 0.04, door)
        band(p, face, "ts_red", lo, hi, 9.2, 10.1, 0.1, [])
        ribs(p, "ts_chrome", face, lo, hi, 10.1, 11.5, [], out=0.05)
        band(p, face, "ts_chrome", lo, hi, 10.1, 11.5, 0.04, [])
        if face is not front:
            band(p, face, "ts_chrome", lo, hi, 3.7, 9.2, 0.04, [])
    # the front between the windows
    band(p, front, "ts_chrome", X0, X1, 3.7, 9.2, 0.04, gaps_front)
    for c in WIN:
        frame_around(p, "ts_chrome", front, c, 6.0, 3.7, 9.1, depth=0.24, t=0.25)
        for k in (-1, 1):
            front.box(p, "ts_chrome", 0.12, 5.4, 0.1, c + k, 6.4, 0.08)
    # the entrance: a chrome frame, a canopy, a glass transom
    frame_around(p, "ts_chrome", front, 34.0, 4.4, 0.5, 8.5, depth=0.3, t=0.35)
    box(p, "ts_chrome", 31.2, 36.8, 9.0, 9.35, 15.6, 18.0)
    box(p, "ts_red", 31.2, 36.8, 9.35, 9.8, 15.6, 18.0)
    for x in (31.4, 36.6):
        cyl(p, "ts_chrome", 0.12, 8.6, T(x, 4.7, 15.8), seg=8)
    # corner posts rounded off
    for x in (X0, X1):
        for z in (Z0, Z1):
            cyl(p, "ts_chrome", 0.35, 11.5, T(x, 5.75, z), seg=10)
    # the barrel roof: slats along an arc over the width
    span, rise = (Z1 - Z0) + 1.0, 2.6
    radius = (span * span / 4 + rise * rise) / (2 * rise)
    cy = 11.6 + rise - radius
    cz = (Z0 + Z1) / 2
    half = math.asin((span / 2) / radius)
    n = 18
    for i in range(n):
        a = -half + (i + 0.5) * (2 * half / n)
        y = cy + radius * math.cos(a)
        z = cz + radius * math.sin(a)
        chord = 2 * radius * math.sin(half / n) + 0.04
        part(p, "ts_chrome" if i % 2 == 0 else "ts_steel", (X1 - X0 + 1.2, 0.3, chord), T((X0 + X1) / 2, y, z) @ RX(-a))
    for z in (Z0 - 0.5, Z1 + 0.5):
        box(p, "ts_red", X0 - 0.6, X1 + 0.6, 11.5, 11.9, z - 0.2, z + 0.2)

    # inside: checker floor, cream walls over mint wainscot, a red stripe
    ix0, ix1, iz0, iz1 = X0 + 0.6, X1 - 0.6, Z0 + 0.6, 35.2
    nx, nz = int((ix1 - ix0) / 2), int((iz1 - iz0) / 2)
    wx, wz = (ix1 - ix0) / nx, (iz1 - iz0) / nz
    for i in range(nx):
        for j in range(nz):
            mat = "ts_tile_w" if (i + j) % 2 == 0 else "ts_tile_b"
            at(p, mat, (wx - 0.04, 0.04, wz - 0.04), ix0 + wx * (i + 0.5), FLOOR + 0.02, iz0 + wz * (j + 0.5))
    inner = (
        (Face("z", iz0, 1), ix0, ix1, [(c - 3, c + 3) for c in WIN] + [(31.8, 36.2)]),
        (Face("z", iz1 - 0.2, -1), ix0, ix1, [(28, 40), (48.3, 51.7)]),
        (Face("x", ix0, 1), iz0, iz1, []),
        (Face("x", ix1, -1), iz0, iz1, []),
    )
    for face, a0, a1, gaps in inner:
        door = [g for g in gaps if g[1] - g[0] < 5]
        band(p, face, "ts_mint", a0, a1, FLOOR, 3.6, 0.04, door)
        band(p, face, "ts_chrome", a0, a1, 3.6, 3.75, 0.08, door)
        band(p, face, "ts_red", a0, a1, 3.75, 4.1, 0.05, door)
        upper = [g for g in gaps if g[1] - g[0] >= 5] + door
        band(p, face, "ts_cream", a0, a1, 4.1, 11.4, 0.03, upper)
    box(p, "ts_cream", ix0, ix1, 11.35, 11.45, iz0, Z1 - 0.6)  # ceiling
    # the counter, its stools, a pie case
    box(p, "ts_red", 20.1, 47.9, FLOOR, 3.55, 32.1, 33.9)
    box(p, "ts_chrome", 20.0, 48.0, FLOOR, 0.9, 31.95, 34.05)
    box(p, "ts_formica", 19.8, 48.2, 3.55, 3.85, 31.7, 34.3)
    box(p, "ts_chrome", 19.75, 48.25, 3.55, 3.7, 31.65, 31.75)
    for x in range(22, 47, 3):
        cyl(p, "ts_chrome", 0.55, 0.2, T(x, FLOOR + 0.1, 30.6), seg=12)
        cyl(p, "ts_chrome", 0.12, 2.3, T(x, FLOOR + 1.3, 30.6), seg=8)
        cyl(p, "ts_vinyl", 0.62, 0.38, T(x, 3.05, 30.6), seg=14)
        cyl(p, "ts_chrome", 0.65, 0.1, T(x, 2.85, 30.6), seg=14)
    cyl(p, "ts_chrome", 0.7, 0.1, T(24, 3.92, 33), seg=14)
    ball(p, "ts_glass", 0.68, 24, 4.0, 33, seg=12, rings=6)
    # booths under the windows
    for c in WIN:
        box(p, "ts_formica", c - 1.8, c + 1.8, 2.95, 3.15, 20.2, 22.6)
        box(p, "ts_chrome", c - 1.85, c + 1.85, 2.9, 3.0, 20.15, 22.65)
        cyl(p, "ts_chrome", 0.15, 2.4, T(c, FLOOR + 1.2, 21.4), seg=8)
        for z, back_z in ((19.6, 18.95), (23.3, 24.35)):
            box(p, "ts_chrome", c - 2.5, c + 2.5, FLOOR, 1.5, z - 0.75, z + 0.75)
            at(p, "ts_vinyl", (4.9, 0.45, 1.5), c, 1.75, z)
            for k in range(4):
                at(p, "ts_vinyl", (1.15, 2.4, 0.45), c - 1.8 + k * 1.2, 3.1, back_z)
    # the jukebox: a wooden body, an arched top, a chrome grille, coloured panes
    jx, jz = 52.4, 28.0
    box(p, "ts_board", jx - 0.9, jx + 0.9, FLOOR, 4.6, jz - 1.3, jz + 1.3)
    cyl(p, "ts_board", 1.3, 1.8, T(jx, 4.6, jz) @ RZ(math.pi / 2), seg=16)
    for k in range(7):
        at(p, "ts_chrome", (0.08, 1.6, 0.08), jx - 0.95, 1.6, jz - 0.9 + k * 0.3)
    at(p, "ts_glass", (0.06, 1.6, 2.0), jx - 0.95, 3.6, jz)
    for s in (-1, 1):
        at(p, "ts_red", (0.08, 3.6, 0.25), jx - 0.95, 2.9, jz + s * 1.1)
    # the kitchen behind the pass: a grill, a hood, shelves, the pass ledge
    box(p, "ts_chrome", 28.0, 40.0, 4.9, 5.05, 35.0, 35.9)
    box(p, "ts_steel", 30.0, 38.0, FLOOR, 3.2, 37.2, 39.3)
    box(p, "ts_tile_b", 30.2, 37.8, 3.2, 3.3, 37.4, 39.1)
    box(p, "ts_chrome", 29.5, 38.5, 8.0, 9.5, 37.0, 39.4)
    for y in (5.5, 7.0):
        box(p, "ts_chrome", 16.0, 26.0, y, y + 0.12, 38.6, 39.4)
    box(p, "ts_board", 29.0, 39.0, 8.6, 10.6, 35.15, 35.25)  # the menu board
    return p


# ============================================================================ motel
MX0, MX1 = 64.0, 122.0


def build_motel():
    p = Prop("TruckStopMotel", pivot="origin")
    front = Face("z", 14.0, -1)
    back = Face("z", 30.0, 1)
    doors = [MX0 + 2.5 + i * 8 for i in range(6)]
    windows = [MX0 + 5.8 + i * 8 for i in range(6)]
    door_gaps = [(d - 1.6, d + 1.6) for d in doors] + [(113.3, 116.7)]
    win_gaps = [(w - 1.5, w + 1.5) for w in windows] + [(117.2, 121.2)]
    # brick below, stucco above, white trim
    band(p, front, "brick", MX0, MX1, 0.5, 2.8, 0.1, door_gaps)
    band(p, front, "ts_stucco", MX0, MX1, 2.8, 10.0, 0.05, door_gaps + win_gaps)
    for face, a0, a1 in ((back, MX0, MX1), (Face("x", MX0, -1), 14.0, 30.0), (Face("x", MX1, 1), 14.0, 30.0)):
        band(p, face, "brick", a0, a1, 0.5, 2.8, 0.1)
        band(p, face, "ts_stucco", a0, a1, 2.8, 10.0, 0.05)
    for d in doors + [115.0]:
        frame_around(p, "ts_white", front, d, 3.2 if d != 115.0 else 3.4, 0.5, 7.5 if d != 115.0 else 7.9, depth=0.2, t=0.3)
        w = 3.2 if d != 115.0 else 3.4
        h = 7.0 if d != 115.0 else 7.4
        front.box(p, "ts_teal", w - 0.1, h, 0.25, d, 0.5 + h / 2, -0.15)
        for k in range(2):
            front.box(p, "ts_teal", w - 0.9, h / 2 - 0.9, 0.06, d, 0.5 + h * (0.27 + 0.48 * k), 0.12)
        ball(p, "brass", 0.12, d + w / 2 - 0.45, 3.9, 13.75, seg=8, rings=5)
    for wcx, wide in [(w, 3.0) for w in windows] + [(119.2, 4.0)]:
        y0, y1 = (3.3, 6.7) if wide == 3.0 else (3.1, 7.5)
        frame_around(p, "ts_white", front, wcx, wide, y0, y1, depth=0.2, t=0.25)
        front.box(p, "ts_glass", wide, y1 - y0, 0.06, wcx, (y0 + y1) / 2, -0.2)
        front.box(p, "ts_curtain", wide - 0.2, y1 - y0 - 0.2, 0.05, wcx, (y0 + y1) / 2, -0.45)
        front.box(p, "ts_white", wide + 0.6, 0.2, 0.45, wcx, y0 - 0.35, 0.0)
    # back wall: an air conditioner under each room's back window
    for w in windows:
        back.box(p, "ts_white", 2.6, 1.6, 0.06, w, 5.0, 0.0)
        back.box(p, "ts_steel", 2.2, 1.3, 1.1, w, 2.4, 0.0)
    # the walkway: a concrete slab with joints and a curb
    for i in range(int((MX1 - MX0) / 4)):
        at(p, "concrete", (3.92, 0.12, 3.9), MX0 + 2 + i * 4, 0.44, 12.0)
    box(p, "concrete", MX0, MX1, 0.0, 0.55, 9.6, 10.1)
    # roof: flat deck, a shingled mansard over the front, fascia and posts
    box(p, "roof_deck", MX0 - 1.0, MX1 + 1.0, 10.0, 10.8, 8.5, 30.5)
    for i in range(10):
        y = 10.8 + i * 0.22
        z = 8.4 + i * 0.4
        box(p, "shingle", MX0 - 1.2, MX1 + 1.2, y, y + 0.16, z, z + 0.6)
    box(p, "ts_white", MX0 - 1.2, MX1 + 1.2, 9.6, 10.4, 8.3, 8.6)
    for x in range(int(MX0) + 1, int(MX1), 8):
        box(p, "ts_white", x - 0.28, x + 0.28, 0.5, 10.0, 10.02, 10.58)
        for s in (-1, 1):
            beam(p, "ts_white", (x, 8.6, 10.3), (x + s * 1.4, 10.0, 10.3), 0.2, 0.2)
    return p


# ============================================================================ pylon
PX, PZ = 74.0, -30.0


def ibeam(p, mat, x, z, y0, y1, w=1.2):
    box(p, mat, x - 0.12, x + 0.12, y0, y1, z - w / 2, z + w / 2)
    for s in (-1, 1):
        box(p, mat, x - w / 2, x + w / 2, y0, y1, z + s * (w / 2 - 0.08) - 0.08, z + s * (w / 2 - 0.08) + 0.08)


def build_pylon():
    p = Prop("TruckStopPylon", pivot="origin")
    for dx in (-6, 6):
        ibeam(p, "ts_red", PX + dx, PZ, 0.0, 30.5)
        box(p, "concrete", PX + dx - 1.4, PX + dx + 1.4, 0.0, 0.8, PZ - 1.4, PZ + 1.4)
    for y in (6.0, 12.0):
        box(p, "ts_steel", PX - 6, PX + 6, y - 0.2, y + 0.2, PZ - 0.15, PZ + 0.15)
    # the cabinet: a box with round ends, chrome edges, bulbs all round
    box(p, "ts_board", PX - 9, PX + 9, 21.0, 30.0, PZ - 0.85, PZ + 0.85)
    for s in (-1, 1):
        cyl(p, "ts_red", 4.6, 1.9, T(PX + s * 9, 25.5, PZ) @ RX(math.pi / 2), seg=20)
        for y in (21.0, 30.0):
            box(p, "ts_chrome", PX - 9.2, PX + 9.2, y - 0.15, y + 0.15, PZ + s * 0.95 - 0.1, PZ + s * 0.95 + 0.1)
    for k in range(19):
        x = PX - 9 + k
        for y in (20.6, 30.4):
            for s in (-1, 1):
                ball(p, "ts_bulb", 0.17, x, y, PZ + s * 0.95, seg=6, rings=4)
    box(p, "ts_board", PX - 8, PX + 8, 16.9, 20.3, PZ - 0.6, PZ + 0.6)
    box(p, "ts_chrome", PX - 8.15, PX + 8.15, 16.75, 16.95, PZ - 0.65, PZ + 0.65)
    # the starburst on top
    for k in range(12):
        a = k * math.pi / 6
        length = 3.4 if k % 2 == 0 else 2.2
        cx, cy = PX + math.cos(a) * length / 2, 33.0 + math.sin(a) * length / 2
        part(p, "ts_chrome", (length, 0.35, 0.3), T(cx, cy, PZ) @ RZ(a))
    ball(p, "ts_red", 0.7, PX, 33.0, PZ, seg=12, rings=8)
    cyl(p, "ts_steel", 0.18, 3.0, T(PX, 31.5, PZ), seg=8)
    # a service ladder up the east post
    for s in (-0.35, 0.35):
        box(p, "ts_steel", PX + 6.75, PX + 6.85, 0.0, 21.0, PZ + s - 0.05, PZ + s + 0.05)
    for y in range(1, 21):
        box(p, "ts_steel", PX + 6.76, PX + 6.84, y, y + 0.08, PZ - 0.35, PZ + 0.35)
    return p


# ============================================================================ billboard
BX, BZ = 60.0, 79.0


def build_billboard():
    p = Prop("TruckStopBillboard", pivot="origin")
    # the face: plank backing in a steel frame, posters' edges curling
    box(p, "ts_board", BX - 20, BX + 20, 28.0, 44.0, BZ - 0.3, BZ + 0.5)
    for y in (27.9, 44.1):
        box(p, "ts_steel", BX - 20.4, BX + 20.4, y - 0.25, y + 0.25, BZ - 0.6, BZ + 0.6)
    for x in (BX - 20.2, BX + 20.2):
        box(p, "ts_steel", x - 0.25, x + 0.25, 27.7, 44.3, BZ - 0.6, BZ + 0.6)
    for k in range(9):
        box(p, "ts_steel", BX - 19 + k * 4.75 - 0.1, BX - 19 + k * 4.75 + 0.1, 28.0, 44.0, BZ + 0.5, BZ + 0.8)
    # legs, with cross bracing
    legs = (BX - 14, BX, BX + 14)
    for x in legs:
        ibeam(p, "ts_steel", x, BZ + 0.8, 0.0, 28.0)
        box(p, "concrete", x - 1.3, x + 1.3, 0.0, 0.7, BZ - 0.5, BZ + 2.1)
    for a, b in zip(legs, legs[1:]):
        for y0, y1 in ((2, 13), (13, 24)):
            cyl_between(p, "ts_steel", (a, y0, BZ + 0.8), (b, y1, BZ + 0.8), 0.12, seg=6)
            cyl_between(p, "ts_steel", (a, y1, BZ + 0.8), (b, y0, BZ + 0.8), 0.12, seg=6)
    # the catwalk: grating, a toe board, posts and two rails
    cz = BZ - 1.8
    box(p, "ts_grating", BX - 20, BX + 20, 26.8, 27.2, cz - 1.3, cz + 1.3)
    box(p, "ts_steel", BX - 20, BX + 20, 27.2, 27.5, cz - 1.3, cz - 1.2)
    x = BX - 20
    while x <= BX + 20.01:
        cyl(p, "ts_steel", 0.08, 3.0, T(x, 28.7, cz - 1.2), seg=6)
        x += 2.5
    for y in (30.2, 28.8):
        cyl_between(p, "ts_steel", (BX - 20, y, cz - 1.2), (BX + 20, y, cz - 1.2), 0.08, seg=6)
    for dx in (-12, 0, 12):
        box(p, "ts_steel", BX + dx - 0.6, BX + dx + 0.6, 28.2, 28.9, cz - 2.4, cz - 1.4)
        cyl_between(p, "ts_steel", (BX + dx, 28.4, cz - 1.2), (BX + dx, 28.4, cz - 1.9), 0.07, seg=6)
    # the scaffold under the catwalk: tube frame, plank deck, the ladder
    sx, sz = 60.0, 74.0
    box(p, "ts_board", sx - 4, sx + 4, 19.4, 20.0, sz - 2, sz + 2)
    for dx in (-3.6, 3.6):
        for dz in (-1.6, 1.6):
            cyl(p, "ts_steel", 0.2, 19.4, T(sx + dx, 9.7, sz + dz), seg=8)
    for y in (6.5, 13.0, 19.2):
        for dz in (-1.6, 1.6):
            cyl_between(p, "ts_steel", (sx - 3.6, y, sz + dz), (sx + 3.6, y, sz + dz), 0.1, seg=6)
        for dx in (-3.6, 3.6):
            cyl_between(p, "ts_steel", (sx + dx, y, sz - 1.6), (sx + dx, y, sz + 1.6), 0.1, seg=6)
    for dz in (-1.6, 1.6):
        cyl_between(p, "ts_steel", (sx - 3.6, 0.5, sz + dz), (sx + 3.6, 19.0, sz + dz), 0.09, seg=6)
    lz = 75.4
    for s in (-0.8, 0.8):
        box(p, "ts_steel", sx + s - 0.1, sx + s + 0.1, 20.0, 27.4, lz - 0.1, lz + 0.1)
    y = 20.6
    while y < 27.3:
        cyl_between(p, "ts_steel", (sx - 0.8, y, lz), (sx + 0.8, y, lz), 0.07, seg=6)
        y += 0.8
    return p


BUILDERS = {
    "TruckStopDiner": build_diner,
    "TruckStopMotel": build_motel,
    "TruckStopPylon": build_pylon,
    "TruckStopBillboard": build_billboard,
}

if __name__ == "__main__":
    bp.BUILDERS.update(BUILDERS)
    argv = sys.argv
    names = argv[argv.index("--") + 1:] if "--" in argv else []
    sys.argv = [argv[0], "--"] + (names or list(BUILDERS.keys()))
    bp.main()
