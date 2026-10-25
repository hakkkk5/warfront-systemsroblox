"""
Butcher's Hollow - Blender prop builder.

Models every hand-made prop for the game with bpy, paints procedural wear
into vertex colours and exports three things per prop:

  assets/blender/glb/<Name>.glb        - for File > Import 3D in Roblox Studio
  assets/blender/previews/<Name>.png   - Cycles preview render
  src/shared/Meshes/<Name>.luau        - packed mesh data; the client turns it
                                         into MeshParts at runtime with
                                         EditableMesh (no upload needed)

Run with Blender 4.2+ (or the `bpy` wheel):
    blender -b -P tools/blender/build_props.py
    python tools/blender/build_props.py          # with `pip install bpy`
    python tools/blender/build_props.py Lantern Cleaver   # only some props

Units are studs. Blender is Z-up with the prop's front facing +Y; Roblox is
Y-up with the front facing -Z, so (x, y, z) -> (x, z, -y) on export. Every
prop's pivot is the bottom centre unless noted.
"""

import base64
import math
import zlib
import os
import random
import struct
import sys

import bpy  # noqa: I001 - bpy must be imported before bmesh / mathutils
import bmesh
from mathutils import Matrix, Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GLB_DIR = os.path.join(ROOT, "assets", "blender", "glb")
PREVIEW_DIR = os.path.join(ROOT, "assets", "blender", "previews")
LUAU_DIR = os.path.join(ROOT, "src", "shared", "Meshes")
RENDER = os.environ.get("BH_RENDER", "1") != "0"


def srgb(r, g, b):
    return (r / 255.0, g / 255.0, b / 255.0)


# ----------------------------------------------------------------------------- palette
# color: sRGB 0..1, roblox: Enum.Material name for the MeshPart, pattern: wear
PALETTE = {
    "steel": dict(color=srgb(150, 150, 152), roblox="Metal", rough=0.35, metal=1.0, pattern="scratch"),
    "steel_bloody": dict(color=srgb(140, 138, 136), roblox="Metal", rough=0.4, metal=1.0, pattern="blood"),
    "metal_dark": dict(color=srgb(28, 28, 30), roblox="Metal", rough=0.45, metal=0.9, pattern="scratch"),
    "rust": dict(color=srgb(96, 56, 34), roblox="CorrodedMetal", rough=0.85, metal=0.4, pattern="rust"),
    "iron": dict(color=srgb(70, 62, 56), roblox="CorrodedMetal", rough=0.8, metal=0.6, pattern="rust"),
    "brass": dict(color=srgb(176, 136, 66), roblox="Metal", rough=0.35, metal=1.0, pattern="tarnish"),
    "wood": dict(color=srgb(98, 66, 40), roblox="Wood", rough=0.8, metal=0.0, pattern="grain"),
    "wood_dark": dict(color=srgb(58, 38, 24), roblox="Wood", rough=0.75, metal=0.0, pattern="grain"),
    "wood_old": dict(color=srgb(104, 92, 78), roblox="Wood", rough=0.9, metal=0.0, pattern="grain_old"),
    "charred": dict(color=srgb(30, 24, 20), roblox="Wood", rough=0.95, metal=0.0, pattern="char"),
    "bark": dict(color=srgb(64, 58, 52), roblox="Wood", rough=0.95, metal=0.0, pattern="bark"),
    "burlap": dict(color=srgb(104, 82, 54), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave_blood"),
    "burlap_clean": dict(color=srgb(112, 90, 62), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave"),
    "rope": dict(color=srgb(168, 146, 104), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave"),
    "canvas": dict(color=srgb(70, 80, 56), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave"),
    "cloth_white": dict(color=srgb(220, 214, 196), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave_blood"),
    "leather": dict(color=srgb(214, 186, 160), roblox="Leather", rough=0.7, metal=0.0, pattern="skin"),
    "plastic_orange": dict(color=srgb(196, 92, 30), roblox="Plastic", rough=0.5, metal=0.0, pattern="dirty"),
    "plastic_black": dict(color=srgb(22, 22, 22), roblox="Plastic", rough=0.6, metal=0.0, pattern="dirty"),
    "rubber": dict(color=srgb(18, 18, 18), roblox="Rubber", rough=0.95, metal=0.0, pattern="dirty"),
    "paint_olive": dict(color=srgb(74, 80, 52), roblox="Metal", rough=0.6, metal=0.3, pattern="chipped"),
    "paint_red": dict(color=srgb(150, 30, 24), roblox="Metal", rough=0.5, metal=0.3, pattern="chipped"),
    "paint_yellow": dict(color=srgb(196, 152, 40), roblox="CorrodedMetal", rough=0.6, metal=0.3, pattern="chipped"),
    "paint_white": dict(color=srgb(222, 222, 216), roblox="Metal", rough=0.4, metal=0.2, pattern="dirty"),
    "paint_rescue_red": dict(color=srgb(176, 28, 28), roblox="Metal", rough=0.4, metal=0.2, pattern="dirty"),
    "glass": dict(color=srgb(150, 170, 165), roblox="Glass", rough=0.05, metal=0.0, pattern="none", transparency=0.55),
    "glass_dark": dict(color=srgb(40, 56, 64), roblox="Glass", rough=0.05, metal=0.0, pattern="none", transparency=0.3),
    "lens": dict(color=srgb(255, 244, 214), roblox="Neon", rough=0.1, metal=0.0, pattern="none"),
    "flame": dict(color=srgb(255, 160, 70), roblox="Neon", rough=0.1, metal=0.0, pattern="none"),
    "ember": dict(color=srgb(255, 96, 30), roblox="Neon", rough=0.1, metal=0.0, pattern="ember"),
    "stone": dict(color=srgb(92, 92, 90), roblox="Slate", rough=0.9, metal=0.0, pattern="stone"),
    "stone_dark": dict(color=srgb(70, 70, 70), roblox="Slate", rough=0.9, metal=0.0, pattern="stone"),
    "dirt": dict(color=srgb(56, 44, 32), roblox="Ground", rough=1.0, metal=0.0, pattern="dirt"),
    "ash": dict(color=srgb(48, 44, 40), roblox="Slate", rough=1.0, metal=0.0, pattern="dirt"),
    "paper": dict(color=srgb(214, 204, 176), roblox="SmoothPlastic", rough=0.9, metal=0.0, pattern="paper"),
    "ceramic": dict(color=srgb(232, 228, 216), roblox="SmoothPlastic", rough=0.3, metal=0.0, pattern="dirty"),
    "label_gold": dict(color=srgb(206, 156, 46), roblox="SmoothPlastic", rough=0.4, metal=0.2, pattern="dirty"),
    "battery_black": dict(color=srgb(30, 30, 32), roblox="SmoothPlastic", rough=0.5, metal=0.0, pattern="dirty"),
    "blood": dict(color=srgb(90, 8, 8), roblox="Glass", rough=0.1, metal=0.0, pattern="none"),
    # farmhouse furniture
    "leather_sofa": dict(color=srgb(74, 42, 30), roblox="Leather", rough=0.6, metal=0.0, pattern="dirty"),
    "brick": dict(color=srgb(112, 58, 44), roblox="Brick", rough=0.9, metal=0.0, pattern="stone"),
    "marble": dict(color=srgb(196, 192, 182), roblox="Marble", rough=0.3, metal=0.0, pattern="dirty"),
    "enamel": dict(color=srgb(214, 206, 182), roblox="SmoothPlastic", rough=0.35, metal=0.0, pattern="chipped"),
    "cast_iron": dict(color=srgb(38, 36, 36), roblox="Metal", rough=0.6, metal=0.8, pattern="scratch"),
    "chrome": dict(color=srgb(186, 188, 192), roblox="Metal", rough=0.2, metal=1.0, pattern="scratch"),
    "linen": dict(color=srgb(186, 178, 158), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave_blood"),
    "quilt": dict(color=srgb(120, 70, 60), roblox="Fabric", rough=1.0, metal=0.0, pattern="weave"),
    "book_red": dict(color=srgb(110, 34, 30), roblox="Fabric", rough=0.8, metal=0.0, pattern="dirty"),
    "book_green": dict(color=srgb(44, 70, 46), roblox="Fabric", rough=0.8, metal=0.0, pattern="dirty"),
    "book_brown": dict(color=srgb(96, 70, 44), roblox="Fabric", rough=0.8, metal=0.0, pattern="dirty"),
}


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def mul(a, s):
    return tuple(max(0.0, min(1.0, c * s)) for c in a)


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def fbm(p, octaves=3):
    total, amp, freq = 0.0, 1.0, 1.0
    for _ in range(octaves):
        total += noise.noise(p * freq) * amp
        amp *= 0.5
        freq *= 2.1
    return total


RUST = srgb(92, 42, 20)
BLOOD = srgb(58, 5, 4)
MOSS = srgb(56, 70, 36)
DIRT = srgb(52, 42, 30)


def shade(matkey, base, co, n, zmin, zmax, seed, face_jitter):
    """Return the vertex colour (sRGB) for one face corner."""
    pattern = PALETTE[matkey]["pattern"]
    p = co + Vector((seed * 17.3, seed * 3.1, seed * 7.7))
    height = (co.z - zmin) / max(zmax - zmin, 1e-4)
    col = base
    if pattern == "none":
        return col
    # broad tonal variation + ambient darkening toward the bottom / crevices
    variation = 1.0 + fbm(p * 1.7) * 0.12 + face_jitter
    occlusion = 0.78 + 0.22 * smoothstep(0.0, 0.35, height)
    if n.z < -0.5:
        occlusion *= 0.82
    col = mul(col, variation * occlusion)

    if pattern == "scratch":
        s = noise.noise(p * 14.0)
        if s > 0.55:
            col = mix(col, (0.8, 0.8, 0.82), (s - 0.55) * 1.6)
        col = mix(col, DIRT, smoothstep(0.35, 0.0, height) * 0.25)
    elif pattern == "blood":
        b = fbm(p * 2.2 + Vector((3, 1, 2)))
        col = mix(col, BLOOD, smoothstep(0.05, 0.4, b) * 0.95)
        col = mix(col, RUST, smoothstep(0.35, 0.6, noise.noise(p * 5.0)) * 0.5)
    elif pattern == "rust":
        r = fbm(p * 2.6)
        col = mix(col, RUST, smoothstep(-0.1, 0.45, r))
        col = mix(col, srgb(60, 34, 22), smoothstep(0.4, 0.7, noise.noise(p * 9.0)) * 0.6)
    elif pattern == "tarnish":
        col = mix(col, srgb(70, 80, 50), smoothstep(0.2, 0.6, fbm(p * 4.0)) * 0.5)
    elif pattern in ("grain", "grain_old"):
        axis = co.x if abs(n.x) < 0.7 else co.y
        g = math.sin((axis * 3.0 + fbm(p * 0.9) * 2.5) * 9.0)
        col = mul(col, 0.9 + g * 0.08)
        if pattern == "grain_old":
            col = mix(col, srgb(70, 74, 60), smoothstep(0.2, 0.6, fbm(p * 1.3)) * 0.35)
        col = mix(col, DIRT, smoothstep(0.25, 0.0, height) * 0.3)
    elif pattern == "char":
        col = mix(col, srgb(14, 12, 10), smoothstep(-0.2, 0.4, fbm(p * 3.0)))
        if noise.noise(p * 8.0) > 0.6:
            col = mix(col, srgb(120, 40, 16), 0.5)
    elif pattern == "bark":
        g = abs(math.sin(math.atan2(co.y, co.x) * 14.0 + fbm(p * 1.2) * 4.0))
        col = mul(col, 0.75 + g * 0.35)
        col = mix(col, MOSS, smoothstep(0.3, 0.8, fbm(p * 0.8)) * smoothstep(0.2, 0.0, height) * 0.8)
    elif pattern in ("weave", "weave_blood"):
        w = (math.sin(co.x * 60.0) * math.sin(co.z * 60.0 + co.y * 60.0)) * 0.05
        col = mul(col, 1.0 + w)
        col = mix(col, DIRT, smoothstep(0.1, 0.6, fbm(p * 1.5)) * 0.45)
        if pattern == "weave_blood":
            col = mix(col, BLOOD, smoothstep(0.35, 0.7, fbm(p * 1.4 + Vector((9, 2, 4)))) * 0.85)
    elif pattern == "skin":
        col = mix(col, srgb(160, 110, 96), smoothstep(0.0, 0.6, fbm(p * 2.0)) * 0.5)
        col = mix(col, BLOOD, smoothstep(0.45, 0.8, fbm(p * 1.6 + Vector((4, 4, 1)))) * 0.7)
    elif pattern == "dirty":
        col = mix(col, DIRT, smoothstep(0.1, 0.7, fbm(p * 1.8)) * 0.35)
    elif pattern == "chipped":
        c = noise.noise(p * 6.0)
        if c > 0.35:
            col = mix(col, RUST, smoothstep(0.35, 0.6, c))
        col = mix(col, DIRT, smoothstep(0.3, 0.0, height) * 0.4)
    elif pattern == "stone":
        col = mul(col, 0.85 + fbm(p * 3.0) * 0.25)
        if n.z > 0.45:
            col = mix(col, MOSS, smoothstep(0.0, 0.5, fbm(p * 1.1) + (n.z - 0.45)) * 0.8)
        col = mix(col, DIRT, smoothstep(0.2, 0.0, height) * 0.5)
    elif pattern == "dirt":
        col = mul(col, 0.8 + fbm(p * 2.5) * 0.3)
    elif pattern == "paper":
        if abs(n.z) > 0.7:
            line = (co.y * 9.0) % 1.0
            if 0.0 < line < 0.08 and abs(co.x) < 0.33:
                col = mix(col, srgb(70, 60, 50), 0.55)
        col = mix(col, srgb(150, 120, 80), smoothstep(0.1, 0.7, fbm(p * 2.0)) * 0.35)
    elif pattern == "ember":
        col = mix(col, srgb(255, 200, 80), smoothstep(0.0, 0.6, noise.noise(p * 4.0)))
    return tuple(max(0.0, min(1.0, c)) for c in col)


# ----------------------------------------------------------------------------- geometry helpers
class Prop:
    def __init__(self, name, pivot="bottom"):
        self.name = name
        self.objects = []
        self.pivot = pivot

    def add(self, ob, mat):
        ob["mat"] = mat
        self.objects.append(ob)
        return ob


def link(name, bm):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def place(ob, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    ob.location = loc
    ob.rotation_euler = rot
    ob.scale = scale
    return ob


def bake_modifiers(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)


def bevel(ob, width, segments=2, angle=40):
    mod = ob.modifiers.new("Bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    mod.angle_limit = math.radians(angle)
    bake_modifiers(ob)
    return ob


def subsurf(ob, levels=1):
    mod = ob.modifiers.new("Sub", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    bake_modifiers(ob)
    return ob


def boolean_cut(ob, cutter):
    mod = ob.modifiers.new("Bool", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    bake_modifiers(ob)
    bpy.data.objects.remove(cutter, do_unlink=True)
    return ob


def box(prop, mat, size, loc=(0, 0, 0), rot=(0, 0, 0), bev=0.0, seg=2):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    ob = place(link("box", bm), loc, rot)
    if bev > 0:
        bevel(ob, bev, seg)
    return prop.add(ob, mat) if prop else ob


def cyl(prop, mat, r, depth, loc=(0, 0, 0), rot=(0, 0, 0), seg=24, r2=None, bev=0.0, caps=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=depth)
    ob = place(link("cyl", bm), loc, rot)
    if bev > 0:
        bevel(ob, bev, 2)
    return prop.add(ob, mat) if prop else ob


def sphere(prop, mat, r, loc=(0, 0, 0), scale=(1, 1, 1), seg=24, rings=14, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=r)
    ob = place(link("sph", bm), loc, rot, scale)
    return prop.add(ob, mat) if prop else ob


def ico(prop, mat, r, loc=(0, 0, 0), subdiv=3, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
    ob = place(link("ico", bm), loc, (0, 0, 0), scale)
    return prop.add(ob, mat) if prop else ob


def torus(prop, mat, major, minor, loc=(0, 0, 0), rot=(0, 0, 0), seg=24, tseg=8, arc=2 * math.pi):
    bm = bmesh.new()
    rings = []
    closed = abs(arc - 2 * math.pi) < 1e-4
    count = seg if closed else seg + 1
    for i in range(count):
        a = arc * i / seg
        center = Vector((math.cos(a) * major, math.sin(a) * major, 0))
        radial = Vector((math.cos(a), math.sin(a), 0))
        ring = []
        for j in range(tseg):
            b = 2 * math.pi * j / tseg
            ring.append(bm.verts.new(center + radial * math.cos(b) * minor + Vector((0, 0, math.sin(b) * minor))))
        rings.append(ring)
    for i in range(count if closed else count - 1):
        r0, r1 = rings[i], rings[(i + 1) % count]
        for j in range(tseg):
            bm.faces.new((r0[j], r0[(j + 1) % tseg], r1[(j + 1) % tseg], r1[j]))
    ob = place(link("torus", bm), loc, rot)
    return prop.add(ob, mat) if prop else ob


def lathe(prop, mat, profile, seg=28, loc=(0, 0, 0), rot=(0, 0, 0), cap_bottom=True, cap_top=True):
    """Revolve a (radius, z) profile around the Z axis."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, z)))
        rings.append(ring)
    for k in range(len(rings) - 1):
        a, b = rings[k], rings[k + 1]
        for i in range(seg):
            bm.faces.new((a[i], a[(i + 1) % seg], b[(i + 1) % seg], b[i]))
    if cap_bottom and profile[0][0] > 1e-4:
        bm.faces.new(list(reversed(rings[0])))
    if cap_top and profile[-1][0] > 1e-4:
        bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = place(link("lathe", bm), loc, rot)
    return prop.add(ob, mat) if prop else ob


def tube(prop, mat, points, radius, seg=8, taper=None, closed=False, resolution=6, poly=False):
    """Sweep a circle along a bezier path (or straight segments with poly=True)."""
    cu = bpy.data.curves.new("tube", "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = max(1, seg // 4)
    cu.use_fill_caps = True
    if poly:
        sp = cu.splines.new("POLY")
        sp.points.add(len(points) - 1)
        for i, p in enumerate(points):
            sp.points[i].co = (p[0], p[1], p[2], 1.0)
            if taper:
                sp.points[i].radius = taper[i]
    else:
        sp = cu.splines.new("BEZIER")
        sp.bezier_points.add(len(points) - 1)
        for i, p in enumerate(points):
            bp = sp.bezier_points[i]
            bp.co = p
            bp.handle_left_type = "AUTO"
            bp.handle_right_type = "AUTO"
            if taper:
                bp.radius = taper[i]
    sp.use_cyclic_u = closed
    sp.resolution_u = resolution
    cob = bpy.data.objects.new("tubecurve", cu)
    bpy.context.collection.objects.link(cob)
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(cob.evaluated_get(dg))
    bpy.data.objects.remove(cob, do_unlink=True)
    ob = bpy.data.objects.new("tube", me)
    bpy.context.collection.objects.link(ob)
    return prop.add(ob, mat) if prop else ob


def displace(ob, amount, freq, seed=0.0, axis_mask=(1, 1, 1), mask=None):
    me = ob.data
    off = Vector((seed * 13.1, seed * 5.3, seed * 2.9))
    for v in me.vertices:
        if mask and not mask(v.co):
            continue
        d = noise.noise_vector(v.co * freq + off)
        v.co += Vector((d.x * axis_mask[0], d.y * axis_mask[1], d.z * axis_mask[2])) * amount
    me.update()
    return ob


def apply_transform(ob):
    ob.data.transform(ob.matrix_basis)
    ob.matrix_basis = Matrix.Identity(4)


def densify(ob, max_edge, passes=3):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for _ in range(passes):
        long_edges = [e for e in bm.edges if e.calc_length() > max_edge]
        if not long_edges:
            break
        bmesh.ops.subdivide_edges(bm, edges=long_edges, cuts=1, use_grid_fill=True)
    bm.to_mesh(ob.data)
    bm.free()


def array_around(prop, mat, builder, count, radius, z=0.0, phase=0.0):
    obs = []
    for i in range(count):
        a = phase + 2 * math.pi * i / count
        ob = builder()
        ob.location = (math.cos(a) * radius, math.sin(a) * radius, z)
        ob.rotation_euler.z = a
        obs.append(prop.add(ob, mat))
    return obs


# ----------------------------------------------------------------------------- props
def build_flashlight():
    p = Prop("Flashlight")
    # profile along the light's axis (x), revolved then laid along +X
    body = lathe(None, None, [
        (0.0, -0.52), (0.1, -0.52), (0.108, -0.5), (0.108, -0.44), (0.1, -0.43),
        (0.1, 0.32), (0.112, 0.36), (0.15, 0.47), (0.158, 0.5), (0.158, 0.6),
        (0.168, 0.61), (0.168, 0.66), (0.0, 0.66),
    ], seg=32)
    body.rotation_euler = (0, math.radians(90), 0)
    body.location = (0, 0, 0.17)
    p.add(body, "metal_dark")
    for i in range(7):  # knurled grip rings
        t = torus(None, None, 0.102, 0.012, (-0.32 + i * 0.06, 0, 0.17), (0, math.radians(90), 0), seg=16, tseg=4)
        p.add(t, "metal_dark")
    lens = cyl(None, None, 0.14, 0.01, (0.662, 0, 0.17), (0, math.radians(90), 0), seg=28)
    p.add(lens, "lens")
    sw = box(None, None, (0.12, 0.06, 0.04), (0.22, 0, 0.275), bev=0.012)
    p.add(sw, "rubber")
    p.add(torus(None, None, 0.05, 0.01, (-0.56, 0, 0.17), (math.radians(90), 0, 0), seg=16, tseg=5), "steel")
    return p


def build_cleaver():
    p = Prop("Cleaver")
    blade = box(None, None, (0.05, 1.1, 0.9), (0, -0.15, 1.25))
    densify(blade, 0.08, 4)
    # chip the cutting edge (the far side from the handle) and thin it
    for v in blade.data.vertices:
        if v.co.y < -0.5:
            v.co.y += random.uniform(-0.02, 0.03)
        if v.co.y < -0.42:
            v.co.x *= 0.3
    hole = cyl(None, None, 0.07, 0.3, (0, -0.45, 1.5), (0, math.radians(90), 0), seg=20)
    boolean_cut(blade, hole)
    bevel(blade, 0.008, 1)
    p.add(blade, "steel_bloody")
    spine = box(None, None, (0.07, 1.1, 0.06), (0, -0.15, 1.69), bev=0.01)
    p.add(spine, "steel")
    handle = box(None, None, (0.13, 0.2, 0.82), (0, 0.27, 0.42), bev=0.05, seg=3)
    p.add(handle, "wood_dark")
    for z in (0.18, 0.42, 0.66):
        p.add(cyl(None, None, 0.03, 0.15, (0, 0.27, z), (0, math.radians(90), 0), seg=12), "brass")
    p.add(box(None, None, (0.09, 0.22, 0.08), (0, 0.27, 0.84), bev=0.01), "steel")
    return p


def build_chainsaw():
    p = Prop("Chainsaw")
    body = box(None, None, (0.8, 1.4, 0.9), (0, 0, 0.45), bev=0.12, seg=3)
    p.add(body, "plastic_orange")
    cover = box(None, None, (0.82, 0.7, 0.5), (0, -0.2, 0.62), bev=0.08, seg=2)
    p.add(cover, "plastic_black")
    for i in range(6):
        p.add(box(None, None, (0.84, 0.04, 0.3), (0, 0.2 + i * 0.07, 0.4), bev=0.01), "plastic_black")
    bar = box(None, None, (0.12, 3.0, 0.36), (0, 2.1, 0.45), bev=0.02)
    p.add(bar, "steel_bloody")
    p.add(cyl(None, None, 0.18, 0.12, (0, 3.6, 0.45), (0, math.radians(90), 0), seg=20), "steel")
    for i in range(26):
        y = 0.65 + i * 0.115
        for z in (0.645, 0.255):
            p.add(box(None, None, (0.16, 0.08, 0.06), (0, y, z)), "metal_dark")
    handle = tube(None, None, [(0, -0.45, 0.9), (0, -0.2, 1.3), (0, 0.35, 1.3), (0, 0.55, 0.9)], 0.06, seg=8)
    p.add(handle, "plastic_black")
    rear = tube(None, None, [(0, -0.7, 0.3), (0, -1.15, 0.32), (0, -1.2, 0.75), (0, -0.7, 0.8)], 0.07, seg=8, poly=True)
    p.add(rear, "plastic_black")
    p.add(cyl(None, None, 0.12, 0.3, (0.45, -0.1, 0.5), (0, math.radians(90), 0), seg=16), "metal_dark")
    p.add(box(None, None, (0.08, 0.25, 0.08), (-0.45, -0.3, 0.75), bev=0.02), "plastic_black")
    return p


def build_lantern():
    p = Prop("Lantern")
    p.add(lathe(None, None, [(0.0, 0.0), (0.3, 0.0), (0.31, 0.05), (0.29, 0.14), (0.2, 0.18), (0.18, 0.22), (0.0, 0.22)], seg=28), "iron")
    p.add(lathe(None, None, [(0.17, 0.22), (0.22, 0.32), (0.25, 0.48), (0.22, 0.66), (0.15, 0.76)], seg=28, cap_bottom=False, cap_top=False), "glass")
    p.add(lathe(None, None, [(0.0, 0.3), (0.035, 0.3), (0.03, 0.45), (0.0, 0.5)], seg=10), "flame")
    p.add(lathe(None, None, [(0.0, 0.74), (0.2, 0.74), (0.24, 0.8), (0.18, 0.9), (0.1, 0.96), (0.06, 1.0), (0.0, 1.0)], seg=24), "iron")
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        x, y = math.cos(a) * 0.27, math.sin(a) * 0.27
        p.add(tube(None, None, [(x * 0.75, y * 0.75, 0.2), (x, y, 0.48), (x * 0.8, y * 0.8, 0.76)], 0.012, seg=6), "iron")
    p.add(torus(None, None, 0.26, 0.012, (0, 0, 0.48), seg=28, tseg=5), "iron")
    p.add(tube(None, None, [(-0.2, 0, 0.82), (-0.18, 0, 1.12), (0, 0, 1.2), (0.18, 0, 1.12), (0.2, 0, 0.82)], 0.014, seg=6), "iron")
    return p


def build_sack_mask():
    p = Prop("SackMask", pivot="center")
    sack = sphere(None, None, 0.7, (0, 0, 0), (1.0, 0.97, 1.12), seg=48, rings=32)
    apply_transform(sack)
    me = sack.data
    for v in me.vertices:
        c = v.co
        ang = math.atan2(c.y, c.x)
        # flatter face, gathered fabric folds toward the neck, lumpy crown
        if c.y > 0.32:
            c.y = 0.32 + (c.y - 0.32) * 0.6
        if c.z < -0.35:
            k = smoothstep(-0.35, -0.8, c.z)
            fold = 1.0 + math.sin(ang * 11.0) * 0.07 * k
            c.x *= (1 - k * 0.38) * fold
            c.y *= (1 - k * 0.38) * fold
        if c.z > 0.45:
            c.z += math.sin(ang * 5.0) * 0.04
        # deep, uneven eye holes
        for ex, ez in ((-0.21, 0.12), (0.23, 0.1)):
            d = math.hypot((c.x - ex) / 1.15, c.z - ez)
            if c.y > 0.15 and d < 0.15:
                c.y -= (0.15 - d) * 1.4
    displace(sack, 0.04, 4.0, seed=1.0)
    displace(sack, 0.015, 14.0, seed=2.0)
    p.add(sack, "burlap")
    top = lathe(None, None, [(0.22, 0.66), (0.09, 0.82), (0.16, 0.92), (0.1, 1.02), (0.03, 1.1), (0.0, 1.11)], seg=20)
    displace(top, 0.035, 8.0, seed=3.0)
    p.add(top, "burlap")
    p.add(torus(None, None, 0.12, 0.035, (0, 0, 0.84), seg=16, tseg=5), "rope")
    cinch = torus(None, None, 0.45, 0.05, (0, 0, -0.68), seg=40, tseg=6)
    displace(cinch, 0.025, 7.0, seed=4.0)
    p.add(cinch, "rope")
    p.add(tube(None, None, [(0.28, 0.33, -0.7), (0.35, 0.44, -0.86), (0.31, 0.46, -1.05)], 0.032, seg=6), "rope")
    p.add(tube(None, None, [(0.22, 0.38, -0.72), (0.2, 0.52, -0.9), (0.24, 0.55, -1.12)], 0.032, seg=6), "rope")
    # eye holes: black voids with stitched rims
    for ex, ez in ((-0.21, 0.12), (0.23, 0.1)):
        p.add(sphere(None, None, 0.11, (ex, 0.36, ez), (1.15, 0.35, 1.0), seg=16, rings=10), "metal_dark")
        for i in range(6):
            a = i * math.pi / 3
            p.add(box(None, None, (0.018, 0.02, 0.07), (ex + math.cos(a) * 0.14, 0.43, ez + math.sin(a) * 0.13), (0, a, 0)), "rope")
    # sewn-shut mouth: a dark seam with heavy cross stitches and a blood drip
    p.add(box(None, None, (0.46, 0.03, 0.028), (0.0, 0.47, -0.27), (0, math.radians(-4), 0)), "metal_dark")
    for i in range(7):
        x = -0.2 + i * 0.066
        p.add(box(None, None, (0.016, 0.022, 0.16), (x, 0.485, -0.27), (0, math.radians(28 if i % 2 else -28), 0)), "rope")
    p.add(box(None, None, (0.04, 0.02, 0.22), (0.08, 0.47, -0.4)), "blood")
    return p


def build_generator():
    p = Prop("Generator")
    w, d, h = 3.6, 2.2, 2.9
    frame = [
        [(-1.75, -1.05, 0.1), (-1.75, -1.05, 2.75), (1.75, -1.05, 2.75), (1.75, -1.05, 0.1)],
        [(-1.75, 1.05, 0.1), (-1.75, 1.05, 2.75), (1.75, 1.05, 2.75), (1.75, 1.05, 0.1)],
    ]
    for pts in frame:
        p.add(tube(None, None, pts, 0.07, seg=8, poly=True), "metal_dark")
    for x in (-1.75, 1.75):
        p.add(tube(None, None, [(x, -1.05, 0.12), (x, 1.05, 0.12)], 0.07, seg=8, poly=True), "metal_dark")
        p.add(tube(None, None, [(x, -1.05, 2.75), (x, 1.05, 2.75)], 0.07, seg=8, poly=True), "metal_dark")
    engine = box(None, None, (2.4, 1.6, 1.3), (-0.3, 0, 0.85), bev=0.06)
    p.add(engine, "iron")
    for i in range(7):
        p.add(box(None, None, (0.05, 1.5, 0.5), (-1.1 + i * 0.16, 0, 1.6), bev=0.01), "iron")
    tank = box(None, None, (2.6, 1.6, 0.8), (0, 0, 2.25), bev=0.25, seg=4)
    p.add(tank, "paint_yellow")
    p.add(cyl(None, None, 0.16, 0.12, (0.7, 0.3, 2.68), seg=16, bev=0.02), "metal_dark")
    panel = box(None, None, (0.12, 1.3, 0.9), (1.45, 0, 1.0), bev=0.02)
    p.add(panel, "metal_dark")
    for i, z in enumerate((0.75, 1.25)):
        p.add(cyl(None, None, 0.09, 0.06, (1.53, -0.35 + i * 0.7, z), (0, math.radians(90), 0), seg=14), "plastic_orange")
    p.add(box(None, None, (0.04, 0.12, 0.2), (1.53, 0.2, 1.0)), "steel")
    p.add(box(None, None, (0.04, 0.14, 0.14), (1.53, -0.25, 1.1)), "flame")
    p.add(cyl(None, None, 0.22, 1.3, (-1.3, -0.75, 1.2), (0, math.radians(90), 0), seg=18, bev=0.03), "rust")
    p.add(tube(None, None, [(-1.95, -0.75, 1.2), (-2.1, -0.75, 1.4), (-2.1, -0.75, 1.8)], 0.07, seg=8), "rust")
    p.add(tube(None, None, [(-0.5, 0.75, 1.0), (-0.2, 0.95, 0.9), (0.3, 0.95, 1.1)], 0.03, seg=6), "rubber")
    return p


def build_radio():
    p = Prop("Radio")
    case = box(None, None, (2.0, 1.1, 1.2), (0, 0, 0.6), bev=0.06, seg=3)
    p.add(case, "paint_olive")
    p.add(box(None, None, (1.8, 0.06, 0.95), (0, 0.55, 0.6), bev=0.02), "metal_dark")
    for i in range(4):
        p.add(cyl(None, None, 0.09, 0.1, (-0.6 + i * 0.4, 0.62, 0.4), (math.radians(90), 0, 0), seg=16, bev=0.015), "ceramic")
    p.add(box(None, None, (0.9, 0.05, 0.3), (0.0, 0.6, 0.86), bev=0.02), "flame")
    for i in range(5):
        p.add(cyl(None, None, 0.035, 0.05, (-0.75 + i * 0.12, 0.6, 0.86), (math.radians(90), 0, 0), seg=10), "steel")
    for x in (-1.06, 1.06):
        p.add(tube(None, None, [(x, -0.35, 0.8), (x * 1.12, 0, 0.95), (x, 0.35, 0.8)], 0.04, seg=6), "metal_dark")
    handset = tube(None, None, [(0.9, 0.3, 1.25), (1.0, 0.0, 1.35), (0.9, -0.3, 1.25)], 0.08, seg=10)
    p.add(handset, "plastic_black")
    for y in (-0.33, 0.33):
        p.add(sphere(None, None, 0.13, (0.9, y, 1.22), (1, 1, 0.7), seg=14, rings=8), "plastic_black")
    p.add(tube(None, None, [(0.95, 0.3, 1.15), (1.2, 0.5, 0.8), (1.1, 0.45, 0.4), (0.95, 0.4, 0.2)], 0.015, seg=6), "plastic_black")
    p.add(cyl(None, None, 0.03, 3.0, (-0.8, -0.3, 2.6), seg=8, r2=0.012), "metal_dark")
    p.add(cyl(None, None, 0.07, 0.15, (-0.8, -0.3, 1.25), seg=12), "metal_dark")
    return p


def build_gas_can():
    p = Prop("GasCan")
    body = box(None, None, (0.7, 1.2, 1.6), (0, 0, 0.8), bev=0.08, seg=3)
    p.add(body, "paint_red")
    for side in (-1, 1):
        for a in (-1, 1):
            p.add(box(None, None, (0.03, 1.05, 0.08), (side * 0.36, 0, 0.8), (math.radians(30 * a), 0, 0), bev=0.01), "paint_red")
    for y in (-0.35, 0, 0.35):
        p.add(tube(None, None, [(0, y - 0.06, 1.58), (0, y - 0.05, 1.78), (0, y + 0.05, 1.78), (0, y + 0.06, 1.58)], 0.035, seg=6), "paint_red")
    p.add(cyl(None, None, 0.1, 0.18, (0, 0.45, 1.66), (math.radians(-30), 0, 0), seg=16, bev=0.02), "metal_dark")
    return p


def build_barrel():
    p = Prop("Barrel")
    profile = [(0.0, 0.0), (1.1, 0.0), (1.14, 0.08)]
    for i in range(1, 12):
        z = i * 3.4 / 12
        bulge = math.sin(math.pi * z / 3.4) * 0.08
        profile.append((1.14 + bulge, z))
    profile += [(1.14, 3.32), (1.1, 3.4), (0.0, 3.4)]
    body = lathe(None, None, profile, seg=40)
    displace(body, 0.03, 1.4, seed=5.0)
    p.add(body, "rust")
    for z in (0.45, 1.7, 2.95):
        bulge = math.sin(math.pi * z / 3.4) * 0.08
        p.add(torus(None, None, 1.16 + bulge, 0.05, (0, 0, z), seg=40, tseg=6), "iron")
    p.add(cyl(None, None, 0.12, 0.06, (0.6, 0.2, 3.42), seg=14), "iron")
    return p


def build_crate():
    p = Prop("Crate")
    s = 3.0
    rng = random.Random(4)
    for face in range(4):
        rot = (0, 0, face * math.pi / 2)
        for i in range(4):
            z = 0.4 + i * 0.73
            pl = box(None, None, (s - 0.2, 0.12, 0.62), (0, s / 2 - 0.06, z), bev=0.02)
            pl.rotation_euler = rot
            pl.location = Matrix.Rotation(rot[2], 4, "Z") @ Vector((0, s / 2 - 0.06, z))
            p.add(pl, "wood_old" if rng.random() > 0.5 else "wood")
    for z in (0.06, s - 0.06):
        for i in range(5):
            p.add(box(None, None, (s, 0.56, 0.12), (0, -s / 2 + 0.3 + i * 0.6, z), bev=0.02), "wood")
    for x in (-1, 1):
        for y in (-1, 1):
            p.add(box(None, None, (0.25, 0.25, s), (x * (s / 2 - 0.12), y * (s / 2 - 0.12), s / 2), bev=0.03), "wood_dark")
    return p


def build_chair(ropes):
    p = Prop("ChairRopes" if ropes else "Chair")
    leg_profile = [(0.0, 0.0), (0.1, 0.0), (0.12, 0.1), (0.08, 0.4), (0.12, 0.8), (0.09, 1.2), (0.11, 1.7), (0.11, 1.8), (0.0, 1.8)]
    for x in (-0.95, 0.95):
        for y in (-0.95, 0.95):
            p.add(lathe(None, None, leg_profile, seg=12, loc=(x, y, 0)), "wood")
        post = [(0.0, 1.8), (0.11, 1.8), (0.09, 2.6), (0.12, 3.4), (0.09, 4.2), (0.13, 4.45), (0.0, 4.6)]
        p.add(lathe(None, None, post, seg=12, loc=(x, -0.95, 0)), "wood")
    seat = box(None, None, (2.2, 2.2, 0.22), (0, 0, 1.9), bev=0.06, seg=2)
    p.add(seat, "wood")
    p.add(box(None, None, (2.0, 0.16, 0.45), (0, -0.95, 4.25), bev=0.05), "wood_dark")
    for x in (-0.5, 0, 0.5):
        p.add(box(None, None, (0.14, 0.1, 2.1), (x, -0.95, 3.1), bev=0.03), "wood")
    for y in (-0.95, 0.95):
        p.add(box(None, None, (1.8, 0.08, 0.08), (0, y, 0.6), bev=0.02), "wood_dark")
    for x in (-0.95, 0.95):
        p.add(box(None, None, (0.08, 1.8, 0.08), (x, 0, 0.75), bev=0.02), "wood_dark")
    if ropes:
        for z in (2.6, 3.4):
            for k in range(3):
                pts = [(-1.15, -1.0 + k * 0.03, z + k * 0.06), (0, -1.12 - k * 0.02, z + 0.02 + k * 0.06), (1.15, -1.0 + k * 0.03, z + k * 0.06)]
                p.add(tube(None, None, pts, 0.045, seg=6), "rope")
        for x in (-0.95, 0.95):
            for k in range(3):
                p.add(torus(None, None, 0.16, 0.04, (x, 0.95, 0.45 + k * 0.09), seg=14, tseg=5), "rope")
        p.add(tube(None, None, [(1.15, -1.0, 2.6), (1.25, -0.8, 2.1), (1.2, -0.7, 1.6)], 0.04, seg=6), "rope")
    return p


def build_body_bag():
    p = Prop("BodyBag")
    bag = sphere(None, None, 1.0, (0, 0, 0), (1, 1, 1), seg=36, rings=20)
    apply_transform(bag)
    for v in bag.data.vertices:
        c = v.co
        # capsule: stretch along X, head end slightly bigger, bend slightly
        x = c.x * 3.0
        r = 0.75 if x < 0 else 0.68
        if abs(x) < 1.8:
            pass
        shoulders = 1.0 + 0.12 * math.exp(-((x + 1.3) ** 2) * 3)
        neck = 1.0 - 0.18 * math.exp(-((x + 2.1) ** 2) * 6)
        c.x = x
        c.y = c.y * r * shoulders * neck
        c.z = c.z * r * 0.9 * shoulders * neck + 0.75
    displace(bag, 0.06, 2.5, seed=6.0)
    displace(bag, 0.015, 12.0, seed=7.0)
    p.add(bag, "burlap")
    for x in (-2.0, -0.9, 0.4, 1.7):
        rr = 0.7 if x < 0 else 0.64
        t = torus(None, None, rr, 0.05, (x, 0, 0.72), (0, math.radians(90), 0), seg=28, tseg=6)
        displace(t, 0.02, 6.0, seed=x)
        p.add(t, "rope")
    return p


def build_cage():
    p = Prop("Cage")
    p.add(box(None, None, (4.4, 4.4, 0.3), (0, 0, 0.15), bev=0.04), "iron")
    p.add(box(None, None, (4.4, 4.4, 0.3), (0, 0, 5.3), bev=0.04), "iron")
    for i in range(8):
        t = -2.0 + i * (4.0 / 7)
        for s in (-2.0, 2.0):
            p.add(cyl(None, None, 0.07, 5.0, (t, s, 2.72), seg=8), "iron")
            p.add(cyl(None, None, 0.07, 5.0, (s, t, 2.72), seg=8), "iron")
    for z in (1.8, 3.6):
        for s in (-2.0, 2.0):
            p.add(box(None, None, (4.1, 0.1, 0.1), (0, s, z)), "iron")
            p.add(box(None, None, (0.1, 4.1, 0.1), (s, 0, z)), "iron")
    p.add(box(None, None, (0.35, 0.18, 0.4), (0.6, 2.1, 2.6), bev=0.04), "brass")
    p.add(torus(None, None, 0.12, 0.025, (0.6, 2.1, 2.88), (math.radians(90), 0, 0), seg=14, tseg=5), "steel")
    return p


def build_gravestone():
    p = Prop("Gravestone")
    slab = box(None, None, (2.0, 0.5, 2.2), (0, 0, 1.1), bev=0.06)
    top = cyl(None, None, 1.0, 0.5, (0, 0, 2.2), (math.radians(90), 0, 0), seg=28)
    p.add(slab, "stone")
    p.add(top, "stone")
    for ob in (slab, top):
        densify(ob, 0.25, 3)
        displace(ob, 0.04, 3.0, seed=8.0)
    p.add(box(None, None, (0.14, 0.06, 0.9), (0, 0.26, 2.0)), "stone_dark")
    p.add(box(None, None, (0.6, 0.06, 0.14), (0, 0.26, 2.15)), "stone_dark")
    for i in range(3):
        p.add(box(None, None, (1.1 - i * 0.2, 0.06, 0.06), (0, 0.26, 1.4 - i * 0.22)), "stone_dark")
    mound = sphere(None, None, 1.0, (0, -2.6, 0), (1.2, 2.5, 0.35), seg=24, rings=12)
    apply_transform(mound)
    for v in mound.data.vertices:
        v.co.z = max(v.co.z, -0.05)
    displace(mound, 0.08, 2.0, seed=9.0)
    p.add(mound, "dirt")
    return p


def build_grave_cross():
    p = Prop("GraveCross")
    p.add(box(None, None, (0.35, 0.3, 3.6), (0, 0, 1.6), (0, math.radians(4), 0), bev=0.04), "wood_old")
    p.add(box(None, None, (2.0, 0.28, 0.32), (0, 0, 2.55), (0, math.radians(4), 0), bev=0.04), "wood_old")
    p.add(torus(None, None, 0.24, 0.05, (0, 0, 2.55), (math.radians(90), 0, math.radians(45)), seg=14, tseg=5), "rope")
    mound = sphere(None, None, 1.0, (0, -2.6, 0), (1.2, 2.5, 0.35), seg=24, rings=12)
    apply_transform(mound)
    for v in mound.data.vertices:
        v.co.z = max(v.co.z, -0.05)
    displace(mound, 0.08, 2.0, seed=10.0)
    p.add(mound, "dirt")
    return p


def build_dead_tree(name, seed, height):
    p = Prop(name)
    rng = random.Random(seed)

    def branch(origin, direction, length, radius, depth):
        pts = [origin]
        pos = Vector(origin)
        d = Vector(direction).normalized()
        steps = 4
        for _ in range(steps):
            d = (d + Vector((rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35), rng.uniform(-0.05, 0.25)))).normalized()
            pos = pos + d * (length / steps)
            pts.append(tuple(pos))
        taper = [1.0 - i / (len(pts)) * 0.85 for i in range(len(pts))]
        p.add(tube(None, None, pts, radius, seg=8 if depth == 0 else 5, taper=taper, resolution=3 if depth else 4), "bark")
        if depth < 2:
            for _ in range(rng.randint(2, 4) if depth == 0 else rng.randint(1, 3)):
                k = rng.randint(1, len(pts) - 2)
                o = pts[k]
                ang = rng.uniform(0, 2 * math.pi)
                nd = Vector((math.cos(ang), math.sin(ang), rng.uniform(0.2, 0.9)))
                branch(o, nd, length * rng.uniform(0.35, 0.55), radius * taper[k] * 0.55, depth + 1)

    # trunk with root flare
    branch((0, 0, 0), (0, 0, 1), height * 0.8, height * 0.045, 0)
    for i in range(5):
        a = i * 2 * math.pi / 5 + rng.uniform(-0.3, 0.3)
        p.add(tube(None, None, [(0, 0, 0.8), (math.cos(a) * 1.0, math.sin(a) * 1.0, 0.2), (math.cos(a) * 1.8, math.sin(a) * 1.8, -0.3)], height * 0.025, seg=6, taper=[1.0, 0.7, 0.3]), "bark")
    return p


def build_rock(name, seed):
    p = Prop(name)
    rock = ico(None, None, 1.0, (0, 0, 0), subdiv=4)
    rng = random.Random(seed)
    sx, sy, sz = rng.uniform(1.6, 2.4), rng.uniform(1.3, 2.0), rng.uniform(0.9, 1.4)
    for v in rock.data.vertices:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    displace(rock, 0.45, 0.6, seed=seed)
    displace(rock, 0.12, 2.2, seed=seed + 1)
    # flat-ish base sunk into the ground
    for v in rock.data.vertices:
        if v.co.z < -0.3 * sz:
            v.co.z = -0.3 * sz + (v.co.z + 0.3 * sz) * 0.2
    p.add(rock, "stone")
    return p


def build_helicopter():
    p = Prop("Helicopter")
    body = box(None, None, (6.6, 13.0, 5.6), (0, 0.5, 5.0))
    densify(body, 1.6, 3)
    for v in body.data.vertices:
        c = v.co
        # rounded nose and tapered tail end
        t = (c.y - 0.5) / 6.5
        if t > 0.3:
            k = (t - 0.3) / 0.7
            c.z = 5.0 + (c.z - 5.0) * (1 - k * 0.35) - k * 0.4
            c.x *= 1 - k * 0.3
        if t < -0.5:
            k = (-0.5 - t) / 0.5
            c.z = 5.0 + (c.z - 5.0) * (1 - k * 0.25) + k * 0.6
            c.x *= 1 - k * 0.25
    subsurf(body, 1)
    for v in body.data.vertices:
        c = v.co
        if c.z < 3.6:
            c.z = max(c.z, 2.4)
    p.add(body, "paint_white")
    stripe = box(None, None, (6.75, 11.0, 0.8), (0, 0.6, 3.9), bev=0.3, seg=3)
    p.add(stripe, "paint_rescue_red")
    glass = sphere(None, None, 2.6, (0, 5.4, 5.6), (1.15, 1.0, 0.75), seg=28, rings=16)
    apply_transform(glass)
    for v in glass.data.vertices:
        if v.co.y < 5.6:
            v.co.y = 5.6 + (v.co.y - 5.6) * 0.2
    p.add(glass, "glass_dark")
    boom = cyl(None, None, 1.0, 13.0, (0, -12.0, 6.0), (math.radians(90), 0, 0), seg=20, r2=0.45)
    p.add(boom, "paint_white")
    fin = box(None, None, (0.3, 2.6, 4.0), (0, -18.0, 7.6), (math.radians(-18), 0, 0), bev=0.12)
    p.add(fin, "paint_rescue_red")
    p.add(box(None, None, (4.0, 1.2, 0.2), (0, -16.5, 6.2), bev=0.08), "paint_white")
    p.add(cyl(None, None, 0.6, 0.25, (0.4, -18.4, 8.4), (0, math.radians(90), 0), seg=16), "metal_dark")
    for x in (-3.4, 3.4):
        p.add(tube(None, None, [(x, -4.8, 0.35), (x, 4.6, 0.35), (x, 5.6, 0.8)], 0.18, seg=8), "metal_dark")
        for y in (-3.0, 3.0):
            p.add(tube(None, None, [(x, y, 0.4), (x * 0.85, y, 1.6), (x * 0.7, y, 2.6)], 0.14, seg=8), "metal_dark")
    p.add(cyl(None, None, 0.45, 1.6, (0, 0, 8.4), seg=16), "metal_dark")
    p.add(box(None, None, (3.2, 4.0, 1.0), (0, -0.8, 7.9), bev=0.3, seg=2), "paint_white")
    p.add(cyl(None, None, 0.45, 0.6, (0, 6.4, 2.6), (math.radians(80), 0, 0), seg=16), "metal_dark")
    p.add(cyl(None, None, 0.38, 0.05, (0, 6.7, 2.55), (math.radians(80), 0, 0), seg=16), "lens")
    p.add(box(None, None, (0.1, 3.6, 3.2), (3.36, 0.5, 4.8), bev=0.05), "metal_dark")
    return p


def build_campfire():
    p = Prop("Campfire")
    rng = random.Random(12)
    for i in range(11):
        a = i * 2 * math.pi / 11
        r = ico(None, None, 0.42, (math.cos(a) * 1.85, math.sin(a) * 1.85, 0.25), subdiv=2,
                scale=(rng.uniform(1.0, 1.4), rng.uniform(0.8, 1.1), rng.uniform(0.6, 0.9)))
        apply_transform(r)
        displace(r, 0.08, 3.0, seed=i)
        p.add(r, "stone")
    ash = cyl(None, None, 1.5, 0.12, (0, 0, 0.05), seg=24)
    p.add(ash, "ash")
    for i in range(4):
        a = i * math.pi / 4 + 0.2
        log = cyl(None, None, 0.2, 2.6, (0, 0, 0.45), (math.radians(78), 0, a), seg=10)
        p.add(log, "charred")
    p.add(ico(None, None, 0.5, (0, 0, 0.3), subdiv=2, scale=(1.4, 1.4, 0.5)), "ember")
    return p


def build_tent():
    p = Prop("Tent")
    for side in (-1, 1):
        sheet = box(None, None, (0.06, 7.2, 4.4), (0, 0, 0))
        densify(sheet, 0.5, 4)
        me = sheet.data
        for v in me.vertices:
            # sag between the poles
            sag = math.sin((v.co.y / 7.2 + 0.5) * math.pi) * 0.25 * math.sin((v.co.z / 4.4 + 0.5) * math.pi)
            v.co.x -= sag
        sheet.rotation_euler = (0, side * math.radians(-37), 0)
        sheet.location = (side * 1.65, 0, 2.2)
        p.add(sheet, "canvas")
    for y in (-3.5, 3.5):
        for side in (-1, 1):
            p.add(cyl(None, None, 0.05, 5.0, (side * 1.5, y, 2.2), (0, side * math.radians(-33), 0), seg=8), "wood")
    p.add(cyl(None, None, 0.06, 7.4, (0, 0, 4.45), (math.radians(90), 0, 0), seg=8), "wood")
    for y in (-3.6, 3.6):
        for side in (-1, 1):
            p.add(tube(None, None, [(0, y, 4.45), (side * 2.0, y * 1.25, 2.0), (side * 3.4, y * 1.4, 0.05)], 0.02, seg=4), "rope")
            p.add(cyl(None, None, 0.05, 0.6, (side * 3.4, y * 1.4, 0.15), seg=6), "wood")
    p.add(box(None, None, (6.4, 7.0, 0.06), (0, 0, 0.03)), "canvas")
    return p


def build_house_key():
    p = Prop("HouseKey")
    p.add(torus(None, None, 0.09, 0.022, (-0.2, 0, 0.03), seg=20, tseg=6), "iron")
    for a in (0.0, 2.1, 4.2):
        p.add(torus(None, None, 0.035, 0.012, (-0.2 + math.cos(a) * 0.09, math.sin(a) * 0.09, 0.03), seg=12, tseg=5), "iron")
    p.add(cyl(None, None, 0.022, 0.4, (0.08, 0, 0.03), (0, math.radians(90), 0), seg=10), "iron")
    p.add(box(None, None, (0.1, 0.03, 0.12), (0.24, 0, -0.03 + 0.06)), "iron")
    p.add(box(None, None, (0.03, 0.03, 0.05), (0.2, 0, -0.02 + 0.06)), "iron")
    return p


def build_fuse():
    p = Prop("Fuse")
    p.add(cyl(None, None, 0.08, 0.42, (0, 0, 0.09), (0, math.radians(90), 0), seg=20, bev=0.01), "ceramic")
    for x in (-0.25, 0.25):
        p.add(cyl(None, None, 0.09, 0.1, (x, 0, 0.09), (0, math.radians(90), 0), seg=20, bev=0.01), "brass")
    p.add(cyl(None, None, 0.082, 0.12, (0, 0, 0.09), (0, math.radians(90), 0), seg=20), "paint_red")
    return p


def build_battery():
    p = Prop("Battery")
    for y in (-0.105, 0.105):
        p.add(cyl(None, None, 0.1, 0.32, (-0.05, y, 0.1), (0, math.radians(90), 0), seg=20, bev=0.01), "battery_black")
        p.add(cyl(None, None, 0.101, 0.12, (0.17, y, 0.1), (0, math.radians(90), 0), seg=20, bev=0.01), "label_gold")
        p.add(cyl(None, None, 0.035, 0.04, (0.25, y, 0.1), (0, math.radians(90), 0), seg=12), "steel")
    return p


def build_bandage():
    p = Prop("Bandage")
    roll = lathe(None, None, [(0.06, -0.15), (0.18, -0.15), (0.18, 0.15), (0.06, 0.15)], seg=24, cap_bottom=False, cap_top=False)
    roll.rotation_euler = (math.radians(90), 0, 0)
    roll.location = (0, 0, 0.18)
    p.add(roll, "cloth_white")
    p.add(cyl(None, None, 0.06, 0.3, (0, 0, 0.18), (math.radians(90), 0, 0), seg=16, caps=False), "cloth_white")
    strip = box(None, None, (0.28, 0.6, 0.015), (0, 0.45, 0.008))
    densify(strip, 0.08, 3)
    for v in strip.data.vertices:
        v.co.z += math.sin(v.co.y * 9) * 0.01
    p.add(strip, "cloth_white")
    return p


def build_note():
    p = Prop("Note")
    sheet = box(None, None, (0.85, 1.1, 0.012), (0, 0, 0.02))
    densify(sheet, 0.12, 4)
    for v in sheet.data.vertices:
        v.co.z += (v.co.x ** 2) * 0.12 + abs(math.sin(v.co.y * 3)) * 0.01
    p.add(sheet, "paper")
    return p


# ----------------------------------------------------------------------------- farmhouse furniture
# Each one matches the footprint of the box stand-in it replaces in
# House.luau (front faces +Y here, -Z in Roblox; scaled to the stand-in's
# height on the client).


def turned_leg(height, r=0.16):
    return [(0.0, 0.0), (r * 0.7, 0.0), (r, height * 0.08), (r * 0.6, height * 0.3), (r * 1.1, height * 0.5),
            (r * 0.6, height * 0.7), (r * 0.9, height * 0.92), (r * 0.9, height), (0.0, height)]


def build_sofa():
    p = Prop("Sofa")
    L, D = 11.0, 4.4
    box(p, "wood_dark", (L - 0.4, D - 0.4, 0.5), (0, 0, 0.55), bev=0.05)
    for x in (-L / 2 + 0.6, L / 2 - 0.6):
        for y in (-D / 2 + 0.5, D / 2 - 0.5):
            cyl(p, "wood_dark", 0.16, 0.35, (x, y, 0.17), seg=10, r2=0.11)
    cw = (L - 2.4) / 3
    for i in range(3):
        x = -L / 2 + 1.2 + cw * (i + 0.5)
        seat = box(p, "leather_sofa", (cw - 0.08, D - 1.3, 0.75), (x, 0.4, 1.15), bev=0.2, seg=3)
        displace(seat, 0.05, 1.3, seed=i)
        back = box(p, "leather_sofa", (cw - 0.1, 0.9, 1.9), (x, -D / 2 + 1.05, 2.45), rot=(math.radians(-10), 0, 0), bev=0.3, seg=3)
        displace(back, 0.06, 1.1, seed=i + 5)
        for bx in (-0.55, 0.55):  # tufting buttons
            sphere(p, "leather_sofa", 0.07, (x + bx, -D / 2 + 1.55, 2.6), seg=8, rings=5)
    box(p, "leather_sofa", (L - 0.6, 0.7, 3.0), (0, -D / 2 + 0.35, 2.0), bev=0.25, seg=3)
    for s in (-1, 1):
        box(p, "leather_sofa", (1.1, D - 0.2, 1.9), (s * (L / 2 - 0.55), 0.05, 1.5), bev=0.3, seg=3)
        cyl(p, "leather_sofa", 0.62, D - 0.1, (s * (L / 2 - 0.55), 0.05, 2.5), rot=(math.pi / 2, 0, 0), seg=18)
    # a tear with the stuffing showing
    sphere(p, "cloth_white", 0.22, (-L / 2 + 2.2, 1.6, 1.55), scale=(1.4, 0.5, 0.4), seg=10, rings=6)
    return p


def build_fireplace():
    p = Prop("Fireplace")
    rng = random.Random(7)
    W, H = 8.0, 8.4
    breast = box(p, "brick", (W, 2.0, H - 0.6), (0, -0.3, (H - 0.6) / 2), bev=0.04)
    boolean_cut(breast, box(None, None, (3.6, 2.4, 3.4), (0, 0.4, 1.6)))
    box(p, "ash", (3.5, 0.25, 3.3), (0, -1.15, 1.65))
    box(p, "stone_dark", (W + 0.6, 3.0, 0.35), (0, 0.4, 0.175), bev=0.04)
    box(p, "wood_dark", (W + 0.8, 2.6, 0.45), (0, 0.2, H - 0.45), bev=0.06)
    for x in (-W / 2 + 0.45, W / 2 - 0.45):
        box(p, "wood_dark", (0.5, 0.6, 1.0), (x, 0.9, H - 1.2), bev=0.05)
    # rough stones standing proud of the brick
    placed = 0
    while placed < 30:
        x = rng.uniform(-W / 2 + 0.5, W / 2 - 0.5)
        z = rng.uniform(0.7, H - 1.4)
        if abs(x) < 2.2 and z < 3.8:
            continue
        st = box(p, "stone", (rng.uniform(0.7, 1.3), 0.3, rng.uniform(0.45, 0.75)), (x, 0.75, z), bev=0.08, seg=2)
        displace(st, 0.05, 2.0, seed=placed)
        placed += 1
    for x in (-1.0, 1.0):
        box(p, "iron", (0.14, 1.1, 0.14), (x, 0.1, 0.55))
        cyl(p, "iron", 0.1, 0.5, (x, 0.6, 0.6), seg=8)
    for i, x in enumerate((-0.4, 0.3)):
        cyl(p, "charred", 0.26, 2.5, (x * 0.4, -0.2 + i * 0.25, 0.75 + i * 0.25), rot=(0, math.pi / 2, 0.2 * i), seg=10)
    return p


def build_coffee_table():
    p = Prop("CoffeeTable")
    box(p, "wood_old", (5.0, 3.0, 0.3), (0, 0, 1.8), bev=0.05)
    for x in (-2.0, 2.0):
        for y in (-1.15, 1.15):
            p.add(lathe(None, None, turned_leg(1.65, 0.14), seg=10, loc=(x, y, 0)), "wood_dark")
    box(p, "wood_dark", (4.4, 2.4, 0.08), (0, 0, 0.5), bev=0.02)
    return p


def build_bookshelf():
    p = Prop("Bookshelf")
    rng = random.Random(12)
    W, D, H = 6.0, 1.4, 9.0
    box(p, "wood_dark", (W, 0.15, H), (0, -D / 2 + 0.07, H / 2))
    for x in (-W / 2 + 0.1, W / 2 - 0.1):
        box(p, "wood_dark", (0.2, D, H), (x, 0, H / 2), bev=0.03)
    shelves = 5
    for i in range(shelves + 1):
        z = 0.2 + i * (H - 0.4) / shelves
        box(p, "wood_dark", (W - 0.2, D, 0.18), (0, 0, z), bev=0.02)
        if i == shelves:
            break
        x = -W / 2 + 0.3
        while x < W / 2 - 0.5:
            t = rng.uniform(0.18, 0.4)
            h = rng.uniform(0.9, 1.45)
            if rng.random() < 0.12:
                x += 0.4  # a gap
                continue
            lean = rng.uniform(-0.12, 0.12) if rng.random() < 0.2 else 0.0
            mat = rng.choice(("book_red", "book_green", "book_brown", "paper"))
            box(p, mat, (t, D - 0.35, h), (x + t / 2, 0.05, z + 0.1 + h / 2), rot=(0, lean, 0), bev=0.02)
            x += t + 0.02
    box(p, "wood_dark", (W + 0.3, D + 0.2, 0.3), (0, 0.05, H), bev=0.05)
    return p


def build_dining_table():
    p = Prop("DiningTable")
    L, D, H = 16.0, 5.0, 3.5
    for i in range(5):
        y = -D / 2 + 0.5 + i * (D - 1.0) / 4
        plank = box(p, "wood_old" if i % 2 else "wood", (L, (D - 0.1) / 5, 0.32), (0, y, H - 0.16), bev=0.03)
        displace(plank, 0.02, 1.5, seed=i)
    box(p, "wood_dark", (L - 1.4, D - 1.0, 0.5), (0, 0, H - 0.55))
    for x in (-L / 2 + 1.0, 0.0, L / 2 - 1.0):
        for y in (-D / 2 + 0.7, D / 2 - 0.7):
            p.add(lathe(None, None, turned_leg(H - 0.3, 0.22), seg=12, loc=(x, y, 0)), "wood_dark")
    # old knife cuts and a dark stain soaked into the wood
    box(p, "blood", (2.2, 1.4, 0.02), (2.5, 0.4, H + 0.005))
    return p


def build_china_hutch():
    p = Prop("ChinaHutch")
    W, D, H = 7.0, 2.5, 8.0
    box(p, "wood_dark", (W, D, 3.4), (0, 0, 1.9), bev=0.05)
    for x in (-W / 4, W / 4):
        box(p, "wood", (W / 2 - 0.3, 0.1, 2.6), (x, D / 2, 1.9), bev=0.04)
        sphere(p, "brass", 0.09, (x + (0.9 if x < 0 else -0.9), D / 2 + 0.08, 2.0), seg=8, rings=5)
    box(p, "wood_dark", (W, D - 0.9, H - 3.6), (0, -0.45, 3.6 + (H - 3.6) / 2), bev=0.04)
    box(p, "glass", (W - 0.6, 0.06, H - 4.2), (0, D / 2 - 0.9, 3.6 + (H - 3.6) / 2))
    for z in (4.9, 6.4):
        box(p, "wood_dark", (W - 0.4, D - 1.1, 0.12), (0, -0.5, z))
        for i in range(5):
            cyl(p, "ceramic", 0.42, 0.06, (-2.6 + i * 1.3, -0.75, z + 0.45), rot=(math.radians(75), 0, 0), seg=18)
    box(p, "wood_dark", (W + 0.3, D - 0.6, 0.35), (0, -0.3, H), bev=0.05)
    return p


def build_kitchen_counter():
    p = Prop("KitchenCounter")
    W, D, H = 4.0, 2.6, 3.65
    box(p, "wood", (W, D - 0.2, H - 0.45), (0, -0.1, (H - 0.45) / 2 + 0.1), bev=0.03)
    box(p, "wood_dark", (W - 0.1, D - 0.4, 0.3), (0, -0.1, 0.15))
    box(p, "wood_old", (W - 0.5, 0.08, 0.7), (0, D / 2 - 0.15, H - 1.0), bev=0.03)
    for x in (-W / 4, W / 4):
        box(p, "wood_old", (W / 2 - 0.35, 0.08, 1.7), (x, D / 2 - 0.15, 1.15), bev=0.03)
        box(p, "brass", (0.08, 0.1, 0.4), (x + (0.6 if x < 0 else -0.6), D / 2 - 0.05, 1.5))
    box(p, "brass", (0.5, 0.1, 0.08), (0, D / 2 - 0.05, H - 1.0))
    top = box(p, "marble", (W + 0.1, D + 0.15, 0.3), (0, 0.05, H - 0.15), bev=0.04)
    displace(top, 0.01, 2.0)
    return p


def build_stove():
    p = Prop("Stove")
    W, D, H = 4.0, 3.0, 3.6
    box(p, "enamel", (W, D - 0.4, H - 1.0), (0, 0, 0.6 + (H - 1.0) / 2), bev=0.12, seg=3)
    for x in (-W / 2 + 0.3, W / 2 - 0.3):
        for y in (-D / 2 + 0.4, D / 2 - 0.4):
            cyl(p, "cast_iron", 0.12, 0.6, (x, y, 0.3), seg=8, r2=0.08)
    box(p, "cast_iron", (W + 0.1, D - 0.3, 0.12), (0, 0, H - 0.4))
    for x in (-0.9, 0.9):
        for y in (-0.55, 0.55):
            torus(p, "cast_iron", 0.42, 0.06, (x, y, H - 0.3), seg=16, tseg=6)
            cyl(p, "cast_iron", 0.36, 0.05, (x, y, H - 0.32), seg=16)
    box(p, "cast_iron", (W - 0.6, 0.08, 1.5), (0, D / 2 - 0.15, 1.5), bev=0.04)
    box(p, "chrome", (2.2, 0.15, 0.12), (0, D / 2 + 0.05, 2.45))
    for i in range(4):
        cyl(p, "cast_iron", 0.12, 0.15, (-1.2 + i * 0.8, D / 2 - 0.1, H - 0.75), rot=(math.pi / 2, 0, 0), seg=10)
    box(p, "enamel", (W, 0.3, 1.4), (0, -D / 2 + 0.35, H + 0.25), bev=0.08)
    cyl(p, "cast_iron", 0.3, 4.0, (1.4, -D / 2 + 0.5, H + 2.0), seg=12)
    return p


def build_fridge():
    p = Prop("Fridge")
    W, D, H = 3.4, 3.0, 8.0
    body = box(p, "enamel", (W, D, H - 0.4), (0, 0, 0.4 + (H - 0.4) / 2), bev=0.55, seg=5)
    displace(body, 0.015, 1.5)
    box(p, "cast_iron", (W - 0.4, D - 0.4, 0.4), (0, 0, 0.2))
    box(p, "cast_iron", (W - 0.2, 0.05, 0.05), (0, D / 2 + 0.01, H - 2.4))
    box(p, "chrome", (0.16, 0.25, 1.3), (W / 2 - 0.45, D / 2 + 0.1, H - 3.5), bev=0.05)
    box(p, "chrome", (0.16, 0.25, 0.7), (W / 2 - 0.45, D / 2 + 0.1, H - 1.4), bev=0.05)
    box(p, "chrome", (1.4, 0.06, 0.25), (0, D / 2 + 0.03, H - 0.9))
    # a bloody hand print on the door
    box(p, "blood", (0.5, 0.02, 0.6), (W / 2 - 0.9, D / 2 + 0.02, H - 3.3), rot=(0, 0.3, 0))
    return p


def build_kitchen_table():
    p = Prop("KitchenTable")
    L, D, H = 8.0, 4.0, 3.25
    top = box(p, "wood_old", (L, D, 0.45), (0, 0, H - 0.22), bev=0.05)
    displace(top, 0.02, 1.2)
    for x in (-L / 2 + 0.5, L / 2 - 0.5):
        for y in (-D / 2 + 0.5, D / 2 - 0.5):
            box(p, "wood_dark", (0.45, 0.45, H - 0.45), (x, y, (H - 0.45) / 2), bev=0.04)
    box(p, "wood_dark", (L - 1.4, 0.15, 0.4), (0, 0, 0.6))
    box(p, "wood", (2.5, 1.6, 0.2), (0, 0, H + 0.1), bev=0.04)  # cutting board
    box(p, "blood", (1.0, 0.7, 0.02), (0.1, 0.1, H + 0.21))
    return p


def build_bed():
    p = Prop("Bed")
    W, L = 7.0, 9.4
    for x in (-W / 2 + 0.2, W / 2 - 0.2):
        for y, h in ((-L / 2 + 0.2, 5.0), (L / 2 - 0.2, 3.0)):
            p.add(lathe(None, None, turned_leg(h, 0.2), seg=12, loc=(x, y, 0)), "wood_dark")
    head = box(p, "wood_dark", (W - 0.4, 0.25, 2.6), (0, -L / 2 + 0.2, 3.4), bev=0.05)
    boolean_cut(head, box(None, None, (W - 1.6, 1.0, 1.6), (0, -L / 2 + 0.2, 3.4)))
    for i in range(5):
        box(p, "wood_dark", (0.18, 0.18, 1.6), (-2.0 + i, -L / 2 + 0.2, 3.4))
    box(p, "wood_dark", (W - 0.4, 0.25, 1.4), (0, L / 2 - 0.2, 1.9), bev=0.05)
    for x in (-W / 2 + 0.2, W / 2 - 0.2):
        box(p, "wood_dark", (0.25, L - 0.4, 0.6), (x, 0, 1.0))
    mattress = box(p, "linen", (W - 0.7, L - 0.7, 0.9), (0, 0, 1.75), bev=0.25, seg=3)
    displace(mattress, 0.05, 0.9)
    quilt = box(p, "quilt", (W - 0.5, L * 0.55, 0.25), (0, L * 0.18, 2.3), bev=0.2, seg=3)
    displace(quilt, 0.12, 0.8, seed=3)
    pillow = box(p, "cloth_white", (2.8, 1.4, 0.5), (0, -L / 2 + 1.3, 2.4), bev=0.25, seg=3)
    displace(pillow, 0.06, 1.4, seed=4)
    return p


def build_nightstand():
    p = Prop("Nightstand")
    box(p, "wood_dark", (2.0, 2.0, 2.2), (0, 0, 1.2), bev=0.05)
    box(p, "wood", (1.7, 0.08, 0.7), (0, 1.0, 1.7), bev=0.03)
    sphere(p, "brass", 0.08, (0, 1.08, 1.7), seg=8, rings=5)
    box(p, "wood_dark", (2.2, 2.2, 0.15), (0, 0, 2.38), bev=0.04)
    for x in (-0.85, 0.85):
        for y in (-0.85, 0.85):
            box(p, "wood_dark", (0.2, 0.2, 0.3), (x, y, 0.15))
    return p


def build_wardrobe():
    p = Prop("Wardrobe")
    W, D, H = 6.0, 3.0, 9.0
    box(p, "wood_dark", (W, D, H - 0.5), (0, 0, 0.35 + (H - 0.5) / 2), bev=0.05)
    for x in (-W / 4, W / 4):
        door = box(p, "wood", (W / 2 - 0.2, 0.12, H - 1.4), (x, D / 2 + 0.02, H / 2), bev=0.04)
        displace(door, 0.01, 2.0, seed=int(x * 10))
        for z in (2.6, 6.4):
            box(p, "wood_old", (W / 2 - 0.9, 0.06, 2.6), (x, D / 2 + 0.1, z), bev=0.04)
        box(p, "brass", (0.1, 0.12, 0.5), (x + (0.65 if x < 0 else -0.65), D / 2 + 0.15, H / 2))
    box(p, "wood_dark", (W + 0.4, D + 0.3, 0.45), (0, 0, H - 0.1), bev=0.08)
    for x in (-W / 2 + 0.3, W / 2 - 0.3):
        for y in (-D / 2 + 0.3, D / 2 - 0.3):
            sphere(p, "wood_dark", 0.22, (x, y, 0.2), seg=10, rings=6)
    return p


def build_dresser():
    p = Prop("Dresser")
    W, D = 6.0, 2.0
    box(p, "wood_dark", (W, D, 3.2), (0, 0, 1.8), bev=0.05)
    for i in range(3):
        z = 0.75 + i * 1.0
        box(p, "wood", (W - 0.4, 0.08, 0.85), (0, D / 2 + 0.02, z), bev=0.03)
        for x in (-1.5, 1.5):
            box(p, "brass", (0.5, 0.1, 0.1), (x, D / 2 + 0.1, z))
    box(p, "wood_dark", (W + 0.2, D + 0.2, 0.2), (0, 0, 3.45), bev=0.04)
    frame = box(p, "wood_dark", (4.2, 0.2, 4.2), (0, -D / 2 + 0.3, 5.6), bev=0.05)
    boolean_cut(frame, box(None, None, (3.6, 1.0, 3.6), (0, -D / 2 + 0.3, 5.6)))
    box(p, "glass_dark", (3.7, 0.05, 3.7), (0, -D / 2 + 0.3, 5.6))
    # the crack across the mirror
    tube(p, "paint_white", [(-1.6, -D / 2 + 0.35, 6.9), (-0.4, -D / 2 + 0.35, 5.9), (0.3, -D / 2 + 0.35, 5.4), (1.5, -D / 2 + 0.35, 4.1)], 0.02, seg=4, poly=True)
    return p


def build_bathtub():
    p = Prop("Bathtub")
    L, D, H = 8.0, 3.6, 2.6
    shell = lathe(None, None, [(0.0, 0.5), (0.9, 0.5), (1.0, 0.8), (1.0, H), (0.85, H), (0.82, 0.8), (0.0, 0.75)], seg=32, loc=(0, 0, 0))
    shell.scale = (L / 2 / 1.0, D / 2 / 1.0, 1.0)
    p.add(shell, "enamel")
    for x in (-L / 2 + 0.9, L / 2 - 0.9):
        for y in (-D / 2 + 0.5, D / 2 - 0.5):
            p.add(lathe(None, None, [(0.0, 0.0), (0.22, 0.0), (0.16, 0.25), (0.12, 0.6), (0.0, 0.6)], seg=10, loc=(x, y, 0)), "brass")
    tube(p, "brass", [(-L / 2 + 0.4, 0, H - 0.1), (-L / 2 + 0.5, 0, H + 0.9), (-L / 2 + 1.1, 0, H + 1.0), (-L / 2 + 1.2, 0, H + 0.6)], 0.09, seg=8)
    for y in (-0.5, 0.5):
        cyl(p, "brass", 0.12, 0.3, (-L / 2 + 0.45, y, H + 0.25), seg=10)
    return p


def build_grandfather_clock():
    p = Prop("GrandfatherClock")
    W, D = 2.2, 1.4
    box(p, "wood_dark", (W + 0.3, D + 0.2, 0.6), (0, 0, 0.3), bev=0.05)
    box(p, "wood_dark", (W - 0.3, D - 0.2, 4.6), (0, 0, 2.9), bev=0.04)
    box(p, "glass", (W - 0.8, 0.05, 3.6), (0, D / 2 - 0.08, 3.0))
    cyl(p, "brass", 0.05, 2.4, (0, 0.1, 3.4), seg=6)
    cyl(p, "brass", 0.32, 0.08, (0, 0.1, 2.1), rot=(math.pi / 2, 0, 0), seg=18)
    box(p, "wood_dark", (W, D, 2.2), (0, 0, 6.3), bev=0.05)
    cyl(p, "paper", 0.8, 0.08, (0, D / 2 + 0.02, 6.3), rot=(math.pi / 2, 0, 0), seg=28)
    torus(p, "brass", 0.82, 0.05, (0, D / 2 + 0.05, 6.3), rot=(math.pi / 2, 0, 0), seg=28, tseg=6)
    for i in range(12):
        a = i * math.pi / 6
        box(p, "metal_dark", (0.05, 0.03, 0.14), (math.sin(a) * 0.65, D / 2 + 0.07, 6.3 + math.cos(a) * 0.65), rot=(0, a, 0))
    box(p, "metal_dark", (0.05, 0.03, 0.5), (0.12, D / 2 + 0.09, 6.48), rot=(0, 0.5, 0))
    box(p, "metal_dark", (0.05, 0.03, 0.36), (-0.13, D / 2 + 0.1, 6.2), rot=(0, 2.4, 0))
    crown = box(p, "wood_dark", (W + 0.3, D + 0.2, 0.5), (0, 0, 7.65), bev=0.08)
    displace(crown, 0.0, 1.0)
    cyl(p, "wood_dark", 0.6, D, (0, 0, 7.9), rot=(math.pi / 2, 0, 0), seg=20)
    return p


BUILDERS = {
    "Sofa": build_sofa,
    "Fireplace": build_fireplace,
    "CoffeeTable": build_coffee_table,
    "Bookshelf": build_bookshelf,
    "DiningTable": build_dining_table,
    "ChinaHutch": build_china_hutch,
    "KitchenCounter": build_kitchen_counter,
    "Stove": build_stove,
    "Fridge": build_fridge,
    "KitchenTable": build_kitchen_table,
    "Bed": build_bed,
    "Nightstand": build_nightstand,
    "Wardrobe": build_wardrobe,
    "Dresser": build_dresser,
    "Bathtub": build_bathtub,
    "GrandfatherClock": build_grandfather_clock,
    "Flashlight": build_flashlight,
    "Cleaver": build_cleaver,
    "Chainsaw": build_chainsaw,
    "Lantern": build_lantern,
    "SackMask": build_sack_mask,
    "Generator": build_generator,
    "Radio": build_radio,
    "GasCan": build_gas_can,
    "Barrel": build_barrel,
    "Crate": build_crate,
    "Chair": lambda: build_chair(False),
    "ChairRopes": lambda: build_chair(True),
    "BodyBag": build_body_bag,
    "Cage": build_cage,
    "Gravestone": build_gravestone,
    "GraveCross": build_grave_cross,
    "DeadTree": lambda: build_dead_tree("DeadTree", 3, 26),
    "DeadTree2": lambda: build_dead_tree("DeadTree2", 9, 22),
    "Rock": lambda: build_rock("Rock", 21),
    "Rock2": lambda: build_rock("Rock2", 33),
    "Helicopter": build_helicopter,
    "Campfire": build_campfire,
    "Tent": build_tent,
    "HouseKey": build_house_key,
    "Fuse": build_fuse,
    "Battery": build_battery,
    "Bandage": build_bandage,
    "Note": build_note,
}


# ----------------------------------------------------------------------------- finishing
def finalize(prop):
    """Apply transforms, join by material, triangulate, shade, paint, UV."""
    for ob in prop.objects:
        apply_transform(ob)
    # bounds for pivot / height-based shading
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in prop.objects:
        for v in ob.data.vertices:
            for i in range(3):
                lo[i] = min(lo[i], v.co[i])
                hi[i] = max(hi[i], v.co[i])
    if prop.pivot == "bottom":
        offset = Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))
    else:
        offset = Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -(lo.z + hi.z) / 2))
    for ob in prop.objects:
        ob.data.transform(Matrix.Translation(offset))
    lo += offset
    hi += offset

    groups = {}
    for ob in prop.objects:
        groups.setdefault(ob["mat"], []).append(ob)

    parts = []
    for mat, obs in groups.items():
        bm = bmesh.new()
        for ob in obs:
            bm.from_mesh(ob.data)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        me = bpy.data.meshes.new(prop.name + "_" + mat)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(prop.name + "_" + mat, me)
        bpy.context.collection.objects.link(ob)
        me.shade_smooth()
        me.set_sharp_from_angle(angle=math.radians(38))
        paint(ob, mat, lo, hi, zlib.crc32(prop.name.encode()) % 97)
        parts.append((ob, mat))
    for ob in prop.objects:
        bpy.data.objects.remove(ob, do_unlink=True)
    return parts, lo, hi


def paint(ob, mat, lo, hi, seed):
    me = ob.data
    base = PALETTE[mat]["color"]
    attr = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
    uv = me.uv_layers.new(name="UVMap")
    rng = random.Random(seed)
    for poly in me.polygons:
        n = poly.normal
        jitter = rng.uniform(-0.035, 0.035)
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            c = shade(mat, base, co, n, lo.z, hi.z, seed, jitter)
            attr.data[li].color_srgb = (c[0], c[1], c[2], 1.0)
            if ax == 0:
                uv.data[li].uv = (co.y * 0.5, co.z * 0.5)
            elif ax == 1:
                uv.data[li].uv = (co.x * 0.5, co.z * 0.5)
            else:
                uv.data[li].uv = (co.x * 0.5, co.y * 0.5)
    me.color_attributes.active_color = attr
    me.color_attributes.render_color_index = 0


def blender_material(mat):
    name = "M_" + mat
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    pal = PALETTE[mat]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = pal["rough"]
    bsdf.inputs["Metallic"].default_value = pal["metal"]
    if pal["roblox"] == "Neon":
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 4.0
    if pal.get("transparency"):
        bsdf.inputs["Alpha"].default_value = 1 - pal["transparency"]
    return m


# ----------------------------------------------------------------------------- export
def to_roblox(v):
    return (v.x, v.z, -v.y)


def export_luau(prop, parts):
    entries = []
    total_tris = 0
    for ob, mat in parts:
        me = ob.data
        attr = me.color_attributes["Col"]
        uvl = me.uv_layers["UVMap"]
        normals = me.corner_normals
        lookup = {}
        verts = []
        indices = []
        for poly in me.polygons:
            for li in poly.loop_indices:
                co = to_roblox(me.vertices[me.loops[li].vertex_index].co)
                n = to_roblox(normals[li].vector)
                c = attr.data[li].color_srgb
                u = uvl.data[li].uv
                key = (
                    round(co[0], 4), round(co[1], 4), round(co[2], 4),
                    round(n[0] * 127), round(n[1] * 127), round(n[2] * 127),
                    round(c[0] * 255), round(c[1] * 255), round(c[2] * 255),
                    round(u[0], 3), round(u[1], 3),
                )
                idx = lookup.get(key)
                if idx is None:
                    idx = len(verts)
                    lookup[key] = idx
                    verts.append(key)
                indices.append(idx)
        lo = [min(v[i] for v in verts) for i in range(3)]
        hi = [max(v[i] for v in verts) for i in range(3)]
        span = [max(hi[i] - lo[i], 1e-5) for i in range(3)]
        blob = bytearray()
        for v in verts:
            q = [int(round((v[i] - lo[i]) / span[i] * 65535)) for i in range(3)]
            uq = [int(round((v[9 + i] % 64.0) / 64.0 * 65535)) for i in range(2)]
            blob += struct.pack("<HHHbbbBBBHH", q[0], q[1], q[2], max(-127, min(127, v[3])), max(-127, min(127, v[4])), max(-127, min(127, v[5])), v[6], v[7], v[8], uq[0], uq[1])
        iblob = struct.pack("<%dH" % len(indices), *indices)
        pal = PALETTE[mat]
        entries.append(
            "\t\t{\n"
            f'\t\t\tmaterial = "{pal["roblox"]}",\n'
            f'\t\t\ttransparency = {pal.get("transparency", 0)},\n'
            f"\t\t\tmin = Vector3.new({lo[0]:.4f}, {lo[1]:.4f}, {lo[2]:.4f}),\n"
            f"\t\t\tmax = Vector3.new({hi[0]:.4f}, {hi[1]:.4f}, {hi[2]:.4f}),\n"
            f"\t\t\tvertexCount = {len(verts)},\n"
            f"\t\t\ttriangleCount = {len(indices) // 3},\n"
            f'\t\t\tvertices = "{base64.b64encode(bytes(blob)).decode()}",\n'
            f'\t\t\tindices = "{base64.b64encode(iblob).decode()}",\n'
            "\t\t},\n"
        )
        total_tris += len(indices) // 3
    os.makedirs(LUAU_DIR, exist_ok=True)
    path = os.path.join(LUAU_DIR, prop.name + ".luau")
    with open(path, "w") as f:
        f.write("--!strict\n")
        f.write(f"-- {prop.name}: generated by tools/blender/build_props.py - do not edit by hand.\n")
        f.write(f"-- {total_tris} triangles in {len(parts)} material groups. Pivot: {prop.pivot}.\n")
        f.write("return {\n")
        f.write(f'\tname = "{prop.name}",\n')
        f.write(f'\tpivot = "{prop.pivot}",\n')
        f.write("\tparts = {\n")
        for e in entries:
            f.write(e)
        f.write("\t},\n}\n")
    return total_tris


def export_glb(prop, parts):
    os.makedirs(GLB_DIR, exist_ok=True)
    for ob in bpy.context.scene.objects:
        ob.select_set(False)
    for ob, mat in parts:
        ob.data.materials.clear()
        ob.data.materials.append(blender_material(mat))
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0][0]
    path = os.path.join(GLB_DIR, prop.name + ".glb")
    kwargs = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True)
    try:
        bpy.ops.export_scene.gltf(**kwargs, export_vertex_color="ACTIVE")
    except TypeError:
        bpy.ops.export_scene.gltf(**kwargs)


def render_preview(prop, parts, lo, hi):
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.013, 0.016, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    scene.world = world

    center = (lo + hi) / 2
    size = max((hi - lo).length, 0.5)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    direction = Vector((0.85, 1.25, 0.6)).normalized()
    cam.location = center + direction * size * 1.55
    look = (center - cam.location).normalized()
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam

    key = bpy.data.objects.new("key", bpy.data.lights.new("key", "AREA"))
    key.data.energy = 140 * size * size
    key.data.size = size
    key.data.color = (1.0, 0.82, 0.62)
    key.location = center + Vector((size * 1.2, size * 0.6, size * 1.4))
    key.rotation_euler = (center - key.location).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(key)
    rim = bpy.data.objects.new("rim", bpy.data.lights.new("rim", "AREA"))
    rim.data.energy = 90 * size * size
    rim.data.size = size
    rim.data.color = (0.55, 0.65, 1.0)
    rim.location = center + Vector((-size * 1.3, -size * 1.1, size * 0.8))
    rim.rotation_euler = (center - rim.location).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(rim)

    floor_bm = bmesh.new()
    bmesh.ops.create_grid(floor_bm, x_segments=1, y_segments=1, size=size * 4)
    floor = link("floor", floor_bm)
    floor.location = (center.x, center.y, lo.z - 0.001)
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.03, 0.028, 0.025, 1)
    floor.data.materials.append(fm)

    scene.render.filepath = os.path.join(PREVIEW_DIR, prop.name + ".png")
    bpy.ops.render.render(write_still=True)


def build(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    random.seed(zlib.crc32(name.encode()))
    prop = BUILDERS[name]()
    parts, lo, hi = finalize(prop)
    tris = export_luau(prop, parts)
    export_glb(prop, parts)
    if RENDER:
        render_preview(prop, parts, lo, hi)
    size = hi - lo
    print(f"[props] {name}: {tris} tris, size {size.x:.2f} x {size.z:.2f} x {size.y:.2f} studs (X x Y x Z roblox)")
    return name, tris


def main():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        argv = [a for a in argv[1:] if not a.endswith(".py")]
    names = argv or list(BUILDERS.keys())
    for name in names:
        build(name)
    # index module so the client can list available meshes
    available = sorted(n[:-5] for n in os.listdir(LUAU_DIR) if n.endswith(".luau") and n != "init.luau")
    with open(os.path.join(LUAU_DIR, "init.luau"), "w") as f:
        f.write("--!strict\n-- Generated by tools/blender/build_props.py. Lists the Blender meshes in this folder.\n")
        f.write("return {\n")
        for n in available:
            f.write(f'\t"{n}",\n')
        f.write("}\n")


if __name__ == "__main__":
    main()
