"""
The Cannibal Family - game pass icons (shared/GamePasses.luau).

Renders one 512 x 512 PNG per pass into assets/blender/icons/, on the
game's dark-red look: a lit object on a glowing backdrop inside a ring, kept
inside the circle Roblox crops pass icons to.

    Second Wind   a stitched-up heart, +1   (one extra life a night)
    Collector     three teeth, x2           (twice the Teeth)
    Survivor Kit  a bandage roll, a battery (one of each every night)

    blender -b --factory-startup -P tools/blender/build_pass_icons.py
"""

import math
import os

import bpy
import bmesh
from mathutils import Matrix, Vector

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "blender", "icons")
SIZE = 512


# ----------------------------------------------------------------------------- scene
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.film_transparent = False
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in scene.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.004, 0.002, 0.002, 1)
    scene.world = world
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 2.2
    cam = bpy.data.objects.new("Camera", cam_data)
    cam.location = (0, -10, 0)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return scene


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def material(name, color, rough=0.5, metal=0.0, emit=None, strength=0.0, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    for name_ in ("Coat Weight", "Clearcoat"):
        if name_ in bsdf.inputs:
            bsdf.inputs[name_].default_value = coat
            break
    if emit:
        for name_ in ("Emission Color", "Emission"):
            if name_ in bsdf.inputs:
                bsdf.inputs[name_].default_value = (*emit, 1)
                break
        bsdf.inputs["Emission Strength"].default_value = strength
    return m


def mesh_object(name, bm, mat, smooth=True):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    obj.data.materials.append(mat)
    return link(obj)


def subsurf(obj, levels=2):
    m = obj.modifiers.new("Subsurf", "SUBSURF")
    m.levels = levels
    m.render_levels = levels
    return m


def backdrop(inner, outer):
    """A glowing disc behind everything, brighter in the middle, and a ring."""
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, radius=1.6, segments=96)
    disc = mesh_object("Backdrop", bm, bpy.data.materials.new("Backdrop"), smooth=False)
    disc.rotation_euler = (math.radians(90), 0, 0)
    disc.location = (0, 3, 0)
    m = disc.data.materials[0]
    m.use_nodes = True
    nodes, links = m.node_tree.nodes, m.node_tree.links
    for n in list(nodes):
        nodes.remove(n)
    out = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    ramp = nodes.new("ShaderNodeValToRGB")
    grad = nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "SPHERICAL"
    coords = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (0.75, 0.75, 0.75)
    links.new(coords.outputs["Object"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], grad.inputs["Vector"])
    links.new(grad.outputs["Color"], ramp.inputs["Fac"])
    ramp.color_ramp.elements[0].color = (*outer, 1)
    ramp.color_ramp.elements[1].color = (*inner, 1)
    links.new(ramp.outputs["Color"], emission.inputs["Color"])
    emission.inputs["Strength"].default_value = 1.0
    links.new(emission.outputs["Emission"], out.inputs["Surface"])
    # the frame: a dark iron ring just inside the crop
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=False, radius=1.0, segments=128)
    ring = mesh_object("Ring", bm, material("Ring", (0.08, 0.03, 0.03), rough=0.35, metal=0.9), smooth=True)
    ring.rotation_euler = (math.radians(90), 0, 0)
    ring.location = (0, 1, 0)
    skin = ring.modifiers.new("Thick", "SKIN")
    for v in ring.data.skin_vertices[0].data:
        v.radius = (0.035, 0.035)
    subsurf(ring, 1)


def lights(key=(1.0, 0.85, 0.7), rim=(1.0, 0.15, 0.08)):
    def area(name, loc, rot, energy, color, size):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.color = color
        data.size = size
        obj = bpy.data.objects.new(name, data)
        obj.location = loc
        obj.rotation_euler = rot
        return link(obj)

    area("Key", (-2.5, -4, 3), (math.radians(55), 0, math.radians(-35)), 260, key, 2.5)
    area("Rim", (2.5, 2, 2), (math.radians(-60), 0, math.radians(140)), 420, rim, 2.0)
    area("Fill", (2, -4, -1.5), (math.radians(100), 0, math.radians(30)), 60, (0.6, 0.65, 0.8), 3)


def label(text, loc, size, mat, extrude=0.05):
    curve = bpy.data.curves.new(text, "FONT")
    curve.body = text
    curve.size = size
    curve.extrude = extrude
    curve.bevel_depth = 0.012
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    # a heavy face for the numbers (Blender's own font draws 1 like an I)
    for path in ("C:/Windows/Fonts/impact.ttf", "C:/Windows/Fonts/arialbd.ttf"):
        if os.path.exists(path):
            curve.font = bpy.data.fonts.load(path)
            break
    obj = bpy.data.objects.new(text, curve)
    obj.data.materials.append(mat)
    obj.location = loc
    obj.rotation_euler = (math.radians(90), 0, 0)
    return link(obj)


def render(name):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.abspath(os.path.join(OUT, name + ".png"))
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[pass icons] " + path)


# ----------------------------------------------------------------------------- shapes
def organic(obj, voxel=0.02, iterations=20, factor=0.9):
    """Even, rounded surface: remesh into voxels, then smooth the edges off."""
    remesh = obj.modifiers.new("Remesh", "REMESH")
    remesh.mode = "VOXEL"
    remesh.voxel_size = voxel
    smooth = obj.modifiers.new("Smooth", "SMOOTH")
    smooth.factor = factor
    smooth.iterations = iterations
    return obj


def place(obj, loc, rot=(0, 0, 0), scale=1.0):
    obj.location = loc
    obj.rotation_euler = rot
    obj.scale = (scale, scale, scale)
    return obj


def box(name, size, loc, mat, bevel=0.0, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = size
    obj.data.materials.append(mat)
    if bevel > 0:
        b = obj.modifiers.new("Bevel", "BEVEL")
        b.width = bevel
        b.segments = 4
        b.affect = "EDGES"
    return obj


def tube(name, a, b, radius, mat):
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=d.length, vertices=12, location=(a + b) / 2)
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    obj.data.materials.append(mat)
    return obj


# ----------------------------------------------------------------------------- Second Wind
def second_wind():
    reset()
    backdrop((0.16, 0.012, 0.01), (0.012, 0.002, 0.002))
    lights()
    # the classic heart curve, filled, thickened and rounded like muscle
    bm = bmesh.new()
    verts = []
    n = 120
    for i in range(n):
        t = i / n * math.tau
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        verts.append(bm.verts.new((x * 0.043, 0, y * 0.043 + 0.08)))
    bm.faces.new(verts)
    heart = mesh_object("Heart", bm, material("Heart", (0.5, 0.025, 0.02), rough=0.3, coat=0.7))
    solid = heart.modifiers.new("Solid", "SOLIDIFY")
    solid.thickness = 0.5
    solid.offset = 0
    organic(heart, 0.02, 30, 1.0)
    cast = heart.modifiers.new("Puff", "CAST")
    cast.factor = 0.3
    heart.rotation_euler = (0, math.radians(-10), 0)
    # sewn shut down the middle: a dark split and pale stitches across it
    dark = material("Split", (0.04, 0.0, 0.0), rough=0.6)
    thread = material("Thread", (0.9, 0.84, 0.66), rough=0.6)
    pts = [(-0.1, 0.5), (0.06, 0.28), (-0.07, 0.06), (0.07, -0.16), (-0.03, -0.4)]
    for a, b in zip(pts, pts[1:]):
        tube("Split", (a[0], -0.42, a[1]), (b[0], -0.42, b[1]), 0.022, dark)
    for (x, y) in [(0.0, 0.4), (0.0, 0.17), (0.0, -0.05), (0.02, -0.28)]:
        tube("Stitch", (x - 0.11, -0.45, y + 0.03), (x + 0.11, -0.45, y - 0.03), 0.016, thread)
    label("+1", (0.54, -0.6, -0.54), 0.6, material("Gold", (0.95, 0.62, 0.18), rough=0.22, metal=1.0))
    render("PassSecondWind")


# ----------------------------------------------------------------------------- Collector
def tooth(loc, rot, scale, mat):
    """A molar: a rounded crown with four cusps and two roots, one surface."""
    bm = bmesh.new()
    crown = bmesh.ops.create_cube(bm, size=1)["verts"]
    bmesh.ops.scale(bm, vec=(0.38, 0.32, 0.26), verts=crown)
    bmesh.ops.translate(bm, verts=crown, vec=(0, 0, 0.14))
    for dx in (-0.09, 0.09):
        for dy in (-0.07, 0.07):
            cusp = bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.1)["verts"]
            bmesh.ops.translate(bm, verts=cusp, vec=(dx, dy, 0.27))
    for dx in (-0.1, 0.1):
        root = bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.025, radius2=0.085, depth=0.42)["verts"]
        bmesh.ops.translate(bm, verts=root, vec=(dx, 0, -0.18))
        bmesh.ops.rotate(bm, verts=root, cent=(dx, 0, 0.02), matrix=Matrix.Rotation(math.radians(8 if dx > 0 else -8), 3, "Y"))
    obj = mesh_object("Tooth", bm, mat)
    organic(obj, 0.012, 18, 0.9)
    return place(obj, loc, rot, scale)


def collector():
    reset()
    backdrop((0.38, 0.16, 0.03), (0.02, 0.008, 0.004))
    lights(rim=(1.0, 0.45, 0.1))
    ivory = material("Ivory", (0.82, 0.74, 0.56), rough=0.32, coat=0.5)
    tooth((-0.36, 0, 0.16), (math.radians(14), math.radians(-24), math.radians(-12)), 1.35, ivory)
    tooth((0.34, 0.1, 0.24), (math.radians(-14), math.radians(28), math.radians(18)), 1.15, ivory)
    tooth((0.0, -0.15, -0.3), (math.radians(8), math.radians(6), math.radians(-4)), 1.25, ivory)
    label("x2", (0.53, -0.6, -0.54), 0.62, material("Gold", (0.95, 0.62, 0.18), rough=0.22, metal=1.0))
    render("PassCollector")


# ----------------------------------------------------------------------------- Survivor Kit
def survivor_kit():
    reset()
    backdrop((0.07, 0.17, 0.07), (0.004, 0.01, 0.005))
    lights(rim=(0.5, 1.0, 0.45))
    white = material("Tin", (0.82, 0.8, 0.76), rough=0.35, coat=0.6)
    red = material("Cross", (0.62, 0.02, 0.02), rough=0.4)
    # a first-aid tin: rounded box, a red cross, a handle on top
    tin = box("Tin", (1.06, 0.5, 0.74), (-0.1, 0.1, 0.12), white, bevel=0.09, rot=(0, math.radians(-6), 0))
    # one bar a hair in front of the other, so they don't fight where they cross
    for i, (sx, sz) in enumerate(((0.42, 0.13), (0.13, 0.42))):
        box("Cross", (sx, 0.04, sz), (-0.12, -0.16 - i * 0.012, 0.14), red, bevel=0.015, rot=(0, math.radians(-6), 0))
    tube("Handle", (-0.34, 0.1, 0.5), (-0.3, 0.1, 0.6), 0.03, red)
    tube("Handle", (0.1, 0.1, 0.55), (0.06, 0.1, 0.6), 0.03, red)
    tube("Handle", (-0.3, 0.1, 0.6), (0.06, 0.1, 0.6), 0.03, red)
    # a D-cell battery leaning across the front
    angle = math.radians(-38)
    body_mat = material("Battery", (0.04, 0.04, 0.04), rough=0.3, coat=0.6)
    band = material("Label", (0.88, 0.45, 0.04), rough=0.35, coat=0.6)
    steel = material("Steel", (0.78, 0.78, 0.8), rough=0.18, metal=1.0)
    center = Vector((0.4, -0.45, -0.32))
    axis = Vector((math.sin(angle), 0, math.cos(angle)))
    for offset, length, radius, mat in ((0.0, 0.78, 0.2, body_mat), (0.17, 0.34, 0.204, band), (0.42, 0.07, 0.07, steel), (-0.41, 0.04, 0.19, steel)):
        loc = center + axis * offset
        bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=length, vertices=48, location=loc, rotation=(0, angle, 0))
        part = bpy.context.active_object
        part.data.materials.append(mat)
        b = part.modifiers.new("Bevel", "BEVEL")
        b.width = 0.012
        b.segments = 2
    # and a bandage roll in front on the left: wound cloth, rings on its face
    cloth = material("Bandage", (0.88, 0.85, 0.78), rough=0.95)
    shade = material("BandageShade", (0.7, 0.66, 0.58), rough=0.95)
    for i, r in enumerate((0.27, 0.22, 0.17, 0.12)):
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=0.24 + i * 0.002, vertices=48, location=(-0.5, -0.5 - i * 0.002, -0.4), rotation=(math.radians(90), 0, 0))
        ring = bpy.context.active_object
        ring.data.materials.append(cloth if i % 2 == 0 else shade)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.06, depth=0.26, vertices=24, location=(-0.5, -0.51, -0.4), rotation=(math.radians(90), 0, 0))
    bpy.context.active_object.data.materials.append(material("Core", (0.3, 0.24, 0.18), rough=0.8))
    render("PassSurvivorKit")


if __name__ == "__main__":
    second_wind()
    collector()
    survivor_kit()
