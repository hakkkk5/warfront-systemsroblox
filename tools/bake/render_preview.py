"""
Renders the baked world (build/bake/*.model.json) with Blender so you can
check what Studio will show without opening it.

    python tools/bake/render_preview.py            # needs `pip install bpy`

Writes assets/screenshots/*.png.
"""

import json
import math
import os
import sys

import bpy  # noqa: I001 - bpy must be imported before bmesh / mathutils
import bmesh
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BAKE = os.path.join(ROOT, "build", "bake")
OUT = os.path.join(ROOT, "assets", "screenshots")

sys.path.insert(0, ROOT)


def to_blender(v):
    # Roblox (x, y, z) -> Blender (x, -z, y)
    return Vector((v[0], -v[2], v[1]))


def unit_shape(shape):
    """Vertices/faces of a unit shape centred at the origin (Roblox axes)."""
    if shape == "Cylinder":
        seg = 12
        verts = []
        for x in (-0.5, 0.5):
            for i in range(seg):
                a = 2 * math.pi * i / seg
                verts.append((x, math.cos(a) * 0.5, math.sin(a) * 0.5))
        faces = [list(range(seg))[::-1], list(range(seg, 2 * seg))]
        for i in range(seg):
            j = (i + 1) % seg
            faces.append([i, j, seg + j, seg + i])
        return verts, faces
    if shape == "Ball":
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=8, radius=0.5)
        verts = [tuple(v.co) for v in bm.verts]
        faces = [[v.index for v in f.verts] for f in bm.faces]
        bm.free()
        return verts, faces
    if shape == "Wedge":
        verts = [(-0.5, -0.5, -0.5), (0.5, -0.5, -0.5), (0.5, -0.5, 0.5), (-0.5, -0.5, 0.5), (-0.5, 0.5, 0.5), (0.5, 0.5, 0.5)]
        faces = [[0, 1, 2, 3], [3, 2, 5, 4], [0, 4, 5, 1], [0, 3, 4], [1, 5, 2]]
        return verts, faces
    verts = [(x, y, z) for x in (-0.5, 0.5) for y in (-0.5, 0.5) for z in (-0.5, 0.5)]
    faces = [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
    return verts, faces


SHAPES = {k: unit_shape(k) for k in ("Block", "Cylinder", "Ball", "Wedge")}


class Batch:
    def __init__(self):
        self.verts = []
        self.faces = []


def collect(node, batches, skip_names=()):
    cls = node.get("ClassName")
    props = node.get("Properties", {})
    if cls in ("Part", "WedgePart", "TrussPart") and node.get("Name") not in skip_names:
        transparency = props.get("Transparency", 0)
        if transparency < 0.9:
            size = props.get("Size", [4, 1, 2])
            cfv = props.get("CFrame", {}).get("CFrame", {"position": [0, 0, 0], "orientation": [[1, 0, 0], [0, 1, 0], [0, 0, 1]]})
            pos = cfv["position"]
            rot = cfv["orientation"]
            shape = "Wedge" if cls == "WedgePart" else props.get("Shape", "Block")
            if shape not in SHAPES:
                shape = "Block"
            verts, faces = SHAPES[shape]
            color = props.get("Color", [0.64, 0.64, 0.65])
            material = props.get("Material", "Plastic")
            key = (round(color[0] * 20), round(color[1] * 20), round(color[2] * 20), material == "Neon", transparency > 0.2)
            b = batches.setdefault(key, Batch())
            base = len(b.verts)
            sx, sy, sz = size
            if shape == "Cylinder":
                d = min(sy, sz)
                sy = sz = d
            if shape == "Ball":
                sy = sz = sx
            for v in verts:
                lx, ly, lz = v[0] * sx, v[1] * sy, v[2] * sz
                wx = rot[0][0] * lx + rot[0][1] * ly + rot[0][2] * lz + pos[0]
                wy = rot[1][0] * lx + rot[1][1] * ly + rot[1][2] * lz + pos[1]
                wz = rot[2][0] * lx + rot[2][1] * ly + rot[2][2] * lz + pos[2]
                b.verts.append(to_blender((wx, wy, wz)))
            for f in faces:
                b.faces.append([base + i for i in f])
    for child in node.get("Children", []):
        collect(child, batches, skip_names)


def build_scene(skip_names=()):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    batches = {}
    for name in ("TerrainPreview", "World", "Cannibals"):
        with open(os.path.join(BAKE, f"{name}.model.json")) as f:
            collect(json.load(f), batches, skip_names)
    total = 0
    for key, b in batches.items():
        me = bpy.data.meshes.new("batch")
        me.from_pydata(b.verts, [], b.faces)
        me.update()
        ob = bpy.data.objects.new("batch", me)
        bpy.context.collection.objects.link(ob)
        mat = bpy.data.materials.new("m")
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        col = (key[0] / 20, key[1] / 20, key[2] / 20)
        lin = tuple(c ** 2.2 for c in col) + (1,)
        bsdf.inputs["Base Color"].default_value = lin
        bsdf.inputs["Roughness"].default_value = 0.8
        if key[3]:
            bsdf.inputs["Emission Color"].default_value = lin
            bsdf.inputs["Emission Strength"].default_value = 3
        if key[4]:
            bsdf.inputs["Alpha"].default_value = 0.5
        me.materials.append(mat)
        total += len(b.faces)
    print(f"[render] {total} faces in {len(batches)} batches")

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.35, 0.42, 0.55, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.5
    scene.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    scene.collection.objects.link(sun)
    return scene


def shoot(scene, name, location, target, lens=35, ortho=None, clip_start=0.5):
    cam_data = bpy.data.cameras.new(name)
    cam_data.lens = lens
    cam_data.clip_start = clip_start
    cam_data.clip_end = 5000
    if ortho:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho
    cam = bpy.data.objects.new(name, cam_data)
    scene.collection.objects.link(cam)
    loc = to_blender(location)
    cam.location = loc
    direction = to_blender(target) - loc
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    os.makedirs(OUT, exist_ok=True)
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("[render] wrote", name)


def main():
    from_config = {
        "House": (-120, -300),
        "Truck": (170, -60),
        "Station": (505, 330),
        "Cemetery": (320, -255),
    }
    scene = build_scene()
    hx, hz = from_config["House"]
    shoot(scene, "overview", (-700, 520, 700), (40, 0, -40), lens=28)
    shoot(scene, "house", (hx - 70, 45, hz - 95), (hx, 14, hz), lens=32)
    tx, tz = from_config["Truck"]
    shoot(scene, "truck_clearing", (tx - 40, 30, tz - 45), (tx, 8, tz), lens=32)
    sx, sz = from_config["Station"]
    shoot(scene, "ranger_station", (sx - 70, 50, sz - 80), (sx, 10, sz), lens=30)
    cx, cz = from_config["Cemetery"]
    shoot(scene, "cemetery", (cx - 45, 25, cz - 50), (cx, 6, cz), lens=32)

    # cut-away of the house: drop the roof and upper floor, look straight down
    scene = build_scene()
    shoot(scene, "house_interior", (hx, 39, hz + 0.01), (hx, 0, hz), ortho=72, clip_start=12)


if __name__ == "__main__":
    main()
