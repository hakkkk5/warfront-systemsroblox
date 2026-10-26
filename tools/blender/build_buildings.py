"""
The Cannibal Family - Blender building exteriors.

Remodels every building in the game: the farmhouse, the ranger station, the
barn, the tool shed, the trailer, the lookout tower and the lobby's gas
station. Each one is modelled at its exact in-game size in the building's
own local space (Roblox axes, studs), so the mesh pivot is the building's
origin CFrame on the server ("origin" pivot, no fitting).

The server keeps its simple parts for collisions and wraps the ones the mesh
replaces (roof wedges, flat porch roofs, box posts) in a stand-in model with
Mesh = <Name> and MeshExact = true; clients hide those and show this mesh.
Everything else here (trim, gutters, siding on the gables, logs) is added on
top of the walls the server already built.

Run like build_props.py, e.g.
    blender -b --factory-startup -P tools/blender/build_buildings.py -- FarmhouseExteriorXL
"""

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bmesh  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import build_props as bp  # noqa: E402
from build_props import PALETTE, Prop, srgb  # noqa: E402

PALETTE.update({
    "shingle": dict(color=srgb(50, 46, 44), roblox="Slate", rough=0.9, metal=0.0, pattern="dirty"),
    "roof_deck": dict(color=srgb(46, 34, 26), roblox="Wood", rough=0.9, metal=0.0, pattern="grain_old"),
    "metal_roof": dict(color=srgb(64, 76, 60), roblox="CorrodedMetal", rough=0.7, metal=0.5, pattern="rust"),
    "barn_red": dict(color=srgb(122, 40, 32), roblox="WoodPlanks", rough=0.9, metal=0.0, pattern="chipped"),
    "siding": dict(color=srgb(104, 92, 78), roblox="WoodPlanks", rough=0.9, metal=0.0, pattern="grain_old"),
    "trim": dict(color=srgb(64, 48, 36), roblox="Wood", rough=0.8, metal=0.0, pattern="grain"),
    "log": dict(color=srgb(98, 70, 46), roblox="Wood", rough=0.9, metal=0.0, pattern="grain"),
    "aluminium": dict(color=srgb(170, 172, 174), roblox="Metal", rough=0.4, metal=0.9, pattern="dirty"),
    "concrete": dict(color=srgb(124, 120, 114), roblox="Concrete", rough=0.95, metal=0.0, pattern="dirty"),
    "trailer_paint": dict(color=srgb(196, 190, 170), roblox="Metal", rough=0.5, metal=0.2, pattern="dirty"),
    "awning_red": dict(color=srgb(150, 40, 34), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave"),
    "awning_white": dict(color=srgb(214, 206, 188), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave"),
    "clapboard": dict(color=srgb(176, 168, 148), roblox="WoodPlanks", rough=0.9, metal=0.0, pattern="chipped"),
    "clapboard_farm": dict(color=srgb(124, 120, 104), roblox="WoodPlanks", rough=0.9, metal=0.0, pattern="chipped"),
    "paint_blue": dict(color=srgb(56, 92, 140), roblox="Metal", rough=0.5, metal=0.2, pattern="chipped"),
})

# Roblox space (X right, Y up, Z back) -> Blender space (X, -Z, Y). A proper
# rotation, so faces keep their winding.
C = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
UP = Vector((0, 1, 0))


def T(x, y, z):
    return Matrix.Translation((x, y, z))


def RX(a):
    return Matrix.Rotation(a, 4, "X")


def RY(a):
    return Matrix.Rotation(a, 4, "Y")


def RZ(a):
    return Matrix.Rotation(a, 4, "Z")


def frame(xv, yv, zv, at=(0, 0, 0)):
    return Matrix((
        (xv[0], yv[0], zv[0], at[0]),
        (xv[1], yv[1], zv[1], at[1]),
        (xv[2], yv[2], zv[2], at[2]),
        (0, 0, 0, 1),
    ))


def emit(p, mat, bm, cf):
    bmesh.ops.transform(bm, matrix=C @ cf, verts=bm.verts)
    return p.add(bp.link("piece", bm), mat)


def part(p, mat, size, cf):
    """A box of Roblox size (sx, sy, sz) at Roblox CFrame cf."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    return emit(p, mat, bm, cf)


def at(p, mat, size, x, y, z):
    return part(p, mat, size, T(x, y, z))


def cyl(p, mat, r, length, cf, seg=10, r2=None):
    """A cylinder along its local Y (Roblox up), centred on cf."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r,
                          radius2=r if r2 is None else r2, depth=length)
    bmesh.ops.transform(bm, matrix=RX(-math.pi / 2), verts=bm.verts)
    return emit(p, mat, bm, cf)


def ball(p, mat, r, x, y, z, seg=14, rings=9):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    return emit(p, mat, bm, T(x, y, z))


def cyl_between(p, mat, a, b, r, seg=10):
    a, b = Vector(a), Vector(b)
    d = (b - a)
    y = d.normalized()
    x = y.cross(Vector((0, 0, 1)) if abs(y.z) < 0.9 else Vector((1, 0, 0))).normalized()
    z = x.cross(y)
    return cyl(p, mat, r, d.length, frame(x, y, z, (a + b) / 2), seg)


def beam(p, mat, a, b, width, thick, up=UP):
    """A board from a to b: `thick` along the up hint, `width` across."""
    a, b = Vector(a), Vector(b)
    d = b - a
    xv = d.normalized()
    zv = xv.cross(Vector(up))
    if zv.length < 1e-4:
        zv = xv.cross(Vector((1, 0, 0)))
    zv.normalize()
    yv = zv.cross(xv)
    return part(p, mat, (d.length, thick, width), frame(xv, yv, zv, (a + b) / 2))


def poly_slab(p, mat, pts, thick):
    """A flat polygon (Roblox points, counter-clockwise seen from outside)
    extruded inward by `thick`."""
    bm = bmesh.new()
    verts = [bm.verts.new(Vector(q)) for q in pts]
    face = bm.faces.new(verts)
    bm.normal_update()
    n = face.normal.copy()
    res = bmesh.ops.extrude_face_region(bm, geom=[face])
    moved = [e for e in res["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=-n * thick, verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return emit(p, mat, bm, Matrix.Identity(4))


def lathe_post(p, mat, profile, x, y, z, seg=12):
    """Turned post (bp.lathe profile of (radius, height)) standing at a
    Roblox point."""
    ob = bp.lathe(None, None, profile, seg=seg, loc=(x, -z, y))
    return p.add(ob, mat)


# ----------------------------------------------------------------------------- roofs
class Slope:
    """One plane of a pitched roof, from the eave line up to the ridge line,
    running along X from x0 to x1. Points are (z, y) in building space."""

    def __init__(self, x0, x1, eave, ridge):
        self.x0, self.x1 = x0, x1
        self.e = Vector((0, eave[1], eave[0]))
        r = Vector((0, ridge[1], ridge[0]))
        self.d = (r - self.e).normalized()  # up the slope
        self.length = (r - self.e).length
        n = Vector((0, self.d.z, -self.d.y))
        self.n = n if n.y > 0 else -n  # out of the roof
        self.xv = self.n.cross(self.d)  # +-X so (x, n, d) is right handed

    def point(self, x, s, h):
        """x along the ridge, s up the slope from the eave, h above the plane."""
        q = self.e + self.d * s + self.n * h
        return Vector((x, q.y, q.z))

    def cf(self, x, s, h):
        return frame(self.xv, self.n, self.d, self.point(x, s, h))

    def y_at(self, z):
        """Height of the plane above building z (inside the slope's span)."""
        t = (z - self.e.z) / self.d.z if abs(self.d.z) > 1e-6 else 0
        return self.e.y + self.d.y * t


def slab(p, mat, sl, s0, s1, h, thick, x0=None, x1=None):
    x0 = sl.x0 if x0 is None else x0
    x1 = sl.x1 if x1 is None else x1
    return part(p, mat, (abs(x1 - x0), thick, s1 - s0), sl.cf((x0 + x1) / 2, (s0 + s1) / 2, h + thick / 2))


def shingles(p, sl, rng, base, row=1.0, missing=0.03, x0=None, x1=None, s_end=None):
    """Courses of shingle strips, each a little proud at its lower edge."""
    x0 = sl.x0 if x0 is None else x0
    x1 = sl.x1 if x1 is None else x1
    s_end = sl.length if s_end is None else s_end
    s = 0.0
    while s < s_end - 0.2:
        x = x0
        while x < x1 - 0.2:
            seg = min(rng.uniform(3.0, 8.0), x1 - x)
            if rng.random() > missing:
                tilt = math.radians(rng.uniform(2.0, 4.5))
                cf = sl.cf(x + seg / 2, s + row * 0.6, base + 0.09 + rng.uniform(0, 0.03)) @ RX(tilt)
                part(p, "shingle", (seg - 0.05, 0.11, row * 1.25), cf)
            x += seg
        s += row


def corrugated(p, mat, sl, base, x0, x1, s0=0.0, s1=None, pitch=1.25):
    s1 = sl.length if s1 is None else s1
    slab(p, mat, sl, s0, s1, base, 0.18, x0, x1)
    x = x0 + pitch / 2
    while x < x1:
        part(p, mat, (0.24, 0.16, s1 - s0), sl.cf(x, (s0 + s1) / 2, base + 0.18 + 0.08))
        x += pitch


def ridge_cap(p, mat, slopes, x0, x1, base, width=0.9):
    for sl in slopes:
        slab(p, mat, sl, sl.length - width, sl.length + 0.1, base + 0.12, 0.12, x0, x1)


def fascia(p, mat, sl, base, x0, x1, depth=1.0):
    """Board hanging under the eave edge."""
    q = sl.point(0, 0, base)
    at(p, mat, (abs(x1 - x0), depth, 0.25), (x0 + x1) / 2, q.y - depth / 2 + 0.2, q.z)


def rake(p, mat, sl, base, x, depth=0.9):
    """Barge board along the gable edge of a slope at end x."""
    a = sl.point(x, -0.05, base + 0.1)
    b = sl.point(x, sl.length + 0.05, base + 0.1)
    beam(p, mat, a - UP * depth / 2, b - UP * depth / 2, 0.25, depth)


def gable_boards(p, mat, x_face, z0, z1, y0, slopes, width=1.1, battens=False):
    """Vertical boards closing the gable triangle on the plane x = x_face,
    each up to the roof plane at its inner corner (the overshoot hides in the
    roof slab)."""
    z = z0
    out = 1 if x_face > 0 else -1
    while z < z1 - 0.05:
        w = min(width, z1 - z)
        zi = z + w if abs(z + w) < abs(z) else z  # corner nearer the ridge
        top = max(sl.y_at(zi) for sl in slopes if min(sl.e.z, sl.e.z + sl.d.z * sl.length) - 0.01 <= zi <= max(sl.e.z, sl.e.z + sl.d.z * sl.length) + 0.01) if slopes else y0
        h = top - y0
        if h > 0.05:
            at(p, mat, (0.2, h, w - 0.05), x_face + out * 0.1, y0 + h / 2, z + w / 2)
            if battens:
                at(p, mat, (0.12, h, 0.25), x_face + out * 0.26, y0 + h / 2, z + w)
        z += w


def gutter(p, x0, x1, z, y):
    cyl_between(p, "iron", (x0, y, z), (x1, y, z), 0.32, seg=8)


def downspout(p, x, z_gutter, z_wall, y_top, y_bottom):
    """From the gutter back to the wall, down it, and a kick out at the foot."""
    y_bend = y_top - (1.2 if abs(z_gutter - z_wall) > 0.05 else 0)
    if y_bend < y_top:
        cyl_between(p, "iron", (x, y_top, z_gutter), (x, y_bend, z_wall), 0.2, seg=8)
    cyl_between(p, "iron", (x, y_bend, z_wall), (x, y_bottom + 0.6, z_wall), 0.2, seg=8)
    out = 1 if z_wall > 0 else -1
    cyl_between(p, "iron", (x, y_bottom + 0.6, z_wall), (x, y_bottom, z_wall + out * 0.9), 0.2, seg=8)


# ----------------------------------------------------------------------------- walls
class Face:
    """An exterior wall face: plane at `plane` on axis 'z' (runs along X) or
    'x' (runs along Z), with `sign` the outward direction."""

    def __init__(self, axis, plane, sign):
        self.axis, self.plane, self.sign = axis, plane, sign

    def cf(self, along, y, out):
        if self.axis == "z":
            return T(along, y, self.plane + self.sign * out)
        return T(self.plane + self.sign * out, y, along) @ RY(math.pi / 2)

    def box(self, p, mat, w, h, d, along, y, out):
        return part(p, mat, (w, h, d), self.cf(along, y, out + d / 2))


def window_trim(p, face, along, y0, y1, width, mat="trim", drip=True):
    h = y1 - y0
    for side in (-1, 1):
        face.box(p, mat, 0.5, h + 0.5, 0.18, along + side * (width / 2 + 0.25), (y0 + y1) / 2, 0)
    face.box(p, mat, width + 1.4, 0.55, 0.22, along, y1 + 0.3, 0)
    if drip:
        face.box(p, mat, width + 1.8, 0.16, 0.45, along, y1 + 0.66, 0)
    face.box(p, mat, width + 1.2, 0.28, 0.6, along, y0 - 0.12, 0)


def door_trim(p, face, along, width, height, mat="trim", pediment=True):
    for side in (-1, 1):
        face.box(p, mat, 0.7, height + 0.4, 0.3, along + side * (width / 2 + 0.35), (height + 0.4) / 2, 0)
    face.box(p, mat, width + 1.6, 0.9, 0.35, along, height + 0.45, 0)
    if pediment:
        face.box(p, mat, width + 2.2, 0.3, 0.7, along, height + 1.05, 0)


def band(p, face, mat, a0, a1, y0, y1, depth, gaps=()):
    """Horizontal board from a0 to a1 along the face, skipping gaps."""
    runs = [(a0, a1)]
    for g0, g1 in gaps:
        nxt = []
        for r0, r1 in runs:
            if g1 <= r0 or g0 >= r1:
                nxt.append((r0, r1))
            else:
                if g0 > r0:
                    nxt.append((r0, g0))
                if g1 < r1:
                    nxt.append((g1, r1))
        runs = nxt
    for r0, r1 in runs:
        if r1 - r0 > 0.1:
            face.box(p, mat, r1 - r0, y1 - y0, depth, (r0 + r1) / 2, (y0 + y1) / 2, 0)


def corner_boards(p, mat, xs, zs, y0, y1, w=0.9):
    """L-shaped corner boards on a rectangle whose outer faces are at x = +-xs,
    z = +-zs."""
    for sx in (-1, 1):
        for sz in (-1, 1):
            at(p, mat, (w, y1 - y0, 0.22), sx * (xs - w / 2 + 0.11), (y0 + y1) / 2, sz * (zs + 0.11))
            at(p, mat, (0.22, y1 - y0, w), sx * (xs + 0.11), (y0 + y1) / 2, sz * (zs - w / 2 + 0.11))


# ============================================================================ farmhouse
def build_farmhouse():
    """CannibalHouse (House.luau + HouseWings.luau), origin O = floor level of
    the ground floor: the two-storey core with a lower-roofed wing either
    side, on the bigger floor plan (house_layout: the plan's numbers mapped,
    windows and doors keep their width)."""
    from house_layout import fx, fz
    p = Prop("FarmhouseExteriorXL", pivot="origin")
    rng = random.Random(7)
    X0, X1 = fx(-35.3), fx(35.3)
    W = fx(68.7)  # outer face of the wing end walls
    # the hidden wedges' sloped faces: (z, y) eave (fz(-26), 25) -> (1, 36),
    # and the eave a stud further out
    k = 11 / (fz(1) - fz(-26))
    front = Slope(X0, X1, (fz(-27), 25 - k), (0.0, 36 - k))
    back = Slope(X0, X1, (-fz(-27), 25 - k), (0.0, 36 - k))
    for sl in (front, back):
        slab(p, "roof_deck", sl, 0, sl.length + 0.02, 0, 0.5)
        shingles(p, sl, rng, 0.5, row=1.3)  # keeps the shingle mesh under 20k tris
        fascia(p, "trim", sl, 0, X0, X1)
        for x in (X0, X1):
            rake(p, "trim", sl, 0.5, x)
        x = X0 + 1.2
        while x < X1:
            a = sl.point(x, 0.0, -0.25)
            b = sl.point(x, 2.6, -0.25)
            beam(p, "trim", a, b, 0.35, 0.5, up=sl.n)
            x += 2.4
        # the main gutters drain onto the wing roofs
        q = sl.point(0, 0, 0)
        zg = q.z + (-0.45 if q.z < 0 else 0.45)
        gutter(p, X0 + 3.9, X1 - 3.9, zg, q.y - 0.3)
    ridge_cap(p, "shingle", (front, back), X0, X1, 0.6)

    # the wings: same eaves, a lower ridge (the server wedges: 8 high, from
    # fz(-26) to 0.5 deep)
    wing_slope = 8 / (fz(0.5) - fz(-26))
    for side in (-1, 1):
        xa, xb = (-W - 1.6, fx(-31.6)) if side < 0 else (fx(31.6), W + 1.6)
        wf = Slope(xa, xb, (fz(-27.3), 25 - wing_slope * 1.3), (0.0, 33 - wing_slope * 0.5))
        wb = Slope(xa, xb, (-fz(-27.3), 25 - wing_slope * 1.3), (0.0, 33 - wing_slope * 0.5))
        x_end = xa if side < 0 else xb
        for sl in (wf, wb):
            slab(p, "roof_deck", sl, 0, sl.length + 0.02, 0, 0.45)
            shingles(p, sl, rng, 0.45, row=1.6)  # keeps the shingle mesh under 20k tris
            fascia(p, "trim", sl, 0, xa, xb)
            rake(p, "trim", sl, 0.45, x_end)
            x = xa + 1.2
            while x < xb:
                a = sl.point(x, 0.0, -0.25)
                b = sl.point(x, 2.6, -0.25)
                beam(p, "trim", a, b, 0.35, 0.5, up=sl.n)
                x += 2.4
            q = sl.point(0, 0, 0)
            zg = q.z + (-0.45 if q.z < 0 else 0.45)
            gutter(p, xa + 0.3, xb - 0.3, zg, q.y - 0.3)
            zw = fz(24.95) if q.z > 0 else -fz(24.95)
            downspout(p, side * (W - 1.6), zg, zw, q.y - 0.4, -1.0)
            downspout(p, side * fx(36.0), zg, zw, q.y - 0.4, -1.0)
        ridge_cap(p, "shingle", (wf, wb), xa, xb, 0.55)
        # the wing's end gable, with a louvred vent
        xf = side * W
        gable_boards(p, "siding", xf, -fz(24.7), fz(24.7), 24.0, (wf, wb), battens=True)
        at(p, "trim", (0.3, 2.6, 3.2), xf + side * 0.4, 28.6, 0)
        for i in range(4):
            part(p, "wood_dark", (0.12, 0.42, 2.6), T(xf + side * 0.6, 27.7 + i * 0.6, 0) @ RZ(side * 0.6))
    # what shows of the main gables above the wing roofs
    for xf in (fx(-32.7), fx(32.7)):
        gable_boards(p, "siding", xf, -fz(12.0), fz(12.0), 32.6, (front, back), battens=True)
    # frieze closing the gap between the wall tops and the roofs
    for zf in (-fz(24.85), fz(24.85)):
        at(p, "trim", (2 * W, 2.0, 0.3), 0, 24.8, zf)

    front_face = Face("z", -fz(24.7), -1)
    back_face = Face("z", fz(24.7), 1)
    left = Face("x", -W, -1)
    right = Face("x", W, 1)
    # windows: (face, along, floor) - the same openings House.luau and
    # HouseWings.luau cut, at their centres in the bigger house
    windows = []
    for a in (-58, -42, -20, -12, 12, 22, 42, 58):
        windows += [(front_face, fx(a), 0), (front_face, fx(a), 13)]
    for a in (-57, -45, -20, 20, 45, 57):
        windows.append((back_face, fx(a), 0))
    for a in (-50, -18, 18, 50):
        windows.append((back_face, fx(a), 13))
    windows += [(left, fz(-12), 0), (left, fz(-12), 13), (left, fz(12), 13)]
    windows += [(right, fz(-12), 0), (right, fz(14), 0), (right, fz(-12), 13), (right, fz(12), 13)]
    for face, a, y0 in windows:
        window_trim(p, face, a, y0 + 4, y0 + 8.5, 4)
    back_door = fx(2.5)
    door_trim(p, front_face, 0, 5, 9)
    door_trim(p, back_face, back_door, 4.6, 9, pediment=False)
    # belly band between the floors, water table at the bottom, corner boards,
    # and pilasters where the wings meet the old house
    ZS = fz(24.7)
    for face, span, doors in ((front_face, W, [(-2.5, 2.5)]), (back_face, W, [(back_door - 2.3, back_door + 2.3)]), (left, ZS, []), (right, ZS, [])):
        band(p, face, "trim", -span, span, 11.9, 12.9, 0.25)
        band(p, face, "trim", -span, span, 0.0, 0.7, 0.3, doors)
    corner_boards(p, "trim", W, ZS, 0, 24.6)
    for sx in (-1, 1):
        for face in (front_face, back_face):
            face.box(p, "trim", 1.1, 24.6, 0.26, sx * fx(32.7), 12.3, 0)

    # the walls: lap siding on every outside face, both floors, cut round
    # every window and door (the server's flat siding layer is hidden).
    # Openings: (centre, width, bottom, top) per floor.
    def wins(*centres, along=fx):
        return [(along(c), 4.6, 3.8, 8.7) for c in centres]

    Z = fz(24.5)
    siding = (
        (Face("z", -Z, -1), -W + 0.2, W - 0.2, {0.0: [(0, 5.4, -1, 9.2)] + wins(-58, -42, -20, -12, 12, 22, 42, 58), 13.0: wins(-58, -42, -20, -12, 12, 22, 42, 58)}),
        (Face("z", Z, 1), -W + 0.2, W - 0.2, {0.0: [(back_door, 5.0, -1, 9.2)] + wins(-57, -45, -20, 20, 45, 57), 13.0: wins(-50, -18, 18, 50)}),
        (Face("x", -W + 0.2, -1), -ZS, ZS, {0.0: wins(-12, along=fz), 13.0: wins(-12, 12, along=fz)}),
        (Face("x", W - 0.2, 1), -ZS, ZS, {0.0: wins(-12, 14, along=fz), 13.0: wins(-12, 12, along=fz)}),
    )
    for face, a0, a1, floors in siding:
        for y0, ops in floors.items():
            # from the water table (ground) or the belly band (upper) to the
            # belly band or the frieze
            y, top, row = y0 + (1.0 if y0 == 0 else 0.2), y0 + (11.75 if y0 == 0 else 10.6), 0
            while y < top:
                gaps = [(c - w / 2, c + w / 2) for (c, w, b, t) in ops if y0 + b - 0.3 < y < y0 + t + 0.3]
                band(p, face, "clapboard_farm", a0, a1, y - 0.31, y + 0.31, 0.12 if row % 2 == 0 else 0.17, gaps)
                y += 0.55
                row += 1
            for _ in range(int((a1 - a0) / 4)):
                a, yy = rng.uniform(a0 + 1, a1 - 1), rng.uniform(y0 + 1.2, top - 0.5)
                if not any(c - w / 2 - 0.6 < a < c + w / 2 + 0.6 and y0 + b - 0.6 < yy < y0 + t + 0.6 for (c, w, b, t) in ops):
                    face.box(p, "siding", rng.uniform(0.5, 2.2), rng.uniform(0.25, 0.6), 0.05, a, yy, 0.16)

    # chimney: brick stack with a corbelled top and two clay pots
    cx, cz = fx(-30), fz(-12)
    at(p, "brick", (4, 18.2, 4), cx, 28.1, cz)
    at(p, "brick", (4.5, 0.6, 4.5), cx, 35.9, cz)
    at(p, "brick", (4.9, 0.6, 4.9), cx, 36.5, cz)
    at(p, "concrete", (5.1, 0.4, 5.1), cx, 37.0, cz)
    for dx in (-0.9, 0.9):
        cyl(p, "brick", 0.45, 1.3, T(cx + dx, 37.85, cz), seg=10, r2=0.38)
    # flashing where it meets the roof
    y_roof = front.y_at(cz) + 0.6
    at(p, "iron", (4.3, 0.35, 4.3), cx, y_roof, cz)

    # porch: a shed roof on turned posts, header beam and brackets
    px, pz = fx(11.0), fz(-33)
    porch = Slope(-px, px, (fz(-34.6), 11.25), (fz(-24.75), 13.4))
    slab(p, "roof_deck", porch, 0, porch.length, 0, 0.35)
    shingles(p, porch, rng, 0.35, row=0.95)
    fascia(p, "trim", porch, 0, -px, px, depth=0.8)
    for x in (-px, px):
        rake(p, "trim", porch, 0.35, x, depth=0.6)
    at(p, "trim", (2 * fx(10.8), 0.6, 0.6), 0, 11.3, pz)
    at(p, "trim", (2 * px, 0.5, 0.4), 0, 13.1, fz(-24.95))  # ledger on the wall
    for x in (fx(-9.5), fx(9.5)):
        lathe_post(p, "trim", bp.turned_leg(11.0, 0.36), x, 0, pz)
        for side in (-1, 1):
            if abs(x + side * 1.7) < fx(10.5):
                beam(p, "trim", (x + side * 0.2, 9.3, pz), (x + side * 1.7, 11.0, pz), 0.25, 0.25)
    return p


# ============================================================================ ranger station
def logs_on(p, face, a0, a1, y_first, courses, openings, ext, r=0.47):
    for i in range(courses):
        y = y_first + i * 0.92
        runs = [(a0 - ext, a1 + ext)]
        for (oc, ow, ob, ot) in openings:
            if y + r > ob and y - r < ot:
                g0, g1 = oc - ow / 2, oc + ow / 2
                nxt = []
                for r0, r1 in runs:
                    if g1 <= r0 or g0 >= r1:
                        nxt.append((r0, r1))
                    else:
                        if g0 > r0:
                            nxt.append((r0, g0))
                        if g1 < r1:
                            nxt.append((g1, r1))
                runs = nxt
        for r0, r1 in runs:
            if r1 - r0 > 0.3:
                mid = (r0 + r1) / 2
                if face.axis == "z":
                    cyl(p, "log", r, r1 - r0, T(mid, y, face.plane) @ RZ(-math.pi / 2))
                else:
                    cyl(p, "log", r, r1 - r0, T(face.plane, y, mid) @ RX(math.pi / 2))


def build_station():
    """RangerStation (Sites.luau buildStation): w 40, d 28, h 11, log walls."""
    p = Prop("RangerStationExterior", pivot="origin")
    X0, X1 = -22.6, 22.6
    front = Slope(X0, X1, (-16.3, 11.5 - 7 / 16 * 0.8), (0.5, 18.5))
    back = Slope(X0, X1, (16.3, 11.5 - 7 / 16 * 0.8), (-0.5, 18.5))
    for sl in (front, back):
        corrugated(p, "metal_roof", sl, 0.0, X0, X1)
        fascia(p, "trim", sl, 0, X0, X1, depth=0.8)
        for x in (X0, X1):
            rake(p, "trim", sl, 0.3, x, depth=0.7)
    ridge_cap(p, "metal_roof", (front, back), X0, X1, 0.42, width=0.8)
    for xf in (-20.5, 20.5):
        gable_boards(p, "siding", xf, -14.5, 14.5, 11.0, (front, back), width=1.0, battens=True)
    # log walls: courses on the long faces sit half a log below the ends'
    fz = Face("z", -14.5, -1)
    bz = Face("z", 14.5, 1)
    lx = Face("x", -20.5, -1)
    rx = Face("x", 20.5, 1)

    def win(c):
        return (c, 4.2, 3.5, 7.5)

    logs_on(p, fz, -20.5, 20.5, 0.47, 12, [(0, 5.2, 0, 9), win(-12), win(12)], 1.1)
    logs_on(p, bz, -20.5, 20.5, 0.47, 12, [win(-12), win(8)], 1.1)
    logs_on(p, lx, -14.5, 14.5, 0.93, 11, [win(0)], 1.1)
    logs_on(p, rx, -14.5, 14.5, 0.93, 11, [win(-4)], 1.1)
    for face, a in ((fz, -12), (fz, 12), (bz, -12), (bz, 8), (lx, 0), (rx, -4)):
        window_trim(p, face, a, 3.5, 7.5, 4, drip=False)
    door_trim(p, fz, 0, 5, 9, pediment=False)
    # porch: metal shed roof on log posts with knee braces
    porch = Slope(-10.2, 10.2, (-21.9, 10.45), (-14.6, 11.3))
    corrugated(p, "metal_roof", porch, 0.0, -10.2, 10.2)
    fascia(p, "trim", porch, 0, -10.2, 10.2, depth=0.6)
    cyl(p, "log", 0.36, 19.6, T(0, 10.25, -20.5) @ RZ(-math.pi / 2))
    for x in (-8.5, 8.5):
        cyl(p, "log", 0.38, 10.25, T(x, 5.12, -20.5))
        for side in (-1, 1):
            beam(p, "log", (x, 8.0, -20.5), (x + side * 2.0, 10.1, -20.5), 0.3, 0.3)
    # stovepipe and the radio mast
    y0 = front.y_at(-6)
    cyl(p, "metal_dark", 0.42, 4.6, T(14, y0 + 2.1, -6))
    cyl(p, "metal_dark", 0.85, 0.7, T(14, y0 + 4.7, -6), r2=0.1)
    yb = back.y_at(3)
    cyl(p, "steel", 0.14, 14.0, T(-17, yb + 6.8, 3), seg=8)
    for i, w in enumerate((5.0, 4.0, 3.0, 2.2)):
        at(p, "steel", (0.12, 0.12, w), -17, yb + 8.5 + i * 1.6, 3)
    for side in (-1, 1):
        zw = 3 + side * 2.5
        beam(p, "steel", (-17, yb + 6, 3), (-17 + side * 4, back.y_at(zw), zw), 0.06, 0.06)
    return p


# ============================================================================ barn
def build_barn():
    """Barn (Sites.luau shed 30 x 40 x 16, broken roof). Ridge along X."""
    p = Prop("BarnExterior", pivot="origin")
    rng = random.Random(5)
    X0, X1 = -15.6, 15.6
    front = Slope(X0, X1, (-21.3, 16 - 9 / 21 * 0.55), (0.0, 16 + 9 * 20.75 / 21))
    back = Slope(X0, X1, (21.3, 16 - 9 / 21 * 0.55), (0.0, 16 + 9 * 20.75 / 21))
    # the skeleton: rafters, purlins and the ridge beam all the way across
    for sl in (front, back):
        x = X0 + 0.3
        while x <= X1:
            beam(p, "wood_old", sl.point(x, 0, -0.35), sl.point(x, sl.length, -0.35), 0.4, 0.7, up=sl.n)
            x += (X1 - X0 - 0.6) / 12
        for k in range(1, 7):
            s = k * sl.length / 7
            part(p, "wood_old", (X1 - X0, 0.35, 0.5), sl.cf(0, s, 0.17))
    at(p, "wood_old", (X1 - X0, 0.9, 0.6), 0, front.point(0, front.length, -0.6).y, 0)
    # what is left of the tin: the panels the server's wedges cover
    corrugated(p, "metal_roof", front, 0.35, -14.25, -0.75)
    corrugated(p, "metal_roof", back, 0.35, -3.6, 14.4)
    # torn sheets hanging off the edges
    for sl, x, s, ang in ((front, 0.6, 8.0, 0.5), (back, -5.2, 12.0, -0.45), (front, -15.0, 2.0, 0.3)):
        part(p, "metal_roof", (2.6, 0.12, 5.0), sl.cf(x, s, 0.4) @ RZ(ang) @ RX(0.35 * rng.uniform(0.6, 1.2)))
    for sl in (front, back):
        fascia(p, "paint_white", sl, 0, X0, X1, depth=0.8)
    # gables in red boards with white battens, a hayloft door on the east end
    for xf in (-15.4, 15.4):
        gable_boards(p, "barn_red", xf, -20.4, 20.4, 16.0, (front, back), width=1.2, battens=True)
    for sl in (front, back):
        for x in (X0, X1):
            rake(p, "paint_white", sl, 0.2, x, depth=0.7)
    loft = Face("x", 15.4, 1)
    loft.box(p, "barn_red", 5.0, 4.6, 0.3, 0, 19.3, 0.3)
    for (w, h, a, y) in ((5.6, 0.4, 0, 21.8), (5.6, 0.4, 0, 16.8), (0.4, 5.0, -2.6, 19.3), (0.4, 5.0, 2.6, 19.3)):
        loft.box(p, "paint_white", w, h, 0.2, a, y, 0.6)
    for s in (-1, 1):
        part(p, "paint_white", (0.2, 0.35, 6.4), T(15.4 + 0.75, 19.3, 0) @ RX(s * math.atan2(4.6, 5.0)))
    at(p, "wood_old", (4.0, 0.5, 0.5), 15.4 + 2.0, 23.3, 0)
    cyl(p, "rope", 0.06, 4.0, T(15.4 + 3.6, 21.3, 0), seg=6)
    # the big doors, slid open on their track
    fr = Face("z", -20.4, -1)
    fr.box(p, "steel", 26.0, 0.3, 0.3, 0, 10.7, 0.2)
    for a in (-9.1, 9.1):
        fr.box(p, "barn_red", 6.0, 10.0, 0.3, a, 5.2, 0.45)
        for (w, h, da, y) in ((6.0, 0.4, 0, 10.0), (6.0, 0.4, 0, 0.4), (0.4, 10.0, -2.8, 5.2), (0.4, 10.0, 2.8, 5.2)):
            fr.box(p, "paint_white", w, h, 0.15, a + da, y, 0.75)
        for s in (-1, 1):
            part(p, "paint_white", (0.35, 10.8, 0.12), T(a, 5.2, -20.4 - 0.85) @ RZ(s * math.atan2(5.6, 9.6)))
        for da in (-2.0, 2.0):
            cyl(p, "steel", 0.25, 0.3, T(a + da, 10.7, -20.4 - 0.45) @ RX(math.pi / 2), seg=8)
    corner_boards(p, "paint_white", 15.4, 20.4, 0, 16.0)
    return p


# ============================================================================ tool shed
def build_tool_shed():
    """ToolShed (Sites.luau shed 12 x 10 x 9, door 4.5)."""
    p = Prop("ToolShedExterior", pivot="origin")
    rng = random.Random(11)
    X0, X1 = -7.3, 7.3
    front = Slope(X0, X1, (-6.1, 9 - 3.6 / 6 * 0.35), (0.25, 12.6))
    back = Slope(X0, X1, (6.1, 9 - 3.6 / 6 * 0.35), (-0.25, 12.6))
    for sl in (front, back):
        slab(p, "roof_deck", sl, 0, sl.length, 0, 0.3)
        shingles(p, sl, rng, 0.3, row=0.9, missing=0.08)
        fascia(p, "trim", sl, 0, X0, X1, depth=0.6)
        for x in (X0, X1):
            rake(p, "trim", sl, 0.3, x, depth=0.55)
    ridge_cap(p, "shingle", (front, back), X0, X1, 0.42, width=0.7)
    for xf in (-6.4, 6.4):
        gable_boards(p, "siding", xf, -5.4, 5.4, 9.0, (front, back), width=0.9)
    door_trim(p, Face("z", -5.4, -1), 0, 4.5, 8, pediment=False)
    corner_boards(p, "trim", 6.4, 5.4, -0.4, 9.2, w=0.6)
    return p


# ============================================================================ trailer
def build_trailer():
    """Trailer (Sites.luau buildTrailer): w 10, d 26, h 8, thin metal walls."""
    p = Prop("TrailerExterior", pivot="origin")
    # rounded roof
    at(p, "trailer_paint", (9.7, 0.4, 25.7), 0, 8.3, 0)
    for sx in (-1, 1):
        cyl(p, "trailer_paint", 0.5, 25.7, T(sx * 4.85, 8.0, 0) @ RX(math.pi / 2), seg=12)
    for sz in (-1, 1):
        cyl(p, "trailer_paint", 0.5, 9.7, T(0, 8.0, sz * 12.85) @ RZ(-math.pi / 2), seg=12)
    at(p, "aluminium", (2.8, 1.1, 2.6), 0, 9.05, 3)
    for i in range(5):
        at(p, "metal_dark", (2.4, 0.08, 0.16), 0, 9.62, 2.0 + i * 0.5)
    at(p, "aluminium", (1.4, 0.45, 1.4), 0, 8.7, -7)
    # ribbed siding between the stripe and the roof, around the openings
    faces = {
        "front": (Face("z", -13.2, -1), -5.2, 5.2, [(0, 4.4, 3, 6)]),
        "back": (Face("z", 13.2, 1), -5.2, 5.2, []),
        "left": (Face("x", -5.2, -1), -13.2, 13.2, [(-6, 4.4, 3.5, 6.5), (6, 4.4, 3.5, 6.5)]),
        "right": (Face("x", 5.2, 1), -13.2, 13.2, [(2, 4.0, 0, 7), (-8, 4.4, 3.5, 6.5)]),
    }
    for face, a0, a1, openings in faces.values():
        y = 2.2
        while y < 7.6:
            gaps = [(c - w / 2, c + w / 2) for (c, w, b, t) in openings if b - 0.1 < y < t + 0.1]
            band(p, face, "trailer_paint", a0, a1, y - 0.07, y + 0.07, 0.08, gaps)
            y += 0.55
        for (c, w, b, t) in openings:
            if b > 0:
                window_trim(p, face, c, b, t, w - 0.4, mat="aluminium", drip=False)
            else:
                door_trim(p, face, c, w - 0.2, t, mat="aluminium", pediment=False)
    # striped awning over the side door
    stripes = 6
    for i in range(stripes):
        z0 = -0.6 + i * (5.2 / stripes)
        z1 = z0 + 5.2 / stripes
        zc = (z0 + z1) / 2
        beam(p, "awning_red" if i % 2 == 0 else "awning_white", (5.3, 7.6, zc), (8.7, 6.9, zc), z1 - z0, 0.08)
    for zc in (-0.4, 4.4):
        cyl(p, "aluminium", 0.08, 9.6, T(8.55, 2.1, zc), seg=6)
    # propane bottles on the tongue
    for x in (-0.8, 0.8):
        cyl(p, "paint_white", 0.6, 2.0, T(x, -0.3, -15.0), seg=12)
        cyl(p, "steel", 0.22, 0.4, T(x, 0.9, -15.0), seg=8)
    at(p, "iron", (3.2, 0.2, 1.6), 0, -1.35, -15.0)
    return p


# ============================================================================ lookout tower
def build_tower_roof():
    """LookoutTower cab roof (Sites.luau buildTower, h 30): a hipped tin roof."""
    p = Prop("LookoutTowerRoof", pivot="origin")
    y0, e = 38.45, 7.6
    apex = Vector((0, 42.6, 0))
    corners = [Vector((-e, y0, -e)), Vector((e, y0, -e)), Vector((e, y0, e)), Vector((-e, y0, e))]
    for i in range(4):
        a, b = corners[i], corners[(i + 1) % 4]
        poly_slab(p, "metal_roof", [b, a, apex], 0.25)
        for k in range(1, 6):
            t = k / 6
            q = a.lerp(b, t)
            beam(p, "metal_roof", q + UP * 0.12, apex.lerp(q, 0.03) + UP * 0.1, 0.18, 0.14)
        beam(p, "trim", a - UP * 0.35, b - UP * 0.35, 0.25, 0.7)
    cyl(p, "steel", 0.25, 1.2, T(0, 43.1, 0), seg=8, r2=0.05)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=0.35)
    emit(p, "steel", bm, T(0, 42.75, 0))
    return p


# ============================================================================ lobby gas station
def build_gas_station():
    """Lobby store and canopy (Lobby.luau), origin = the lobby ORIGIN."""
    p = Prop("GasStationExterior", pivot="origin")
    rng = random.Random(3)
    # store block x -31..3, y 0..12, z 17..35; its front faces -Z
    x0, x1, z0, z1 = -31.0, 3.0, 17.0, 35.0
    at(p, "roof_deck", (34.4, 0.5, 18.4), -14, 12.25, 26)
    # parapet with a metal coping, taller and stepped at the front
    for (sx, sy, sz, cx, cy, cz) in (
        (34.6, 2.4, 0.6, -14, 13.2, 17.2),
        (34.6, 1.4, 0.5, -14, 12.7, 35.1),
        (0.5, 1.4, 18.0, -31.1, 12.7, 26),
        (0.5, 1.4, 18.0, 2.9, 12.7, 26),
    ):
        at(p, "siding", (sx, sy, sz), cx, cy, cz)
        at(p, "iron", (sx + 0.3, 0.2, sz + 0.3), cx, cy + sy / 2 + 0.1, cz)
    at(p, "trim", (35.4, 0.35, 0.9), -14, 12.05, 16.75)
    # rooftop: AC unit, vents
    at(p, "aluminium", (4.0, 2.0, 3.0), -6, 13.5, 30)
    cyl(p, "metal_dark", 1.1, 0.3, T(-6, 14.6, 30), seg=14)
    for (vx, vz) in ((-24, 31), (-20, 22), (-2, 24)):
        cyl(p, "metal_dark", 0.3, 1.6, T(vx, 13.3, vz), seg=8)
        cyl(p, "metal_dark", 0.5, 0.3, T(vx, 14.2, vz), seg=8, r2=0.1)
    # front awning on brackets, over the windows and the door
    aw = Slope(-31.6, 3.6, (12.9, 10.6), (16.95, 11.7))
    corrugated(p, "metal_roof", aw, 0.0, -31.6, 3.6, pitch=1.1)
    fascia(p, "paint_white", aw, 0, -31.6, 3.6, depth=0.55)
    for bx in (-30.5, -22, -14, -6, 2.5):
        beam(p, "metal_dark", (bx, 8.6, 16.95), (bx, 10.55, 13.4), 0.18, 0.18)
    front = Face("z", z0, -1)
    for wx in (-24, -4):
        window_trim(p, front, wx, 2.8, 7.2, 8, mat="aluminium", drip=False)
        for k in (-1, 1):
            front.box(p, "aluminium", 0.2, 4.4, 0.12, wx + k * 1.4, 5.0, 0.3)
    door_trim(p, front, -14, 4, 8, mat="aluminium", pediment=False)
    # stone wainscot under the windows
    band(p, front, "stone", x0, x1, 0, 1.9, 0.35, [(-16.3, -11.7)])
    # front walk, a hair above the asphalt (top 0.3) so the two never fight
    at(p, "concrete", (34.6, 0.3, 4.2), -14, 0.2, 14.9)
    for sx in (x0, x1):
        at(p, "trim", (0.6, 12.2, 0.6), sx, 6.1, z0 - 0.2)
    # downspouts at the front corners, from the parapet scuppers
    for sx in (x0 + 0.3, x1 - 0.3):
        downspout(p, sx, z0 - 0.45, z0 - 0.45, 12.3, 0.1)
    # ---- the store itself (the server's plain box is hidden): a core, lap
    # siding with peeling paint around the windows and door, a back door
    at(p, "siding", (33.8, 11.9, 17.8), -14, 5.95, 26)
    faces = (
        (Face("z", z0, -1), x0, x1, [(-28.3, -19.7, 2.6, 7.4), (-16.4, -11.6, 0, 8.3), (-8.3, 0.3, 2.6, 7.4)], 2.2),
        (Face("z", z1, 1), x0, x1, [(-6.4, -1.6, 0, 8.3)], 0.3),
        (Face("x", x0, -1), z0, z1, [(23.6, 28.4, 2.8, 7.2)], 0.3),
        (Face("x", x1, 1), z0, z1, [], 0.3),
    )
    for face, a0, a1, gaps, y in faces:
        row = 0
        while y < 11.7:
            g = [(o0, o1) for (o0, o1, b, t) in gaps if b - 0.3 < y < t + 0.3]
            band(p, face, "clapboard", a0, a1, y - 0.31, y + 0.31, 0.12 if row % 2 == 0 else 0.17, g)
            y += 0.55
            row += 1
    # paint flaking off to the grey wood
    for _ in range(36):
        face, a0, a1, gaps, y0 = faces[rng.randrange(4)]
        a, y = rng.uniform(a0 + 1, a1 - 1), rng.uniform(y0 + 0.4, 11)
        if not any(o0 - 0.5 < a < o1 + 0.5 and b - 0.5 < y < t + 0.5 for (o0, o1, b, t) in gaps):
            face.box(p, "siding", rng.uniform(0.4, 1.6), rng.uniform(0.2, 0.5), 0.06, a, y, 0.15)
    back = Face("z", z1, 1)
    back.box(p, "metal_dark", 4.4, 8.2, 0.15, -4, 4.1, 0.0)
    door_trim(p, back, -4, 4.4, 8.2, mat="trim", pediment=False)
    side = Face("x", x0, -1)
    side.box(p, "glass_dark", 4.4, 4.4, 0.1, 26, 5.0, 0.0)
    window_trim(p, side, 26, 2.8, 7.2, 4.4, mat="aluminium", drip=False)
    # ice chest and a propane cage against the east wall, tyres by the west wall
    at(p, "paint_white", (2.2, 3.2, 4.2), 4.3, 1.9, 22.5)
    at(p, "paint_blue", (2.25, 0.6, 4.25), 4.3, 2.5, 22.5)
    at(p, "aluminium", (2.3, 0.15, 4.3), 4.3, 3.55, 22.5)
    cx, cz = 4.6, 30.5
    for dx in (-1.2, 1.2):
        for dz in (-2.3, 2.3):
            at(p, "steel", (0.12, 5.0, 0.12), cx + dx, 2.8, cz + dz)
    for yy in (0.4, 2.8, 5.2):
        for dz in (-2.3, 2.3):
            at(p, "steel", (2.5, 0.1, 0.1), cx, yy, cz + dz)
        for dx in (-1.2, 1.2):
            at(p, "steel", (0.1, 0.1, 4.7), cx + dx, yy, cz)
    for i in range(4):
        cyl(p, "paint_white", 0.42, 2.0, T(cx + (i % 2 - 0.5) * 1.0, 1.5, cz - 1.5 + i * 1.0), seg=12)
        ball(p, "paint_white", 0.42, cx + (i % 2 - 0.5) * 1.0, 2.5, cz - 1.5 + i * 1.0)
    for i in range(4):
        bp.torus(p, "rubber", 0.95, 0.4, (-33.2, -29.5, 0.45 + i * 0.82), seg=20, tseg=8)
    cyl(p, "steel", 0.8, 2.6, T(-10, 1.6, 15.4), seg=14)
    cyl(p, "metal_dark", 0.85, 0.2, T(-10, 2.95, 15.4), seg=14)

    # ---- the canopy over the pumps (the server's slab, band and posts are hidden)
    cx0, cx1, cz0, cz1 = -31.2, 3.2, -20.2, 4.2
    at(p, "paint_white", (34.4, 0.8, 24.4), -14, 10.2, -8)
    for (sx, sz, ccx, ccz) in ((34.8, 0.3, -14, cz0 - 0.15), (34.8, 0.3, -14, cz1 + 0.15), (0.3, 24.8, cx0 - 0.15, -8), (0.3, 24.8, cx1 + 0.15, -8)):
        at(p, "paint_red", (sx, 1.1, sz), ccx, 9.35, ccz)
        at(p, "paint_white", (sx + 0.04, 0.14, sz + 0.04), ccx, 9.98, ccz)
        at(p, "paint_white", (sx + 0.04, 0.14, sz + 0.04), ccx, 8.72, ccz)
    # panelled ceiling with dark trays round the strip lights hanging below it
    for i in range(8):
        for j in range(6):
            at(p, "aluminium", (4.15, 0.08, 3.95), -29.1 + i * 4.3, 9.62, -18.1 + j * 4.05)
    for lx in (-24, -14, -4):
        at(p, "metal_dark", (6.8, 0.22, 1.2), lx, 9.47, -8)
    # columns: white steel with red kick plates on concrete collars
    for ccx in (-26, -2):
        for ccz in (-16, 0):
            at(p, "paint_white", (1.0, 8.4, 1.0), ccx, 4.9, ccz)
            at(p, "paint_red", (1.12, 1.2, 1.12), ccx, 1.6, ccz)
            cyl(p, "concrete", 0.95, 1.0, T(ccx, 0.5, ccz), seg=14)
    # the island: a curbed slab with yellow edges and bollards at the ends
    at(p, "concrete", (26.6, 0.7, 5.6), -14, 0.35, -8)
    for (sx, sz, ccx, ccz) in ((26.8, 0.1, -14, -10.8), (26.8, 0.1, -14, -5.2), (0.1, 5.8, -27.35, -8), (0.1, 5.8, -0.65, -8)):
        at(p, "paint_yellow", (sx, 0.72, sz), ccx, 0.36, ccz)
    for bx in (-28.2, 0.2):
        cyl(p, "paint_yellow", 0.33, 3.2, T(bx, 1.6, -8), seg=10)
        ball(p, "paint_yellow", 0.33, bx, 3.2, -8)
    # two old pumps facing the lot, glass globes lit on top
    for px in (-20, -8):
        at(p, "concrete", (3.0, 0.5, 2.2), px, 0.95, -8)
        at(p, "paint_red", (2.4, 4.4, 1.6), px, 3.4, -8)
        cyl(p, "paint_red", 0.8, 2.4, T(px, 5.6, -8) @ RZ(math.pi / 2), seg=16)
        at(p, "metal_dark", (0.9, 0.35, 0.9), px, 6.45, -8)
        ball(p, "lens", 0.6, px, 7.15, -8)
        at(p, "paint_white", (2.44, 0.3, 1.64), px, 2.3, -8)
        at(p, "glass_dark", (1.8, 1.1, 0.08), px, 4.45, -8.84)
        for dx in (-0.45, 0.45):
            at(p, "paper", (0.7, 0.5, 0.05), px + dx, 3.4, -8.83)
        hose = [(px + 1.2, 4.8, -8.0), (px + 1.7, 3.0, -8.4), (px + 1.5, 1.4, -8.6), (px + 1.3, 3.3, -8.9)]
        for a, b in zip(hose, hose[1:]):
            cyl_between(p, "rubber", a, b, 0.09, seg=6)
        at(p, "metal_dark", (0.32, 0.7, 0.42), px + 1.3, 3.6, -8.95)

    # ---- a leaning utility pole behind the diner (build_lobby.py, x 14..54,
    # z 18..40) with wires over its roof to the store roof
    pole = (44.0, 0.0, 46.0)
    cyl(p, "wood_dark", 0.45, 28.0, T(pole[0], 14.0, pole[2]) @ RZ(0.03), seg=10)
    at(p, "wood_dark", (6.0, 0.4, 0.4), pole[0] - 0.4, 25.0, pole[2])
    for dx in (-2.6, 0.0, 2.6):
        cyl(p, "ceramic", 0.14, 0.5, T(pole[0] - 0.4 + dx, 25.45, pole[2]), seg=8)
        a = Vector((pole[0] - 0.4 + dx, 25.6, pole[2]))
        b = Vector((2.6, 12.9, 30.0 + dx * 0.5))
        mid = (a + b) / 2 - Vector((0, 2.2, 0))
        beam(p, "metal_dark", a, mid, 0.06, 0.06)
        beam(p, "metal_dark", mid, b, 0.06, 0.06)

    # a few crumbling spots in the walk
    for _ in range(4):
        at(p, "stone_dark", (rng.uniform(0.8, 1.8), 0.08, rng.uniform(0.6, 1.4)), rng.uniform(-30, 2), 0.37, rng.uniform(13.2, 16.6))
    return p


BUILDINGS = {
    "FarmhouseExteriorXL": build_farmhouse,
    "RangerStationExterior": build_station,
    "BarnExterior": build_barn,
    "ToolShedExterior": build_tool_shed,
    "TrailerExterior": build_trailer,
    "LookoutTowerRoof": build_tower_roof,
    "GasStationExterior": build_gas_station,
}

if __name__ == "__main__":
    bp.BUILDERS.update(BUILDINGS)
    argv = sys.argv
    names = argv[argv.index("--") + 1:] if "--" in argv else []
    sys.argv = [argv[0], "--"] + (names or list(BUILDINGS.keys()))
    bp.main()
