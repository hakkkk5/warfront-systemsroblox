"""
The Cannibal Family - the farmhouse's floors, walls, stairs and furniture.

House.luau and HouseWings.luau build the farmhouse out of plain parts, which
keep the collisions; Build.bake marks every plain, static one "Baked" so the
clients hide them and show these meshes instead (the stand-in furniture,
lights, doors and pickups are left alone). This remodels each of those parts
by what it is, at its exact place:

    floors        boards with staggered joints, checker tiles, flagstones,
                  a stained concrete slab; tongue-and-groove ceilings under
                  every floor that has a room beneath it
    walls         plaster with grime at the skirting
    timber        hand-hewn ceiling beams and rafters, turned balusters and
                  table legs, rounded rails, moulded trim and window frames
    stairs        treads with a nosing, risers, a dark body
    cloth         pleated curtains, draped sheets, soft piles of clothes,
                  rugs with a border and fringe
    the rest      cobwebs, blood pools, candles with drips, skulls on stakes,
                  cardboard boxes with open flaps, a ladder for each truss

The parts come from tools/blender/data/farmhouse_parts.txt, dumped from
Studio relative to the house origin, one part per line:

    group|shape|material|colour|transparency|x,y,z|sx,sy,sz|rotation|name|parent

group S (CannibalHouse.Structure) becomes FarmhouseStructure, F (Furniture)
FarmhouseFurnish. To refresh it after changing the house, run BakePreview in
Studio and dump the Baked parts again (see Build.bake).

    blender -b --factory-startup -P tools/blender/build_house_parts.py
"""

import math
import os
import random
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Matrix, Vector, noise  # noqa: E402

import build_props as bp  # noqa: E402
from build_props import PALETTE, srgb, mix, mul  # noqa: E402
from build_buildings import C  # noqa: E402

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "farmhouse_parts.txt")
MESHES = {"S": "FarmhouseStructure", "F": "FarmhouseFurnish"}
# Roblox takes at most 20k triangles a mesh; bigger materials are split into
# "<key>_2", "<key>_3"... (MeshLibrary reads those as <key>)
LIMIT = 18000

PALETTE.update({
    "hs_floor": dict(color=srgb(70, 50, 34), roblox="Wood", rough=0.8, metal=0.0, pattern="grain"),
    "hs_wood": dict(color=srgb(60, 44, 32), roblox="Wood", rough=0.75, metal=0.0, pattern="grain"),
    "hs_beam": dict(color=srgb(52, 38, 28), roblox="Wood", rough=0.9, metal=0.0, pattern="grain_old"),
    "hs_bloodwood": dict(color=srgb(78, 52, 34), roblox="Wood", rough=0.8, metal=0.0, pattern="blood"),
    "hs_plaster": dict(color=srgb(96, 84, 70), roblox="Plaster", rough=1.0, metal=0.0, pattern="dirty"),
    "hs_stone": dict(color=srgb(70, 66, 62), roblox="Cobblestone", rough=0.9, metal=0.0, pattern="stone"),
    "hs_tile": dict(color=srgb(150, 140, 120), roblox="SmoothPlastic", rough=0.3, metal=0.0, pattern="dirty"),
    "hs_concrete": dict(color=srgb(90, 86, 80), roblox="Concrete", rough=0.95, metal=0.0, pattern="blood"),
    "hs_slate": dict(color=srgb(84, 80, 76), roblox="Slate", rough=0.9, metal=0.0, pattern="stone"),
    "hs_cloth": dict(color=srgb(110, 90, 80), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave"),
    "hs_curtain": dict(color=srgb(107, 79, 69), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave"),
    "hs_rug": dict(color=srgb(90, 30, 28), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave_blood"),
    "hs_leather": dict(color=srgb(60, 40, 30), roblox="Leather", rough=0.7, metal=0.0, pattern="dirty"),
    "hs_metal": dict(color=srgb(70, 66, 60), roblox="Metal", rough=0.45, metal=0.9, pattern="scratch"),
    "hs_rust": dict(color=srgb(110, 70, 50), roblox="CorrodedMetal", rough=0.8, metal=0.5, pattern="rust"),
    "hs_glass": dict(color=srgb(40, 50, 56), roblox="Glass", rough=0.05, metal=0.0, pattern="none", transparency=0.55),
    "hs_jar": dict(color=srgb(110, 40, 30), roblox="SmoothPlastic", rough=0.05, metal=0.0, pattern="none", transparency=0.3),
    "hs_mirror": dict(color=srgb(150, 160, 165), roblox="Glass", rough=0.05, metal=0.0, pattern="none"),
    "hs_blood": dict(color=srgb(80, 6, 6), roblox="SmoothPlastic", rough=0.1, metal=0.0, pattern="none"),
    "hs_plastic": dict(color=srgb(220, 214, 196), roblox="SmoothPlastic", rough=0.5, metal=0.0, pattern="dirty"),
    "hs_web": dict(color=srgb(200, 200, 196), roblox="SmoothPlastic", rough=1.0, metal=0.0, pattern="none", transparency=0.45),
    "hs_cardboard": dict(color=srgb(150, 120, 84), roblox="Cardboard", rough=1.0, metal=0.0, pattern="dirty"),
})


# ----------------------------------------------------------------------------- input
class Part:
    """One dumped part, in house-local Roblox space."""

    def __init__(self, line, index):
        f = line.rstrip("\r\n").split("|")
        self.index = index
        self.group, self.shape, self.mat = f[0], f[1], f[2]
        h = f[3]
        self.color = srgb(int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
        self.t = float(f[4])
        self.pos = Vector([float(v) for v in f[5].split(",")])
        self.size = Vector([float(v) for v in f[6].split(",")])
        r = (1, 0, 0, 0, 1, 0, 0, 0, 1) if f[7] == "I" else tuple(float(v) for v in f[7].split(","))
        self.upright = f[7] == "I" or (abs(r[4]) > 0.999)
        self.cf = Matrix((
            (r[0], r[1], r[2], self.pos.x),
            (r[3], r[4], r[5], self.pos.y),
            (r[6], r[7], r[8], self.pos.z),
            (0, 0, 0, 1),
        ))
        self.name = f[8] if len(f) > 8 else ""
        self.parent = f[9] if len(f) > 9 else ""

    @property
    def top(self):
        return self.pos.y + self.size.y / 2

    def reddish(self):
        r, g, b = self.color
        return r > 0.12 and r > g * 1.8 and r > b * 1.8


def load():
    with open(DATA) as fh:
        return [Part(line, i) for i, line in enumerate(fh) if line.strip()]


# ----------------------------------------------------------------------------- output
class Mesh:
    """The pieces of one Blender mesh, by palette key. Each piece keeps its
    own colour, so one material can carry every shade of the old parts."""

    def __init__(self, name):
        self.name = name
        self.groups = {}

    def emit(self, key, bm, cf, color, local=None):
        if not bm.faces:
            bm.free()
            return
        m = C @ cf if local is None else C @ cf @ local
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.verts.index_update()
        verts = [v.co.copy() for v in bm.verts]
        faces = [tuple(v.index for v in f.verts) for f in bm.faces]
        bm.free()
        self.groups.setdefault(key, []).append((verts, faces, tuple(max(0.0, min(1.0, c)) for c in color)))


def shade_piece(color, rng, spread=0.1):
    return mul(color, 1.0 + rng.uniform(-spread, spread))


# ----------------------------------------------------------------------------- geometry
GRID_FACES = (
    ((1, 0, 0), (0, 1, 0), (0, 0, 1)),
    ((-1, 0, 0), (0, 0, 1), (0, 1, 0)),
    ((0, 1, 0), (0, 0, 1), (1, 0, 0)),
    ((0, -1, 0), (1, 0, 0), (0, 0, 1)),
    ((0, 0, 1), (1, 0, 0), (0, 1, 0)),
    ((0, 0, -1), (0, 1, 0), (1, 0, 0)),
)


def axis_of(v):
    return max(range(3), key=lambda i: abs(v[i]))


def grid_box(bm, size, steps, center=(0, 0, 0), skip=()):
    """A box whose faces are grids no coarser than `steps` (per axis), so the
    vertex-colour wear has somewhere to live. skip: face normals to leave out."""
    h = Vector(size) / 2
    c = Vector(center)
    st = steps if isinstance(steps, (tuple, list)) else (steps, steps, steps)
    out = []
    for n, u, v in GRID_FACES:
        if n in skip:
            continue
        n, u, v = Vector(n), Vector(u), Vector(v)
        iu, iv, inn = axis_of(u), axis_of(v), axis_of(n)
        hu, hv, hn = h[iu], h[iv], h[inn]
        nu = max(1, math.ceil(2 * hu / st[iu] - 1e-6))
        nv = max(1, math.ceil(2 * hv / st[iv] - 1e-6))
        origin = c + n * hn - u * hu - v * hv
        rows = [[bm.verts.new(origin + u * (2 * hu * i / nu) + v * (2 * hv * j / nv)) for j in range(nv + 1)] for i in range(nu + 1)]
        for i in range(nu):
            for j in range(nv):
                out.append(bm.faces.new((rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1])))
    return out


def cube(bm, size, center=(0, 0, 0), bev=0.0, seg=1, skip_bottom=False, skip_top=False):
    r = bmesh.ops.create_cube(bm, size=1.0)
    vs = r["verts"]
    bmesh.ops.scale(bm, vec=Vector(size), verts=vs)
    bmesh.ops.translate(bm, vec=Vector(center), verts=vs)
    if bev > 0.004:
        edges = list({e for v in vs for e in v.link_edges})
        try:
            bmesh.ops.bevel(bm, geom=list(vs) + edges, offset=bev, segments=seg, profile=0.5,
                            affect="EDGES", clamp_overlap=True)
        except Exception:  # noqa: BLE001 - a plain box is fine
            pass
    if skip_bottom or skip_top:
        # a face nobody sees (the underside of a floorboard, the top of a ceiling board)
        low = Vector(center).y - size[1] / 2 + 1e-4
        high = Vector(center).y + size[1] / 2 - 1e-4
        hidden = [f for f in bm.faces if (skip_bottom and all(v.co.y < low for v in f.verts))
                  or (skip_top and all(v.co.y > high for v in f.verts))]
        if hidden:
            bmesh.ops.delete(bm, geom=hidden, context="FACES_ONLY")
    return vs


def cylinder_x(bm, r, length, seg=12, center=(0, 0, 0), r2=None):
    """Along local X (a Roblox cylinder's axis)."""
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r,
                                radius2=r if r2 is None else r2, depth=length)
    vs = res["verts"]
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi / 2, 3, "Y"), verts=vs)
    bmesh.ops.translate(bm, vec=Vector(center), verts=vs)
    return vs


def cylinder_y(bm, r, length, seg=10, center=(0, 0, 0), r2=None):
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r,
                                radius2=r if r2 is None else r2, depth=length)
    vs = res["verts"]
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(-math.pi / 2, 3, "X"), verts=vs)
    bmesh.ops.translate(bm, vec=Vector(center), verts=vs)
    return vs


def sphere(bm, r, center=(0, 0, 0), scale=(1, 1, 1), seg=12, rings=8):
    res = bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    vs = res["verts"]
    bmesh.ops.scale(bm, vec=Vector(scale), verts=vs)
    bmesh.ops.translate(bm, vec=Vector(center), verts=vs)
    return vs


def lathe_y(bm, profile, seg, y0, y1, radius):
    """A turned shape along local Y; profile: (t 0..1, radius fraction)."""
    rings = []
    for t, f in profile:
        y = y0 + (y1 - y0) * t
        rings.append([bm.verts.new((math.cos(2 * math.pi * k / seg) * radius * f, y,
                                    math.sin(2 * math.pi * k / seg) * radius * f)) for k in range(seg)])
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])


def ribbon(bm, a, b, width, normal):
    """A flat strip from a to b, both sides."""
    a, b, normal = Vector(a), Vector(b), Vector(normal)
    d = b - a
    if d.length < 1e-4:
        return
    side = d.cross(normal)
    if side.length < 1e-6:
        return
    side = side.normalized() * width / 2
    off = normal.normalized() * 0.004
    front = [bm.verts.new(p + off) for p in (a - side, b - side, b + side, a + side)]
    back = [bm.verts.new(p - off) for p in (a - side, b - side, b + side, a + side)]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))


def round_box(bm, size, radius, steps, wrinkle=0.0, seed=0.0, flare=0.0):
    """A soft box: a grid box pushed onto a rounded box, with cloth wrinkles."""
    grid_box(bm, size, steps)
    h = Vector(size) / 2
    inner = Vector([max(0.0, h[i] - radius) for i in range(3)])
    for v in bm.verts:
        p = v.co
        c = Vector([max(-inner[i], min(inner[i], p[i])) for i in range(3)])
        d = p - c
        if d.length > 1e-6:
            n = d.normalized()
            p = c + n * radius
            if wrinkle:
                p += n * noise.noise(p * 2.6 + Vector((seed, seed * 0.3, 0))) * wrinkle
            if flare and p.y < -h.y + 0.35:
                p += Vector((n.x, 0, n.z)) * flare
            v.co = p


def roughen(bm, amount, freq, seed):
    off = Vector((seed * 1.7, seed * 0.37, seed * 2.9))
    for v in bm.verts:
        v.co += noise.noise_vector(v.co * freq + off) * amount


# ----------------------------------------------------------------------------- remodels
def piece(mesh, p, key, color, build, local=None):
    bm = bmesh.new()
    build(bm)
    mesh.emit(key, bm, p.cf, color, local)


def generic_box(mesh, p, key, bev_scale=0.2, bev_max=0.06):
    s = p.size
    b = min(bev_max, min(s) * bev_scale)
    if max(s) > 3.5 and min(s) > 0.6:
        # big pieces (cabinets, crates, walls of furniture) get a fine grid for the wear
        piece(mesh, p, key, p.color, lambda bm: grid_box(bm, s, 1.0))
    else:
        piece(mesh, p, key, p.color, lambda bm: cube(bm, s, bev=b))


def generic_shape(mesh, p, key):
    s = p.size
    if p.shape == "Cylinder":
        r = min(s.y, s.z) / 2
        seg = max(8, min(20, int(r * 30)))
        piece(mesh, p, key, p.color, lambda bm: cylinder_x(bm, r, s.x, seg))
    elif p.shape == "Ball":
        r = min(s) / 2
        piece(mesh, p, key, p.color, lambda bm: sphere(bm, r, seg=16 if r > 0.8 else 12, rings=10 if r > 0.8 else 8))
    elif p.shape == "WedgePart":
        def build(bm):
            hx, hy, hz = s.x / 2, s.y / 2, s.z / 2
            v = [bm.verts.new(c) for c in (
                (-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz), (-hx, hy, hz), (hx, hy, hz))]
            bm.faces.new((v[0], v[1], v[2], v[3]))
            bm.faces.new((v[3], v[2], v[5], v[4]))
            bm.faces.new((v[0], v[4], v[5], v[1]))
            bm.faces.new((v[0], v[3], v[4]))
            bm.faces.new((v[1], v[5], v[2]))
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        piece(mesh, p, key, p.color, build)
    else:
        generic_box(mesh, p, key)


def floor_slab(mesh, p, kind, rng):
    """A floor: a dark core with the surface on top, and a board ceiling
    underneath when it is the floor of an upper storey."""
    s = p.size
    top, bottom = s.y / 2, -s.y / 2
    ceiling = s.y >= 0.9 and p.pos.y > 1.0
    surface = {"planks": 0.12, "tiles": 0.05, "flags": 0.08, "concrete": 0.0}[kind]
    core_top = top - surface - 0.005
    core_bottom = bottom + (0.08 if ceiling else 0.0)
    if kind == "concrete":
        piece(mesh, p, "hs_concrete", p.color,
              lambda bm: grid_box(bm, (s.x, core_top - core_bottom, s.z), (2.0, 4.0, 2.0), (0, (core_top + core_bottom) / 2, 0)))
    else:
        piece(mesh, p, "hs_floor", mul(p.color, 0.45),
              lambda bm: cube(bm, (s.x, core_top - core_bottom, s.z), (0, (core_top + core_bottom) / 2, 0)))
    if kind == "planks":
        along_x = s.x >= s.z and p.pos.z > -25
        boards(mesh, p, "hs_floor", s, top, 0.12, 1.1, 0.04, along_x, (6.0, 14.0), p.color, rng, 0.14)
    elif kind == "tiles":
        tiles(mesh, p, s, top, rng)
    elif kind == "flags":
        flags(mesh, p, s, top, rng)
    if ceiling:
        boards(mesh, p, "hs_floor", s, bottom + 0.08, 0.08, 0.9, 0.035, s.x < s.z, (12.0, 24.0),
               mul(mix(p.color, srgb(150, 130, 100), 0.45), 1.05), rng, 0.06, under=True)


def boards(mesh, p, key, s, top, thick, width, gap, along_x, lengths, color, rng, spread, under=False):
    """Rows of boards with staggered joints over the s.x x s.z rectangle,
    their top faces at `top` (local)."""
    run = s.x if along_x else s.z
    across = s.z if along_x else s.x
    rows = max(1, int(round(across / width)))
    w = across / rows
    for i in range(rows):
        c_across = -across / 2 + w * (i + 0.5)
        a = -run / 2
        first = True
        while a < run / 2 - 1e-3:
            ln = rng.uniform(*lengths) * (rng.uniform(0.3, 1.0) if first else 1.0)
            b = min(run / 2, a + ln)
            if run / 2 - b < 1.2:
                b = run / 2
            first = False
            length = b - a - gap
            if length > 0.1:
                c_run = (a + b) / 2
                y = top - thick / 2 + rng.uniform(-0.008, 0.004)
                size = (length, thick, w - gap) if along_x else (w - gap, thick, length)
                center = (c_run, y, c_across) if along_x else (c_across, y, c_run)
                tone = shade_piece(color, rng, spread)
                piece(mesh, p, key, tone, lambda bm, size=size, center=center: cube(bm, size, center, skip_bottom=not under, skip_top=under))
            a = b


def tiles(mesh, p, s, top, rng):
    """A checkerboard of square tiles over grout."""
    module = 2.0
    nx, nz = max(1, round(s.x / module)), max(1, round(s.z / module))
    wx, wz = s.x / nx, s.z / nz
    light = mix(p.color, srgb(226, 220, 204), 0.55)
    dark = mul(p.color, 0.42)
    for i in range(nx):
        for j in range(nz):
            cx, cz = -s.x / 2 + wx * (i + 0.5), -s.z / 2 + wz * (j + 0.5)
            tone = shade_piece(light if (i + j) % 2 == 0 else dark, rng, 0.06)
            size = (wx - 0.07, 0.05, wz - 0.07)
            center = (cx, top - 0.025 + rng.uniform(-0.004, 0.0), cz)
            piece(mesh, p, "hs_tile", tone, lambda bm, size=size, center=center: cube(bm, size, center, skip_bottom=True))


def flags(mesh, p, s, top, rng):
    """Irregular flagstones in staggered courses."""
    z = -s.z / 2
    while z < s.z / 2 - 0.2:
        depth = min(s.z / 2 - z, rng.uniform(2.2, 3.4))
        if s.z / 2 - (z + depth) < 0.8:
            depth = s.z / 2 - z
        x = -s.x / 2
        while x < s.x / 2 - 0.2:
            ln = min(s.x / 2 - x, rng.uniform(2.0, 4.0))
            if s.x / 2 - (x + ln) < 0.8:
                ln = s.x / 2 - x
            size = (ln - 0.12, 0.08, depth - 0.12)
            center = (x + ln / 2, top - 0.04 + rng.uniform(-0.015, 0.01), z + depth / 2)
            tone = shade_piece(p.color, rng, 0.16)
            piece(mesh, p, "hs_slate", tone, lambda bm, size=size, center=center: cube(bm, size, center, bev=0.035, skip_bottom=True))
            x += ln
        z += depth


def stair_steps(mesh, steps, rng):
    """Each server step is a solid block from the floor up to its tread: keep
    the block as the dark body and put a tread with a nosing and a riser on
    the face toward the step below."""
    by_run = {}
    for p in steps:
        by_run.setdefault((round(p.pos.x, 1), round(p.size.x, 1)), []).append(p)
    for run in by_run.values():
        run.sort(key=lambda q: q.top)
        for i, p in enumerate(run):
            if len(run) > 1:
                other = run[i - 1] if i > 0 else run[i + 1]
                d = other.pos.z - p.pos.z
                facing = (1 if d > 0 else -1) if i > 0 else (-1 if d > 0 else 1)
            else:
                facing = -1
            s = p.size
            top = s.y / 2
            piece(mesh, p, "hs_wood", mul(p.color, 0.6),
                  lambda bm, s=s, top=top: cube(bm, (s.x, s.y - 0.2, s.z), (0, -0.1, 0)))
            tread = shade_piece(p.color, rng, 0.08)
            piece(mesh, p, "hs_wood", mul(tread, 1.15),
                  lambda bm, s=s, top=top, f=facing: cube(bm, (s.x + 0.06, 0.2, s.z + 0.14), (0, top - 0.1, f * 0.07), bev=0.05, seg=2))
            if s.y > 0.45:
                h = min(0.8, s.y - 0.25)
                piece(mesh, p, "hs_wood", mul(p.color, 0.85),
                      lambda bm, s=s, top=top, f=facing, h=h: cube(bm, (s.x - 0.04, h, 0.06), (0, top - 0.2 - h / 2, f * (s.z / 2 + 0.02))))


def hewn_beam(mesh, p, rng):
    s = p.size
    long_axis = axis_of(s)
    steps = [0.45, 0.45, 0.45]
    steps[long_axis] = 1.4

    def build(bm):
        grid_box(bm, s, steps)
        # adze-chamfered arrises: pull the long edges in a little, then
        # roughen the whole timber
        h = s / 2
        for v in bm.verts:
            near = [i for i in range(3) if i != long_axis and abs(abs(v.co[i]) - h[i]) < 0.02]
            if len(near) == 2:
                for i in near:
                    v.co[i] *= 1 - min(0.12, 0.06 / max(h[i], 0.1))
        roughen(bm, 0.03, 0.9, p.index * 0.37)
    piece(mesh, p, "hs_beam", shade_piece(p.color, rng, 0.12), build)


BALUSTER = [(0.0, 1.0), (0.1, 1.0), (0.12, 0.62), (0.2, 0.8), (0.28, 0.5), (0.62, 0.58), (0.72, 0.85),
            (0.78, 0.52), (0.88, 0.62), (0.9, 1.0), (1.0, 1.0)]
LEG = [(0.0, 0.55), (0.06, 0.7), (0.12, 0.55), (0.55, 0.8), (0.68, 0.6), (0.76, 0.9), (0.82, 1.0), (1.0, 1.0)]


def turned(mesh, p, key, profile, scale=1.15):
    s = p.size
    r = min(s.x, s.z) / 2 * scale
    piece(mesh, p, key, p.color, lambda bm: lathe_y(bm, profile, 8, -s.y / 2, s.y / 2, r))


def rail(mesh, p, key):
    s = p.size
    piece(mesh, p, key, p.color, lambda bm: cube(bm, s, bev=min(s.x, s.y, s.z) * 0.32, seg=2))


def rod(mesh, p, rng):
    """A curtain rod: round bar, ball finials, two brackets."""
    s = p.size
    long_axis = axis_of(s)
    length = s[long_axis]
    local = Matrix.Identity(4)
    if long_axis == 1:
        local = Matrix.Rotation(math.pi / 2, 4, "Z")
    elif long_axis == 2:
        local = Matrix.Rotation(-math.pi / 2, 4, "Y")

    def build(bm):
        cylinder_x(bm, 0.05, length - 0.3, 10)
        for e in (-1, 1):
            sphere(bm, 0.11, (e * (length / 2 - 0.12), 0, 0), seg=10, rings=6)
            cube(bm, (0.08, 0.06, 0.28), (e * (length / 2 - 0.55), 0, 0.12))
    piece(mesh, p, "hs_metal", mul(p.color, 1.6), build, local)


def curtain(mesh, p, rng):
    """A pleated curtain, both sides, hanging from its top edge with a ragged hem."""
    s = p.size
    w, h = s.x, s.y
    folds = max(2, round(w / 0.42))
    nx, ny = folds * 4, 6
    hem = [rng.uniform(-0.22, 0.0) for _ in range(nx + 1)]
    seed = p.index * 0.71

    def build(bm):
        for side in (1, -1):
            grid = []
            for i in range(nx + 1):
                u = i / nx
                col = []
                for j in range(ny + 1):
                    v = j / ny
                    x = -w / 2 + w * u
                    y = -h / 2 + h * v + (hem[i] * (1 - v) if j == 0 else 0)
                    amp = 0.13 * (0.55 + 0.45 * (1 - v))
                    z = math.sin(u * folds * 2 * math.pi) * amp + noise.noise(Vector((x * 1.3 + seed, y * 0.8, 0))) * 0.05
                    col.append(bm.verts.new((x, y, z + side * 0.012)))
                grid.append(col)
            for i in range(nx):
                for j in range(ny):
                    quad = (grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])
                    bm.faces.new(quad if side > 0 else tuple(reversed(quad)))
    piece(mesh, p, "hs_curtain", p.color, build)


def cobweb(mesh, p, rng):
    """Spokes and sagging rings of silk in the plane of the old square."""
    s = p.size
    r = min(s.x, s.y) / 2 * 1.2
    spokes = 9
    angles = [2 * math.pi * k / spokes + rng.uniform(-0.15, 0.15) for k in range(spokes)]

    def build(bm):
        n = (0, 0, 1)
        for a in angles:
            ribbon(bm, (0, 0, 0), (math.cos(a) * r, math.sin(a) * r, rng.uniform(-0.05, 0.05)), 0.03, n)
        for ring in range(1, 5):
            rr = r * ring / 4.6
            pts = [(math.cos(a) * rr * rng.uniform(0.85, 1.0), math.sin(a) * rr * rng.uniform(0.85, 1.0), 0) for a in angles]
            for k in range(spokes):
                a, b = Vector(pts[k]), Vector(pts[(k + 1) % spokes])
                mid = (a + b) / 2 * 0.86  # silk sags toward the centre
                ribbon(bm, a, mid, 0.022, n)
                ribbon(bm, mid, b, 0.022, n)
    piece(mesh, p, "hs_web", srgb(214, 212, 204), build)


def blood_pool(mesh, p, rng):
    s = p.size
    n = 16
    phase = rng.uniform(0, 10)

    def build(bm):
        pts = []
        for k in range(n):
            a = 2 * math.pi * k / n
            f = 0.72 + 0.28 * (0.5 + 0.5 * math.sin(a * 3 + phase)) * rng.uniform(0.85, 1.12)
            pts.append((math.cos(a) * s.x / 2 * f, math.sin(a) * s.z / 2 * f))
        t = max(0.02, min(0.05, s.y))
        top = [bm.verts.new((x, t / 2, z)) for x, z in pts]
        bot = [bm.verts.new((x, -t / 2, z)) for x, z in pts]
        bm.faces.new(top)
        bm.faces.new(list(reversed(bot)))
        for k in range(n):
            bm.faces.new((top[k], bot[k], bot[(k + 1) % n], top[(k + 1) % n]))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    piece(mesh, p, "hs_blood", mul(p.color, 0.9), build)


def rug(mesh, p, rng):
    s = p.size
    t = max(s.y, 0.04)
    long_axis = 0 if s.x >= s.z else 2
    piece(mesh, p, "hs_rug", p.color, lambda bm: grid_box(bm, (s.x, t, s.z), (0.8, 1.0, 0.8)))
    border = mul(mix(p.color, srgb(150, 110, 60), 0.35), 0.8)
    inset, bw = 0.45, 0.3
    for along in (0, 2):
        for e in (-1, 1):
            if along == 0:
                size, center = (s.x - 2 * inset, 0.012, bw), (0, t / 2 + 0.004, e * (s.z / 2 - inset))
            else:
                size, center = (bw, 0.012, s.z - 2 * inset), (e * (s.x / 2 - inset), t / 2 + 0.004, 0)
            piece(mesh, p, "hs_rug", border, lambda bm, size=size, center=center: cube(bm, size, center))
    # fringe on the short ends
    fringe = mix(p.color, srgb(200, 186, 150), 0.6)

    def build(bm):
        n = (0, 1, 0)
        across = s.z if long_axis == 0 else s.x
        half = (s.x if long_axis == 0 else s.z) / 2
        k = -across / 2 + 0.12
        while k < across / 2 - 0.1:
            for e in (-1, 1):
                ln = rng.uniform(0.18, 0.3)
                if long_axis == 0:
                    a, b = (e * half, t / 2, k), (e * (half + ln), 0.0, k + rng.uniform(-0.05, 0.05))
                else:
                    a, b = (k, t / 2, e * half), (k + rng.uniform(-0.05, 0.05), 0.0, e * (half + ln))
                ribbon(bm, a, b, 0.06, n)
            k += 0.16
    piece(mesh, p, "hs_rug", fringe, build)


def cardboard(mesh, p, rng):
    s = p.size
    piece(mesh, p, "hs_cardboard", p.color, lambda bm: cube(bm, s, bev=0.03))
    # top flaps, some folded open
    for e in (-1, 1):
        if rng.random() < 0.55:
            angle = rng.uniform(0.4, 1.9)

            def build(bm, e=e, angle=angle):
                vs = cube(bm, (s.x - 0.04, 0.02, s.z / 2 - 0.02), (0, s.y / 2 + 0.01, e * s.z / 4))
                bmesh.ops.rotate(bm, cent=(0, s.y / 2, e * s.z / 2), matrix=Matrix.Rotation(e * angle, 3, "X"), verts=vs)
            piece(mesh, p, "hs_cardboard", mul(p.color, 0.92), build)
    tape = mix(p.color, srgb(200, 180, 130), 0.5)
    piece(mesh, p, "hs_cardboard", tape, lambda bm: cube(bm, (0.35, s.y * 0.35, 0.012), (0, s.y * 0.33, -s.z / 2 - 0.006)))


def candle(mesh, p, rng):
    """Wax along local X (up), drips down the side and a puddle at the foot."""
    s = p.size
    r = min(s.y, s.z) / 2
    ln = s.x

    def build(bm):
        cylinder_x(bm, r, ln, 10)
        for _ in range(3):
            a = rng.uniform(0, 2 * math.pi)
            dl = rng.uniform(0.15, 0.4) * ln
            x = ln / 2 - dl / 2 - 0.02
            sphere(bm, 1.0, (x, math.cos(a) * r, math.sin(a) * r), (dl / 2, 0.05, 0.05), seg=6, rings=4)
        cylinder_x(bm, r * 1.9, 0.04, 12, (-ln / 2 + 0.02, 0, 0))
    piece(mesh, p, "hs_plastic", p.color, build)
    piece(mesh, p, "hs_plastic", srgb(20, 16, 14), lambda bm: cube(bm, (0.12, 0.025, 0.025), (ln / 2 + 0.05, 0, 0)))


def skull(mesh, p):
    """Faces -Z, like the eye sockets beside the yard skulls; the ones on the
    trophy-room shelves turn to face into the room."""
    s = p.size
    r = min(s) / 2
    local = None
    if p.group == "F" and abs(p.pos.x) > 25:
        local = Matrix.Rotation(math.pi / 2 if p.pos.x > 0 else -math.pi / 2, 4, "Y")

    def build(bm):
        sphere(bm, r, (0, 0.04 * r, 0.05 * r), (0.95, 0.92, 1.08), seg=14, rings=9)
        cube(bm, (0.95 * r, 0.42 * r, 0.7 * r), (0, -0.62 * r, -0.42 * r), bev=0.08 * r, seg=2)
        for e in (-1, 1):
            sphere(bm, 0.22 * r, (e * 0.62 * r, -0.28 * r, -0.62 * r), (1.2, 0.8, 1.0), seg=8, rings=6)
    piece(mesh, p, "hs_plastic", p.color, build, local)
    teeth = mul(p.color, 0.9)

    def build_teeth(bm):
        for k in range(6):
            cube(bm, (0.11 * r, 0.16 * r, 0.06 * r), ((k - 2.5) * 0.14 * r, -0.5 * r, -0.78 * r), bev=0.02 * r)
    piece(mesh, p, "hs_plastic", teeth, build_teeth, local)
    if p.group == "F":
        # the shelf skulls have no sockets of their own
        for e in (-1, 1):
            piece(mesh, p, "hs_plastic", srgb(10, 8, 8),
                  lambda bm, e=e: sphere(bm, 1.0, (e * 0.32 * r, 0.12 * r, -0.86 * r), (0.2 * r, 0.17 * r, 0.12 * r), seg=8, rings=6), local)


def socket(mesh, p):
    s = p.size
    piece(mesh, p, "hs_plastic", srgb(8, 6, 6), lambda bm: sphere(bm, 1.0, (0, 0, 0), (s.x / 2, s.y / 2, max(s.z, 0.12) / 2), seg=10, rings=6))


def stake(mesh, p, rng):
    """A sharpened stick along local X, thinner toward its top."""
    s = p.size
    r = min(s.y, s.z) / 2
    seg, rings = 7, 8

    def build(bm):
        ring_verts = []
        for i in range(rings + 1):
            t = i / rings
            x = -s.x / 2 + s.x * t
            rr = r * (1.05 - 0.35 * t)
            ring = []
            for k in range(seg):
                a = 2 * math.pi * k / seg
                wob = 1 + noise.noise(Vector((x * 1.5, math.cos(a), math.sin(a) + p.index))) * 0.18
                ring.append(bm.verts.new((x, math.cos(a) * rr * wob, math.sin(a) * rr * wob)))
            ring_verts.append(ring)
        for a, b in zip(ring_verts, ring_verts[1:]):
            for k in range(seg):
                bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]))
        bm.faces.new(list(reversed(ring_verts[0])))
        bm.faces.new(ring_verts[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    piece(mesh, p, "hs_beam", p.color, build)


def ladder(mesh, p):
    s = p.size
    color = p.color

    def build(bm):
        for e in (-1, 1):
            cube(bm, (0.24, s.y, 0.34), (e * (s.x / 2 - 0.2), 0, 0), bev=0.04)
        y = -s.y / 2 + 0.6
        while y < s.y / 2 - 0.3:
            cylinder_x(bm, 0.075, s.x - 0.4, 8, (0, y, 0))
            y += 1.0
    piece(mesh, p, "hs_wood", color, build)


def soft(mesh, p, key, rng, wrinkle=0.035, flare=0.0):
    s = p.size
    radius = min(s) * 0.3
    piece(mesh, p, key, p.color,
          lambda bm: round_box(bm, s, radius, (0.35, 0.35, 0.35), wrinkle, p.index * 0.53, flare))


def canvas(mesh, p):
    s = p.size
    piece(mesh, p, "hs_cloth", p.color, lambda bm: grid_box(bm, s, (0.4, 0.4, 0.4)))


def jar(mesh, p):
    s = p.size
    r = min(s.y, s.z) / 2
    piece(mesh, p, "hs_jar", p.color, lambda bm: cylinder_x(bm, r, s.x, 12))
    piece(mesh, p, "hs_metal", srgb(90, 80, 60), lambda bm: cylinder_x(bm, r * 1.06, 0.12, 12, (s.x / 2 + 0.04, 0, 0)))


def wall(mesh, p):
    s = p.size
    piece(mesh, p, "hs_plaster", p.color, lambda bm: grid_box(bm, s, (3.0, 3.0, 3.0)))


def foundation(mesh, p):
    s = p.size

    def build(bm):
        grid_box(bm, s, (3.0, 1.5, 3.0))
        roughen(bm, 0.05, 1.3, p.index * 0.91)
    piece(mesh, p, "hs_stone", p.color, build)


# ----------------------------------------------------------------------------- sorting
def thin_dims(s, limit):
    return sum(1 for v in s if v <= limit)


def remodel(mesh, p, rng, steps):
    s, m = p.size, p.mat
    if p.shape == "TrussPart" or p.name == "Truss":
        return ladder(mesh, p)
    if p.shape == "WedgePart":
        return generic_shape(mesh, p, "hs_plaster" if m == "Plaster" else "hs_wood")
    if p.shape == "Cylinder":
        if m == "SmoothPlastic" and min(s.y, s.z) <= 0.3 and s.x <= 1.2 and p.color[0] > 0.7:
            return candle(mesh, p, rng)
        if m == "Wood" and s.x >= 4 and min(s.y, s.z) <= 0.5:
            return stake(mesh, p, rng)
        if m == "Glass":
            return blood_pool(mesh, p, rng) if p.reddish() and s.x < 0.1 else jar(mesh, p)
        key = {"Wood": "hs_wood", "Fabric": "hs_cloth", "Metal": "hs_metal", "Slate": "hs_slate",
               "CorrodedMetal": "hs_rust", "DiamondPlate": "hs_rust"}.get(m, "hs_plastic")
        return generic_shape(mesh, p, key)
    if p.shape == "Ball":
        if m == "SmoothPlastic" and min(s) <= 1.2 and p.color[0] > 0.75 and p.parent == "":
            return skull(mesh, p)
        key = {"Metal": "hs_metal"}.get(m, "hs_plastic")
        if m == "Metal" and p.t > 0.3:
            key = "hs_jar"
        return generic_shape(mesh, p, key)

    # blocks
    if m == "Glass":
        if p.reddish():
            return blood_pool(mesh, p, rng) if s.y <= 0.06 else generic_box(mesh, p, "hs_blood")
        if p.t >= 0.4:
            return generic_box(mesh, p, "hs_glass", bev_max=0.0)
        return generic_box(mesh, p, "hs_mirror" if p.t < 0.1 else "hs_jar")
    if m == "SmoothPlastic" and p.t >= 0.5 and min(s) <= 0.05:
        return cobweb(mesh, p, rng)
    if m == "SmoothPlastic" and max(s) <= 0.35 and sum(p.color) < 0.2:
        return socket(mesh, p)
    if m in ("WoodPlanks", "CeramicTiles", "Concrete", "Slate") and p.upright and s.y <= 1.05 and s.x >= 2.5 and s.z >= 2.5:
        kind = {"WoodPlanks": "planks", "CeramicTiles": "tiles", "Concrete": "concrete", "Slate": "flags"}[m]
        return floor_slab(mesh, p, kind, rng)
    if m == "WoodPlanks" and p.upright and s.x >= 4 and 0.9 <= s.z <= 2.2 and s.y >= 0.5:
        steps.append(p)
        return None
    if m == "Cobblestone":
        return foundation(mesh, p)
    if m == "Plaster":
        return wall(mesh, p)
    if m == "Carpet":
        return rug(mesh, p, rng)
    if m == "Cardboard":
        return cardboard(mesh, p, rng)
    if m == "Fabric":
        if min(s) <= 0.07:
            return curtain(mesh, p, rng) if p.group == "S" and s.z <= 0.07 else canvas(mesh, p)
        return soft(mesh, p, "hs_cloth", rng, flare=0.12 if s.y >= 4 else 0.0)
    if m == "Leather":
        return soft(mesh, p, "hs_leather", rng, wrinkle=0.015)
    if m in ("Wood", "WoodPlanks"):
        bloody = p.parent in ("ButcherTable", "MeatHooks")
        key = "hs_bloodwood" if bloody else "hs_wood"
        two_thin = thin_dims(s, 0.35)
        if min(s) >= 0.45 and max(s) >= 6 and sorted(s)[1] <= 1.0:
            return hewn_beam(mesh, p, rng)
        if p.group == "S" and s.x <= 0.3 and s.z <= 0.3 and 2.4 <= s.y <= 3.5:
            return turned(mesh, p, key, BALUSTER)
        if p.group == "F" and s.x <= 0.6 and s.z <= 0.6 and 1.5 <= s.y <= 4.5 and min(s.x, s.z) >= 0.2:
            return turned(mesh, p, key, LEG, 1.0)
        if two_thin >= 2 and max(s) >= 2:
            return rail(mesh, p, key)
        return generic_box(mesh, p, key)
    if m in ("Metal", "DiamondPlate"):
        if thin_dims(s, 0.15) >= 2 and max(s) >= 3:
            return rod(mesh, p, rng)
        return generic_box(mesh, p, "hs_metal", bev_max=0.03)
    if m == "CorrodedMetal":
        return generic_box(mesh, p, "hs_rust", bev_max=0.03)
    return generic_box(mesh, p, "hs_plastic", bev_max=0.04)


# ----------------------------------------------------------------------------- assembly
def chunks_of(pieces):
    pieces = sorted(pieces, key=lambda pc: (round(sum(v.x for v in pc[0]) / len(pc[0]) / 12), sum(v.y for v in pc[0]) / len(pc[0])))
    out, cur, tris = [], [], 0
    for pc in pieces:
        t = len(pc[1])
        if cur and tris + t > LIMIT:
            out.append(cur)
            cur, tris = [], 0
        cur.append(pc)
        tris += t
    if cur:
        out.append(cur)
    return out


def make_object(name, key, chunk):
    verts, faces, info = [], [], []
    rng = random.Random(zlib.crc32(name.encode()))
    for seed, (pv, pf, color) in enumerate(chunk):
        base = len(verts)
        zs = [v.z for v in pv]
        lo, hi = min(zs), max(zs)
        jitter = rng.uniform(-0.035, 0.035)
        for f in pf:
            faces.append(tuple(base + i for i in f))
            info.append((color, lo, hi, seed % 97, jitter))
        verts.extend(pv)
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    me.shade_smooth()
    me.set_sharp_from_angle(angle=math.radians(38))
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    uv = me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        color, lo, hi, seed, jitter = info[poly.index]
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            c = bp.shade(key, color, co, n, lo, hi, seed, jitter)
            attr.data[li].color_srgb = (c[0], c[1], c[2], 1.0)
            if ax == 0:
                uv.data[li].uv = (co.y * 0.5, co.z * 0.5)
            elif ax == 1:
                uv.data[li].uv = (co.x * 0.5, co.z * 0.5)
            else:
                uv.data[li].uv = (co.x * 0.5, co.y * 0.5)
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = 0
    return ob, len(faces)


def build(mesh_names):
    parts = load()
    meshes = {g: Mesh(name) for g, name in MESHES.items() if name in mesh_names}
    steps = {g: [] for g in meshes}
    for p in parts:
        if p.group in meshes:
            remodel(meshes[p.group], p, random.Random(p.index * 7919 + 13), steps[p.group])
    for g, mesh in meshes.items():
        stair_steps(mesh, steps[g], random.Random(4242))

    for mesh in meshes.values():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        out = []
        total = 0
        for key in sorted(mesh.groups):
            for i, chunk in enumerate(chunks_of(mesh.groups[key])):
                name = mesh.name + "_" + (key if i == 0 else f"{key}_{i + 1}")
                ob, tris = make_object(name, key, chunk)
                out.append((ob, key))
                total += tris
                print(f"[house parts]   {name}: {tris} tris")

        bp.export_glb(bp.Prop(mesh.name, pivot="origin"), out)
        print(f"[house parts] {mesh.name}: {len(out)} mesh parts, {total} tris")


def main():
    argv = sys.argv
    names = argv[argv.index("--") + 1:] if "--" in argv else []
    build(set(names or MESHES.values()))
    # index module, as build_props.py writes it
    available = sorted(n[:-4] for n in os.listdir(bp.GLB_DIR) if n.endswith(".glb"))
    with open(os.path.join(bp.LUAU_DIR, "init.luau"), "w") as f:
        f.write("--!strict\n-- Generated by tools/blender/build_props.py. Lists the Blender meshes; they ship as\n")
        f.write("-- uploaded mesh assets (export_combined.py -> ReplicatedStorage.MeshAssets).\n")
        f.write("return {\n")
        for n in available:
            f.write(f'\t"{n}",\n')
        f.write("}\n")


if __name__ == "__main__":
    main()
