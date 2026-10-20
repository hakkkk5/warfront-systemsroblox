"""
Exports every procedural model as its own Roblox model file, so you can
bring it into Studio with right-click > Insert from File... (no Import 3D).

It reuses bake.py's bundle (the real game modules on the mock engine in
tools/bake/runtime.luau) with tools/bake/export_models.luau as the entry
script, and writes:

    build/models/rbxm/<Prop>.rbxm        one per Props builder (+ variants:
                                         ChairRopes, DeadTree2, Rock2, GraveCross)
    build/models/rbxm/AllProps.rbxm      every prop in a labelled grid
    build/models/rbxm/House.rbxm         the farmhouse on its own
    build/models/rbxm/Site_<Name>.rbxm   one per site folder in Sites.luau
    build/models/rbxm_src/               the .model.json + tiny Rojo project
                                         each .rbxm is built from

Props keep their builder pivot (bottom centre at the origin, front facing
-Z). The house and each site are moved so their ground point is at the
origin; Highway and Signs span the map and keep their world positions.
Every part is anchored. Each .rbxm is decoded again with Rojo and checked
against its .model.json. Usage:

    python tools/bake/export_models.py [--luau path/to/luau] [--rojo path/to/rojo]
"""

import argparse
import base64
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.dont_write_bytecode = True  # no __pycache__ in tools/bake
import bake  # noqa: E402

OUT =os.path.join(bake.ROOT, "build", "models")
SRC = os.path.join(OUT, "rbxm_src")
RBXM = os.path.join(OUT, "rbxm")
PART_CLASSES = {"Part", "WedgePart", "TrussPart", "MeshPart", "CornerWedgePart"}


def bundle():
    """bake.py's bundle, with export_models.luau in place of main.luau."""
    with open(os.path.join(HERE, "main.luau")) as f:
        main_chunk = "do\n" + f.read() + "\nend\n"
    source = bake.bundle()
    if not source.endswith(main_chunk):
        sys.exit("bake.bundle() no longer ends with main.luau; update export_models.py")
    with open(os.path.join(HERE, "export_models.luau")) as f:
        return source[: -len(main_chunk)] + "do\n" + f.read() + "\nend\n"


def run_entry(luau):
    script = os.path.join(OUT, "bundle.luau")
    with open(script, "w") as f:
        f.write(bundle())
    proc = subprocess.run([luau, script], capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout[-4000:])
        sys.stderr.write(proc.stderr[-4000:])
        sys.exit("export failed")

    files, metas = {}, []
    current = None
    for line in proc.stdout.splitlines():
        if line.startswith("<<<FILE "):
            current = line[len("<<<FILE ") : -3]
            files[current] = []
        elif line == "<<<END>>>":
            current = None
        elif line.startswith("<<<META "):
            metas.append(json.loads(line[len("<<<META ") : -3]))
        elif line.startswith("<<<LOG "):
            print("[export]", line[len("<<<LOG ") : -3])
        elif current:
            files[current].append(line)
    return {name: "\n".join(lines) for name, lines in files.items()}, metas


def walk(node, name):
    """(class, name, properties) of every instance in a .model.json tree, in order."""
    yield node["ClassName"], node.get("Name", name), node.get("Properties", {})
    for child in node.get("Children", []):
        yield from walk(child, None)


def decode_attributes(blob):
    """Roblox's AttributesSerialize format, for the String/Bool/Float64 values we write."""
    out, i = {}, 4
    for _ in range(struct.unpack_from("<I", blob)[0] if blob else 0):
        (n,) = struct.unpack_from("<I", blob, i)
        key, kind, i = blob[i + 4 : i + 4 + n].decode(), blob[i + 4 + n], i + 5 + n
        if kind == 0x02:
            (n,) = struct.unpack_from("<I", blob, i)
            out[key], i = blob[i + 4 : i + 4 + n].decode(), i + 4 + n
        elif kind == 0x03:
            out[key], i = blob[i] != 0, i + 1
        elif kind == 0x06:
            out[key], i = struct.unpack_from("<d", blob, i)[0], i + 8
        else:
            raise ValueError(f"attribute {key} has type {kind:#x}")
    return out


def rojo_build(rojo, project, output):
    proc = subprocess.run([rojo, "build", project, "-o", output], capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout + proc.stderr)
        sys.exit(f"rojo build {os.path.basename(project)} failed")


def verify(rojo, file, name, tree, rbxm, tmp):
    """Instance count of `rbxm` and its differences from the .model.json `tree`."""
    expected = list(walk(tree, name))
    with open(rbxm, "rb") as f:
        data = f.read()
    if data[:8] != b"<roblox!":
        return len(expected), ["not a binary Roblox model"]
    problems = []
    header_classes, header_instances = struct.unpack_from("<ii", data, 16)
    classes = len({cls for cls, _, _ in expected})
    if (header_instances, header_classes) != (len(expected), classes):
        problems.append(f"header has {header_instances} instances / {header_classes} classes, "
                        f"model.json has {len(expected)} / {classes}")

    # decode it again (rbx_binary, as Studio does) and compare instance by instance
    shutil.copy(rbxm, os.path.join(tmp, file + ".rbxm"))
    project = os.path.join(tmp, file + ".project.json")
    with open(project, "w") as f:
        json.dump({"name": name, "tree": {"$path": file + ".rbxm"}}, f)
    rojo_build(rojo, project, os.path.join(tmp, file + ".rbxmx"))
    items = list(ET.parse(os.path.join(tmp, file + ".rbxmx")).getroot().iter("Item"))
    if len(items) != len(expected):
        problems.append(f"decodes to {len(items)} instances, model.json has {len(expected)}")

    def prop(item, tag, prop_name):
        node = item.find(f"Properties/{tag}[@name='{prop_name}']")
        return None if node is None else (node.text or "")

    for item, (cls, inst_name, props) in zip(items, expected):
        label = f"{cls} {inst_name}"
        if item.get("class") != cls or prop(item, "string", "Name") != inst_name:
            problems.append(f"{label} decodes as {item.get('class')} {prop(item, 'string', 'Name')}")
            break
        if cls in PART_CLASSES and (props.get("Anchored") is not True or prop(item, "bool", "Anchored") != "true"):
            problems.append(f"{label} is not anchored")
        if cls == "Model" and prop(item, "OptionalCoordinateFrame", "WorldPivotData") is None:
            problems.append(f"{label} has no WorldPivot")
        tags = base64.b64decode(prop(item, "BinaryString", "Tags") or "")
        if sorted(t.decode() for t in tags.split(b"\0") if t) != sorted(props.get("Tags", [])):
            problems.append(f"{label} tags differ")
        attrs = {k: next(iter(v.values())) for k, v in props.get("Attributes", {}).get("Attributes", {}).items()}
        if decode_attributes(base64.b64decode(prop(item, "BinaryString", "AttributesSerialize") or "")) != attrs:
            problems.append(f"{label} attributes differ")
    return len(expected), problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--luau")
    parser.add_argument("--rojo")
    args = parser.parse_args()
    luau = bake.find_tool(args.luau, "luau")
    rojo = bake.find_tool(args.rojo, "rojo")

    for folder in (SRC, RBXM):
        shutil.rmtree(folder, ignore_errors=True)
        os.makedirs(folder)
    files, metas = run_entry(luau)

    rows, failures = [], []
    with tempfile.TemporaryDirectory() as tmp:
        for meta in metas:
            name = meta["file"]
            data = files[name]
            tree = json.loads(data)  # validate
            with open(os.path.join(SRC, name + ".model.json"), "w") as f:
                f.write(data)
            project = os.path.join(SRC, name + ".project.json")
            with open(project, "w") as f:
                json.dump({"name": meta["name"], "tree": {"$path": name + ".model.json"}}, f)
            rbxm = os.path.join(RBXM, name + ".rbxm")
            rojo_build(rojo, project, rbxm)

            instances, problems = verify(rojo, name, meta["name"], tree, rbxm, tmp)
            if problems:
                failures.append((name, problems))
            rows.append((name, meta, instances, os.path.getsize(rbxm)))

    print()
    print(f"{'file':<24} {'kind':<6} {'seed':>4} {'parts':>6} {'insts':>6}  {'extents (studs)':<22} {'rbxm':>9}")
    for name, meta, instances, size in rows:
        sx, sy, sz = meta["size"]
        seed = "" if meta["seed"] is None else str(meta["seed"])
        extents = f"{sx:.1f} x {sy:.1f} x {sz:.1f}"
        print(f"{name + '.rbxm':<24} {meta['kind']:<6} {seed:>4} {meta['parts']:>6} {instances:>6}  "
              f"{extents:<22} {size / 1024:>6.1f} KB")
    total = sum(r[3] for r in rows)
    print(f"\n{len(rows)} models, {total / 1024:.0f} KB, in {os.path.relpath(RBXM, bake.ROOT)}")
    for name, problems in failures:
        print(f"[export] {name}: " + "; ".join(problems))
    if failures:
        sys.exit(f"{len(failures)} models failed verification")
    print("[export] every .rbxm decodes to the same instances as its .model.json")


if __name__ == "__main__":
    main()
