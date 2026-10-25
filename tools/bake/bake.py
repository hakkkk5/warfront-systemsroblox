"""
Bakes the procedurally built world into Rojo model files so the place opens
in Roblox Studio with everything already in it (instead of an empty
Workspace until you press Play).

It bundles the real game modules from src/ with a small mock of the Roblox
engine (tools/bake/runtime.luau), runs them in the standalone Luau
interpreter, and writes:

    build/bake/World.model.json          house, sites, forest, items, props
    build/bake/Cannibals.model.json      the family, posed where they start
    build/bake/TerrainPreview.model.json part-based preview of the terrain
    build/bake/ButchersHollow.project.json

The game rebuilds the world when it starts (the generation is deterministic,
so it looks the same) and replaces the terrain preview with real smooth
terrain. Usage:

    python tools/bake/bake.py [--luau path/to/luau] [--rojo path/to/rojo]
    rojo build build/bake/ButchersHollow.project.json -o ButchersHollow.rbxl
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "build", "bake")


def module_path(rel):
    """Map a source file to its DataModel path (mirrors default.project.json)."""
    parts = rel.replace("\\", "/").split("/")
    if parts[0] == "shared":
        base = ["ReplicatedStorage", "Shared"]
    elif parts[0] == "server":
        base = ["ServerScriptService", "Server"]
    else:
        return None
    rest = parts[1:]
    name = rest[-1]
    if name.endswith(".server.luau") or name.endswith(".client.luau"):
        return None
    stem = name[: -len(".luau")]
    if stem == "init":
        return "/".join(base + rest[:-1])
    return "/".join(base + rest[:-1] + [stem])


def bundle():
    chunks = []
    with open(os.path.join(ROOT, "tools", "bake", "runtime.luau")) as f:
        runtime = f.read()
    chunks.append("local BAKE_RUNTIME = (function()\n" + runtime + "\nend)()\n")
    chunks.append(
        "local function io_stderr(msg) print('<<<LOG ' .. msg .. '>>>') end\n"
    )
    for folder in ("shared", "server"):
        for dirpath, _, files in os.walk(os.path.join(ROOT, "src", folder)):
            for name in sorted(files):
                if not name.endswith(".luau"):
                    continue
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, os.path.join(ROOT, "src"))
                path = module_path(rel)
                if not path:
                    continue
                with open(full) as f:
                    src = f.read()
                src = re.sub(r"^export type", "type", src, flags=re.M)
                chunks.append(
                    f'BAKE_RUNTIME.module("{path}", "ModuleScript", function(script)\n{src}\nend)\n'
                )
    with open(os.path.join(ROOT, "tools", "bake", "main.luau")) as f:
        chunks.append("do\n" + f.read() + "\nend\n")
    return "".join(chunks)


def find_tool(explicit, name):
    if explicit:
        return explicit
    found = shutil.which(name)
    if not found:
        sys.exit(f"{name} not found on PATH; pass --{name} /path/to/{name}")
    return found


def write_project():
    with open(os.path.join(ROOT, "default.project.json")) as f:
        project = json.load(f)

    def rebase(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k == "$path":
                    node[k] = os.path.relpath(os.path.join(ROOT, v), OUT).replace("\\", "/")
                else:
                    rebase(v)

    rebase(project["tree"])
    workspace = project["tree"].setdefault("Workspace", {})
    for name in ("World", "Cannibals", "TerrainPreview"):
        workspace[name] = {"$path": f"{name}.model.json"}
    with open(os.path.join(OUT, "ButchersHollow.project.json"), "w") as f:
        json.dump(project, f, indent=2)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--luau")
    parser.add_argument("--rojo")
    parser.add_argument("--output", help="also build the place file to this path")
    args = parser.parse_args()
    luau = find_tool(args.luau, "luau")

    os.makedirs(OUT, exist_ok=True)
    script = os.path.join(OUT, "bundle.luau")
    with open(script, "w") as f:
        f.write(bundle())
    proc = subprocess.run([luau, script], capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout[-4000:])
        sys.stderr.write(proc.stderr[-4000:])
        sys.exit("bake failed")

    current = None
    buffers = {}
    for line in proc.stdout.splitlines():
        if line.startswith("<<<FILE "):
            current = line[len("<<<FILE ") : -3]
            buffers[current] = []
        elif line == "<<<END>>>":
            current = None
        elif line.startswith("<<<LOG "):
            print("[bake]", line[len("<<<LOG ") : -3])
        elif current:
            buffers[current].append(line)
    for name, lines in buffers.items():
        data = "\n".join(lines)
        json.loads(data)  # validate
        with open(os.path.join(OUT, f"{name}.model.json"), "w") as f:
            f.write(data)
        print(f"[bake] {name}.model.json  {len(data) / 1e6:.1f} MB")
    write_project()
    print("[bake] wrote", os.path.relpath(os.path.join(OUT, "ButchersHollow.project.json"), ROOT))

    if args.output:
        rojo = find_tool(args.rojo, "rojo")
        subprocess.run([rojo, "build", os.path.join(OUT, "ButchersHollow.project.json"), "-o", args.output], check=True)


if __name__ == "__main__":
    main()
