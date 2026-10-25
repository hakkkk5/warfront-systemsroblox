"""
The Cannibal Family - Blender bodies for the cannibals.

Each of the six kinds gets eight meshes, one per R6 body part in two forms:

    <Kind>Head  <Kind>Torso  <Kind>Arm  <Kind>Leg                (near human)
    <Kind>MonsterHead  <Kind>MonsterTorso  <Kind>MonsterArm  <Kind>MonsterLeg

Every mesh is modelled in Roblox space around the centre of the R6 part it
dresses, at rig scale 1 (pivot "origin"): Head 2x1x1 (shown as a ~1.25 head),
Torso 2x2x1, Arm and Leg 1x2x1. The monster parts are modelled at the sizes
MonsterForm stretches the rig to (client MonsterForm.luau): arms 0.75x3.8x0.75
with the shoulder 0.5 below the top, legs 0.8x3.6x0.8, torso 1.7x2.6x0.8.
The client (CannibalSkins.luau) welds them onto the rig's parts, so the
keyframe animation, AI and cutscenes keep working on the plain R6 rig.

Faces look down -Z (Roblox front). Run like the other builders:
    blender -b --factory-startup -P tools/blender/build_monsters.py [-- ButcherMonsterHead ...]
"""

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mathutils import Vector  # noqa: E402

import build_props as bp  # noqa: E402
import build_buildings as bb  # noqa: E402
from build_props import PALETTE, Prop, srgb  # noqa: E402
from build_buildings import T, RX, RY, RZ, part, cyl, beam  # noqa: E402

# the kinds' colours, as in server Cannibals.luau KINDS
KINDS = {
    "Butcher": dict(skin=(190, 150, 128), shirt=(132, 120, 100), pants=(46, 42, 38), mask="Sack", apron=True, bulk=1.15),
    "Brother": dict(skin=(206, 176, 156), shirt=(90, 84, 70), pants=(54, 50, 60), mask="Stitched", apron=False, bulk=0.9),
    "Hunter": dict(skin=(176, 140, 116), shirt=(70, 76, 52), pants=(52, 46, 36), mask="Sack", apron=False, bulk=1.0, hood=True),
    "Scavenger": dict(skin=(200, 168, 146), shirt=(110, 60, 46), pants=(40, 40, 44), mask="Stitched", apron=False, bulk=0.85),
    "Papa": dict(skin=(184, 146, 120), shirt=(100, 94, 82), pants=(36, 34, 32), mask="Skin", apron=True, bulk=1.25),
    "Kin": dict(skin=(196, 162, 140), shirt=(84, 70, 56), pants=(44, 42, 40), mask="Sack", apron=False, bulk=1.0),
}

PALETTE.update({
    "monster_skin": dict(color=srgb(88, 86, 78), roblox="SmoothPlastic", rough=0.6, metal=0.0, pattern="skin"),
    "monster_flesh": dict(color=srgb(120, 40, 36), roblox="SmoothPlastic", rough=0.4, metal=0.0, pattern="blood"),
    "maw": dict(color=srgb(18, 6, 6), roblox="SmoothPlastic", rough=0.9, metal=0.0, pattern="none"),
    "teeth": dict(color=srgb(214, 200, 160), roblox="SmoothPlastic", rough=0.5, metal=0.0, pattern="dirty"),
    "claw": dict(color=srgb(42, 34, 30), roblox="SmoothPlastic", rough=0.4, metal=0.0, pattern="dirty"),
    "bone": dict(color=srgb(206, 192, 162), roblox="SmoothPlastic", rough=0.6, metal=0.0, pattern="dirty"),
    "eye_glow": dict(color=srgb(255, 36, 24), roblox="Neon", rough=0.1, metal=0.0, pattern="none"),
    "eye_white": dict(color=srgb(196, 178, 112), roblox="SmoothPlastic", rough=0.2, metal=0.0, pattern="dirty"),
    "boot": dict(color=srgb(34, 28, 24), roblox="Leather", rough=0.7, metal=0.0, pattern="dirty"),
})
for _kind, _k in KINDS.items():
    PALETTE["skin" + _kind] = dict(color=srgb(*_k["skin"]), roblox="SmoothPlastic", rough=0.7, metal=0.0, pattern="skin")
    PALETTE["shirt" + _kind] = dict(color=srgb(*_k["shirt"]), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave_blood")
    PALETTE["pants" + _kind] = dict(color=srgb(*_k["pants"]), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave")


def rv(x, y, z):
    """Roblox point -> Blender point."""
    return (x, -z, y)


def blob(p, mat, r, x, y, z, sx=1.0, sy=1.0, sz=1.0, seg=14, rings=10, rough=0.0, seed=0.0):
    ob = bp.sphere(None, None, r, loc=rv(x, y, z), scale=(sx, sz, sy), seg=seg, rings=rings)
    if rough:
        bp.displace(ob, rough, 3.0, seed)
    return p.add(ob, mat)


def cone(p, mat, a, b, ra, rb, seg=8):
    """Tapered limb segment from a (radius ra) to b (radius rb), Roblox points."""
    a, b = Vector(a), Vector(b)
    d = b - a
    y = d.normalized()
    x = y.cross(Vector((0, 0, 1)) if abs(y.z) < 0.9 else Vector((1, 0, 0))).normalized()
    z = x.cross(y)
    return cyl(p, mat, ra, d.length, bb.frame(x, y, z, (a + b) / 2), seg=seg, r2=rb)


def limb(p, mat, x, z, profile, seg=12, lumps=0.03, seed=0.0):
    """A sculpted vertical limb: profile is (radius, Roblox y) from top down."""
    pts = sorted(((r, y) for r, y in profile), key=lambda q: q[1])
    ob = bp.lathe(None, None, pts, seg=seg, loc=rv(x, 0, z))
    if lumps:
        bp.displace(ob, lumps, 5.0, seed)
    return p.add(ob, mat)


def finger(p, rng, base, out, length, r=0.055):
    """Two-jointed finger hooking forward into a thick claw."""
    b = Vector(base)
    d = Vector(out).normalized()
    k1 = b + d * length * 0.5
    k2 = k1 + (d + Vector((0, -0.3, -0.5))).normalized() * length * 0.4
    tip = k2 + (d + Vector((0, -0.2, -1.4))).normalized() * length * 0.55
    cone(p, "monster_skin", tuple(b), tuple(k1), r, r * 0.85, seg=6)
    cone(p, "monster_skin", tuple(k1), tuple(k2), r * 0.85, r * 0.75, seg=6)
    cone(p, "claw", tuple(k2), tuple(tip), r * 0.95, 0.0, seg=7)


def rag(p, mat, rng, x0, x1, y, z, depth, count, drop=(0.2, 0.7), facing=-1):
    """A ragged hem: strips hanging from y between x0 and x1 on the plane z."""
    for i in range(count):
        x = x0 + (x1 - x0) * (i + 0.5) / count
        h = rng.uniform(*drop)
        part(p, mat, ((x1 - x0) / count * 0.92, h, depth), T(x, y - h / 2, z) @ RZ(rng.uniform(-0.12, 0.12)))


# ----------------------------------------------------------------------------- near-human parts
def human_head(kind):
    k = KINDS[kind]
    p = Prop(kind + "Head", pivot="origin")
    s = "skin" + kind
    # the R6 head shows ~1.2 across; the masks sit a little proud of it
    if k["mask"] == "Sack":
        sack = blob(p, "burlap", 0.7, 0, 0.05, 0, 1.02, 1.08, 1.0, seg=24, rings=16, rough=0.04, seed=3)
        bp.displace(sack, 0.015, 12.0, 5.0)
        blob(p, "burlap", 0.24, 0.05, 0.75, 0.05, 1.2, 0.8, 1.0, seg=10, rings=6, rough=0.05)
        bp.torus(p, "rope", 0.52, 0.05, rv(0, -0.5, 0), seg=24, tseg=5)
        part(p, "metal_dark", (0.5, 0.05, 0.05), T(0, -0.3, -0.69) @ RZ(-0.06))
        for i in range(6):
            part(p, "rope", (0.025, 0.16, 0.03), T(-0.2 + i * 0.08, -0.3, -0.71) @ RZ(0.5 if i % 2 else -0.5))
    elif k["mask"] == "Stitched":
        blob(p, "leather", 0.68, 0, 0, 0, 1.0, 1.06, 0.98, seg=22, rings=14, rough=0.02, seed=4)
        for i in range(-2, 3):
            part(p, "metal_dark", (0.04, 1.05, 0.04), T(i * 0.2, 0, -0.66) @ RZ(i * 0.18))
            for j in range(5):
                part(p, "rope", (0.12, 0.025, 0.03), T(i * 0.2 + (j - 2) * 0.02 * i, -0.4 + j * 0.2, -0.68))
    else:  # skin mask: a pale stretched face with a wide stitched grin and hair
        blob(p, "leather", 0.7, 0, 0, 0, 1.0, 1.05, 1.0, seg=22, rings=14, rough=0.03, seed=6)
        part(p, "maw", (0.62, 0.09, 0.05), T(0, -0.3, -0.69) @ RZ(0.05))
        for i in range(8):
            part(p, "rope", (0.02, 0.16, 0.03), T(-0.28 + i * 0.08, -0.3, -0.71))
        blob(p, "wood_dark", 0.72, 0, 0.36, 0.05, 1.04, 0.55, 1.04, seg=18, rings=8, rough=0.06, seed=7)
    if k.get("hood"):
        blob(p, "canvas", 0.8, 0, 0.12, 0.1, 1.04, 1.04, 1.06, seg=20, rings=12, rough=0.03, seed=8)
    # eye holes where the server's glowing Eye parts sit (x +-0.22, y 0.12)
    for x in (-0.22, 0.22):
        blob(p, "maw", 0.1, x, 0.12, -0.66, 1.2, 0.9, 0.4, seg=10, rings=6)
    # neck
    cone(p, s, (0, -0.95, 0), (0, -0.5, 0), 0.32, 0.36)
    return p


def human_torso(kind):
    k = KINDS[kind]
    p = Prop(kind + "Torso", pivot="origin")
    rng = random.Random(len(kind))
    sh = "shirt" + kind
    w = 1.0 + (k["bulk"] - 1.0) * 0.5
    blob(p, sh, 0.62, 0, 0.25, 0, 1.55 * w, 1.15, 0.78, seg=18, rings=10, rough=0.04, seed=1)
    blob(p, sh, 0.58, 0, -0.45, 0, 1.45 * w, 1.0, 0.8 * k["bulk"], seg=18, rings=10, rough=0.04, seed=2)
    part(p, "leather", (1.9 * w, 0.18, 1.0), T(0, -0.9, 0))
    part(p, "brass", (0.22, 0.16, 0.06), T(0, -0.9, -0.52))
    if k["apron"]:
        part(p, "leather", (1.4 * w, 1.9, 0.08), T(0, -0.35, -0.55) @ RX(0.04))
        for _ in range(6):
            part(p, "blood", (rng.uniform(0.15, 0.45), rng.uniform(0.15, 0.6), 0.02), T(rng.uniform(-0.5, 0.5), rng.uniform(-1.1, 0.4), -0.6))
        beam(p, "leather", (-0.5 * w, 0.55, -0.5), (-0.35, 1.0, 0.1), 0.1, 0.05)
        beam(p, "leather", (0.5 * w, 0.55, -0.5), (0.35, 1.0, 0.1), 0.1, 0.05)
    # blood soaked into the cloth
    for _ in range(4):
        blob(p, "blood", 0.14, rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), -0.48, 1.4, 1.0, 0.15, seg=8, rings=5)
    return p


def human_arm(kind):
    p = Prop(kind + "Arm", pivot="origin")
    sh, s = "shirt" + kind, "skin" + kind
    cone(p, sh, (0, 0.95, 0), (0, -0.1, 0), 0.44, 0.38, seg=10)
    cone(p, s, (0, -0.1, 0), (0, -0.78, 0), 0.32, 0.28, seg=10)
    blob(p, s, 0.3, 0, -0.9, 0, 1.0, 0.9, 1.1, seg=10, rings=7, rough=0.02)
    for i in range(4):
        cone(p, s, (-0.15 + i * 0.1, -1.0, -0.15), (-0.15 + i * 0.1, -1.0, -0.33), 0.06, 0.05, seg=5)
    return p


def human_leg(kind):
    p = Prop(kind + "Leg", pivot="origin")
    pa = "pants" + kind
    cone(p, pa, (0, 0.95, 0), (0, -0.55, 0), 0.47, 0.4, seg=10)
    cone(p, "boot", (0, -0.55, 0), (0, -0.92, 0), 0.42, 0.44, seg=10)
    part(p, "boot", (0.82, 0.22, 1.2), T(0, -0.9, -0.12))
    part(p, "boot", (0.9, 0.08, 1.24), T(0, -0.98, -0.12))
    return p


# ----------------------------------------------------------------------------- monster parts
def monster_head(kind):
    """Distorted: a lumpy elongated skull, a dislocated jaw hanging open and
    askew, a torn mouth full of uneven teeth, eyes in the wrong places, and
    what is left of the kind's mask."""
    k = KINDS[kind]
    p = Prop(kind + "MonsterHead", pivot="origin")
    rng = random.Random(len(kind) * 7)
    skull = blob(p, "monster_skin", 0.62, 0.04, 0.18, 0.02, 0.95, 1.35, 1.0, seg=24, rings=16)
    bp.displace(skull, 0.09, 2.5, rng.uniform(0, 9))
    bp.displace(skull, 0.03, 9.0, rng.uniform(0, 9))
    # cheek bones pushed out of shape, one sunken
    blob(p, "monster_skin", 0.22, -0.34, -0.02, -0.38, 1.2, 0.8, 0.7, rough=0.03)
    blob(p, "monster_skin", 0.16, 0.36, 0.06, -0.42, 1.0, 1.1, 0.6, rough=0.03)
    # the torn mouth: a tall dark maw ripped up one cheek
    blob(p, "maw", 0.3, 0.06, -0.38, -0.46, 1.25, 1.5, 0.5, seg=14, rings=10)
    beam(p, "maw", (0.12, -0.3, -0.56), (0.48, 0.02, -0.4), 0.12, 0.08)
    blob(p, "monster_flesh", 0.3, 0.06, -0.38, -0.42, 1.35, 1.6, 0.4, seg=14, rings=10)
    # upper teeth, crooked and too many
    for i in range(11):
        x = -0.26 + i * 0.055
        tilt = rng.uniform(-0.25, 0.25)
        cone(p, "teeth", (x, -0.14, -0.6), (x + tilt * 0.1, -0.34 - rng.uniform(0, 0.12), -0.62), 0.03, 0.0, seg=5)
    # the jaw: dislocated, hanging down and twisted to one side
    jaw = T(0.08, -0.72, -0.28) @ RZ(0.22) @ RX(-0.55)
    part(p, "monster_skin", (0.62, 0.14, 0.55), jaw)
    for i in range(9):
        x = -0.24 + i * 0.06
        base = jaw @ Vector((x, 0.06, -0.24))
        cone(p, "teeth", tuple(base), (base.x + rng.uniform(-0.02, 0.02), base.y + 0.2 + rng.uniform(0, 0.08), base.z - 0.02), 0.028, 0.0, seg=5)
    for side in (-1, 1):
        beam(p, "monster_flesh", (side * 0.3, -0.42, -0.3), tuple(jaw @ Vector((side * 0.3, 0, 0.1))), 0.07, 0.05)
    # eyes in the wrong places: one high on the brow, one sliding down the cheek,
    # a third half-open by the temple
    eyes = ((-0.2, 0.42, -0.5, 0.11), (0.3, -0.08, -0.5, 0.09), (-0.42, 0.18, -0.3, 0.06))
    for x, y, z, r in eyes:
        blob(p, "maw", r * 1.5, x, y, z + 0.03, 1.2, 1.0, 0.5, seg=10, rings=6)
        blob(p, "eye_white", r, x, y, z - 0.02, 1.0, 1.0, 0.7, seg=10, rings=6)
        blob(p, "eye_glow", r * 0.45, x + rng.uniform(-0.02, 0.02), y, z - 0.08, 1.0, 1.0, 0.6, seg=8, rings=5)
    # long greasy hair strands
    for i in range(10):
        a = i / 10 * math.pi * 2
        top = (math.cos(a) * 0.35, 0.82, math.sin(a) * 0.3 + 0.05)
        beam(p, "wood_dark", top, (top[0] * 1.6, -0.4 - rng.uniform(0, 0.4), top[2] * 1.4 + 0.12), 0.05, 0.03)
    # the mask, torn
    if k["mask"] == "Sack":
        part(p, "burlap", (0.9, 0.7, 0.08), T(0.22, 0.55, 0.2) @ RY(0.9) @ RZ(0.3))
        part(p, "burlap", (0.5, 0.9, 0.06), T(-0.45, 0.0, 0.25) @ RY(-1.2) @ RZ(-0.2))
        bp.torus(p, "rope", 0.42, 0.04, rv(0, -0.6, 0.15), seg=18, tseg=4)
    elif k["mask"] == "Stitched":
        for i in range(4):
            beam(p, "leather", (-0.4 + i * 0.26, 0.7, -0.4), (-0.5 + i * 0.3, -0.2 - rng.uniform(0, 0.4), -0.52), 0.12, 0.03)
    else:
        part(p, "leather", (0.7, 0.8, 0.05), T(0.48, 0.1, -0.12) @ RY(1.1) @ RZ(0.4))
    if k.get("hood"):
        blob(p, "canvas", 0.8, 0, 0.3, 0.2, 1.0, 1.2, 1.05, seg=18, rings=10, rough=0.05)
    cone(p, "monster_skin", (0, -1.05, 0.05), (0, -0.55, 0.05), 0.2, 0.26)
    return p


def monster_torso(kind):
    """Gaunt and stretched (1.7 x 2.6 x 0.8): ribs through the skin, a spine of
    bone spurs, the shirt hanging in strips."""
    k = KINDS[kind]
    p = Prop(kind + "MonsterTorso", pivot="origin")
    rng = random.Random(len(kind) * 11)
    body = blob(p, "monster_skin", 0.5, 0, 0.35, 0, 1.6, 2.0, 0.75, seg=18, rings=12)
    bp.displace(body, 0.05, 3.0, 2.0)
    blob(p, "monster_skin", 0.4, 0, -0.8, 0.05, 1.3, 1.4, 0.7, seg=16, rings=10, rough=0.04)
    for i in range(6):
        y = 0.75 - i * 0.24
        for side in (-1, 1):
            a = (side * 0.12, y, -0.36)
            b = (side * 0.62, y - 0.12, -0.22)
            c = (side * 0.72, y - 0.2, 0.12)
            beam(p, "bone", a, b, 0.07, 0.07)
            beam(p, "bone", b, c, 0.06, 0.06)
    part(p, "bone", (0.12, 1.4, 0.1), T(0, 0.3, -0.38))
    for i in range(5):
        cone(p, "bone", (0, 0.9 - i * 0.4, 0.3), (0, 0.98 - i * 0.4, 0.62 + rng.uniform(0, 0.15)), 0.08, 0.0, seg=6)
    rag(p, "shirt" + kind, rng, -0.8, 0.8, 1.15, -0.4, 0.04, 9, drop=(0.3, 1.1))
    rag(p, "shirt" + kind, rng, -0.8, 0.8, 1.15, 0.4, 0.04, 7, drop=(0.4, 1.4))
    if k["apron"]:
        part(p, "leather", (1.0, 1.3, 0.05), T(0.15, -0.8, -0.42) @ RZ(0.12) @ RX(0.1))
    part(p, "leather", (1.7, 0.14, 0.86), T(0, -1.2, 0))
    return p


def monster_arm(kind):
    """0.75 x 3.8 x 0.75, the shoulder 0.5 below the top: a long sinewy arm
    with a knotted elbow and a hand of hooked claws reaching past the knees."""
    p = Prop(kind + "MonsterArm", pivot="origin")
    rng = random.Random(len(kind) * 13)
    # shoulder, wiry upper arm, a knot of an elbow, a forearm all sinew, bony wrist
    limb(p, "monster_skin", 0, 0, [
        (0.31, 1.75), (0.27, 1.4), (0.22, 1.0), (0.24, 0.65), (0.19, 0.3), (0.23, 0.12), (0.2, -0.05),
        (0.16, -0.4), (0.18, -0.75), (0.13, -1.1), (0.15, -1.38), (0.12, -1.5),
    ], seg=12, lumps=0.035, seed=len(kind))
    blob(p, "bone", 0.13, 0.02, 0.12, 0.16, 1.0, 1.3, 0.9, rough=0.02)
    for i in range(3):
        beam(p, "monster_flesh", (0.12 * (i - 1), -0.25, -0.15), (0.1 * (i - 1), -1.25, -0.11), 0.035, 0.03)
    # a too-big hand and five hooked fingers reaching past the knees
    hand = blob(p, "monster_skin", 0.22, 0, -1.65, -0.06, 1.35, 1.05, 0.75, seg=12, rings=8)
    bp.displace(hand, 0.03, 6.0, 4.0)
    for i in range(5):
        a = (i - 2) * 0.11
        thumb = i == 0
        base = (a - (0.08 if thumb else 0), -1.75, -0.12)
        out = (a * 1.3 - (0.4 if thumb else 0), -1.0, -0.25)
        finger(p, rng, base, out, 0.62 if thumb else 0.82 + rng.uniform(0, 0.12), r=0.06 if thumb else 0.055)
    # torn sleeve at the shoulder
    cone(p, "shirt" + kind, (0, 1.9, 0), (0, 1.2, 0), 0.38, 0.34, seg=10)
    rag(p, "shirt" + kind, rng, -0.3, 0.3, 1.25, -0.33, 0.03, 4)
    for _ in range(4):
        blob(p, "blood", 0.06, rng.uniform(-0.15, 0.15), rng.uniform(-1.4, 1.0), -0.2, 1.0, 2.0, 0.3, seg=6, rings=4)
    return p


def monster_leg(kind):
    """0.8 x 3.6 x 0.8: too long, a backward knot of a knee, torn trousers and
    bare clawed feet."""
    p = Prop(kind + "MonsterLeg", pivot="origin")
    rng = random.Random(len(kind) * 17)
    hip = (0, 1.75, 0)
    cone(p, "pants" + kind, hip, (0, 0.6, -0.04), 0.4, 0.3, seg=10)
    rag(p, "pants" + kind, rng, -0.3, 0.3, 0.7, -0.3, 0.03, 4)
    limb(p, "monster_skin", 0, -0.04, [
        (0.27, 0.75), (0.22, 0.4), (0.24, 0.12), (0.2, -0.1), (0.15, -0.5), (0.17, -0.9), (0.12, -1.3), (0.14, -1.55),
    ], seg=12, lumps=0.03, seed=len(kind) + 1)
    blob(p, "bone", 0.18, 0, 0.1, -0.22, 1.0, 1.1, 1.0, rough=0.02)
    blob(p, "monster_skin", 0.22, 0, -1.65, -0.2, 0.9, 0.6, 1.5, seg=10, rings=7, rough=0.03)
    for i in range(3):
        x = (i - 1) * 0.12
        cone(p, "claw", (x, -1.7, -0.45), (x * 1.3, -1.78, -0.75), 0.05, 0.0, seg=5)
    return p


BUILDERS = {}
for _kind in KINDS:
    for _maker, _suffix in ((human_head, "Head"), (human_torso, "Torso"), (human_arm, "Arm"), (human_leg, "Leg"),
                            (monster_head, "MonsterHead"), (monster_torso, "MonsterTorso"),
                            (monster_arm, "MonsterArm"), (monster_leg, "MonsterLeg")):
        BUILDERS[_kind + _suffix] = (lambda m, k: lambda: m(k))(_maker, _kind)

if __name__ == "__main__":
    bp.BUILDERS.update(BUILDERS)
    argv = sys.argv
    names = argv[argv.index("--") + 1:] if "--" in argv else []
    sys.argv = [argv[0], "--"] + (names or list(BUILDERS.keys()))
    bp.main()
