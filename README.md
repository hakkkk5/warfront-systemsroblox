# Butcher's Hollow

A first-person survival horror game for Roblox. Your car crashes on a forest road at night. You wake up tied to a chair in a cannibal family's farmhouse and watch them butcher the last traveller. Then you cut yourself free, escape the house, rebuild a broken-down truck in the woods, steal the keys off the Butcher's belt, and run for the ranger station when the engine blows.

![Blender props](assets/blender/contact_sheet.png)

## The story

| Chapter | What happens |
| --- | --- |
| **Prologue: Hollow Road** | Cutscene: night drive in the rain, a figure in the headlights, the crash, being dragged to the house. |
| **I: The Butcher's House** | Cutscene: you wake tied up while the Butcher and Brother Abel carve up a body, then saw through the ropes with the knife beside you. Find a flashlight, find the padlock key upstairs, and escape through the chained front door while they patrol both floors. |
| **II: The Woods** | Find the abandoned pickup. Its parts are scattered through the forest: the **engine** in the old barn, the **battery** at the hunter's camp, the **spark plugs** in the doctor's trailer, the **spare wheel** in the cemetery. Find **sedative syringes**, sneak up behind the Butcher, inject him and take the **truck keys**. Install everything at the truck. |
| **III: Last Ride** | Interactive drive (hold W). The engine overheats and **explodes**. |
| **IV: The Ranger Station** | Papa and his chainsaw are right behind you. Get the fuse from the fire lookout and fuel from the tool shed, restore power, and use the radio. |
| **V: Rescue** | Survive two minutes while the family closes in, then reach the helicopter. |

## Features

- **First person:** head bob, strafe tilt, sprint FOV, crouching, stamina, hands holding a shadow-casting flashlight whose battery drains, and the equipped item shown in your other hand.
- **Cannibal AI:**
  - Sees you within a vision cone (more easily with your flashlight on, less when crouched) and hears you running.
  - Investigates noises, chases, searches and opens doors.
  - Attacks with cleavers or a chainsaw, and drags you out of a hiding spot if it saw you go in.
  - A syringe from behind knocks one out for 80 seconds.
- **Hiding spots:** wardrobes, closets, pantry, lockers.
- **Inventory (TAB):** rotating 3D previews, use and equip, plus a **journal** of 8 lore notes.
- **Detection eye, objectives, hints (H), checkpoints, jumpscare death screen, chapter title cards, credits.**
- **Procedural world:**
  - 1440×1440-stud terrain with roads, a lake and a mountain rim.
  - A two-floor walkable farmhouse with eight furnished rooms.
  - A barn, camp, trailer, cemetery, ranger station, fire lookout and helipad.
  - About 1,000 trees and the undergrowth.
- **Atmosphere:** Future lighting, fog, colour grading, rain, lightning, flickering bulbs and candles, hazard lights, heartbeat, and music that changes with each chapter and during chases.

## Getting it into Roblox Studio

The quickest way in: open the prebuilt place file `ButchersHollow.rbxl` in Studio. The whole world is already in it:
- the house, every site, the forest, the items and the family, standing where they start;
- a part-built preview of the terrain.

Press **Play** and the game generates real smooth terrain and wires up every door, prompt and cannibal.

**Real terrain in edit mode.** To get real terrain (and the ForgeGUI meshes) while editing, run this once in **View → Command Bar**, then save:

```lua
require(game.ServerScriptService.Server.Bake)()
```

A local Claude session connected to the Roblox Studio MCP can run the same line with `run_code`.

**Building the place file yourself:**
1. Install [Rojo](https://rojo.space) 7.4+, and the standalone [Luau](https://github.com/luau-lang/luau/releases) interpreter for the bake.
2. Bake the world, then build:
   ```sh
   python tools/bake/bake.py                      # runs the world builders offline
   rojo build build/bake/ButchersHollow.project.json -o ButchersHollow.rbxl
   ```
   `rojo build default.project.json` also works, but the place then stays empty until you press Play. For live sync, use `rojo serve` with the Rojo Studio plugin.
3. Optional: `python tools/bake/render_preview.py` (needs `pip install bpy`) renders the baked world to `assets/screenshots/` so you can check it without Studio.
**Before publishing:**

1. **Publish the place from the Roblox account `@hakaaannnnnnnn` (user 1864017860).** The ForgeGUI meshes are owned by that account, and `InsertService:LoadAsset` only loads models the experience owner owns. If you publish elsewhere, the game still works, but those props fall back to their part-built versions.
2. Make sure the place holds **ReplicatedStorage.MeshAssets** (the imported Blender models, see "Blender models" below). It lives in the place file, not in the Rojo project, so a fresh `rojo build` or bake doesn't have it; without it the part-built versions are shown instead.
3. Recommended: set **Max Players** to 1 for the intended experience. Co-op for 2–4 players works: objectives are shared and cutscenes play for everyone.
4. Optional: in Studio, select Terrain and enable **Decoration** for animated grass.

## Assets

### ForgeGUI models (published to Roblox)

| Prop | Asset id | | Prop | Asset id |
| --- | --- | --- | --- | --- |
| Crashed sedan | 73193234568840 | | Syringe | 79237926120495 |
| Pickup truck | 116288644494114 | | Car keys | 98412590570036 |
| Engine block | 124503135770719 | | Hunting knife | 84693353445664 |
| Car battery | 115821756774757 | | Butcher table | 104341500262978 |
| Spark plugs | 106943413747423 | | Meat hooks | 102976782218646 |
| Spare wheel | 132952222251049 | | Pine / oak tree | 95887089293746 / 111118553837182 |

The ids, target sizes and an optional `yaw` correction live in `src/shared/Assets.luau`. If a mesh comes in facing the wrong way, change its `yaw`.

### Blender models

Everything below is modelled in Blender with Python, with wear, rust, blood and moss painted into vertex colours. Each model gets a GLB (`assets/blender/glb/`) and a preview render (`assets/blender/previews/`).

- `tools/blender/build_props.py`: the props and furniture (lantern, cleaver, chainsaw, sack mask, generator, sofa, beds, stove, ...).
- `tools/blender/build_buildings.py`: building exteriors modelled at their exact size around each building's origin (the farmhouse, ranger station, barn, tool shed, trailer, lookout tower roof and the lobby gas station).
- `tools/blender/build_interiors.py`: the farmhouse rooms (wallpaper, wainscot, tiles, stair runner, blood).
- `tools/blender/build_monsters.py`: the six cannibals' bodies, one mesh per R6 part, near-human and monster.

The game uses them as **uploaded mesh assets** (a client may only build a handful of meshes at runtime):

1. `tools/blender/export_combined.py` packs models into one `.glb` (`BH_OUT` names it, `-- Name ...` picks models).
2. In Studio, **Import 3D** that file.
3. Run `tools/roblox/harvest_meshes.luau` in the command bar. It files the parts under `ReplicatedStorage.MeshAssets.<Name>` and undoes the importer's turn and scale.
4. Save the place.

`src/client/Controllers/MeshLibrary.luau` swaps the meshes in for the server's part-built stand-ins (tag `BlenderMesh`, attribute `Mesh`); `CannibalSkins` dresses the cannibals. Anything not imported keeps its part-built look.

To regenerate (Blender 4.2+ or `pip install bpy`):

```sh
blender -b --factory-startup -P tools/blender/build_props.py            # everything
blender -b --factory-startup -P tools/blender/build_props.py -- Lantern # one prop
BH_RENDER=0 blender -b --factory-startup -P tools/blender/build_monsters.py  # skip preview renders
```

The terrain is baked into the place (`workspace.TerrainBaked`) so a match starts in a few seconds; regenerate it by running `Terrain.generate()` in Studio and saving.

**Optional:** you can import any GLB with **File → Import 3D** and drop the result into `ServerStorage.CustomModels` under the same name, such as `Generator`. `AssetService` then uses your imported model instead of the generated one.

### Sound

Music comes from licensed APM and DistroKid tracks in the Creator Store. Sound effects are slots in `Assets.Sounds`, and empty slots are skipped silently. Good ForgeGUI `generation_sound_effect` prompts for the empty ones:

| Slot | Prompt |
| --- | --- |
| Heartbeat (loop) | slow heavy human heartbeat |
| Crash | violent car crash, tyres screeching, metal impact, glass shattering |
| Chop | meat cleaver chopping into meat on a wooden table |
| DoorOpen / DoorLocked / Unlock | old wooden door creaking open / rattling a locked door / heavy padlock unlocking, chain falling |
| RopeCut | knife sawing through thick rope |
| Inject | syringe injection, man groaning and collapsing |
| Growl / Scream / Jumpscare | deranged man growling / monster scream / horror jumpscare sting |
| EngineStart / EngineLoop / EngineFail / Explosion | old truck starting / engine idle loop / engine sputtering and dying / car engine explosion with debris |
| Thunder / Wind | loud thunder crack / wind through pine trees at night |
| Chainsaw / Generator / Radio / HelicopterLoop | chainsaw revving / diesel generator running / radio static with distorted voices / helicopter blades loop |
| FlashlightClick / Repair / PageTurn | flashlight switch click / wrench clanking on metal / turning a paper page |

## Controls

| Key | Action |
| --- | --- |
| WASD / mouse | Move / look |
| Shift | Run (uses stamina) |
| C or Ctrl | Crouch |
| E (hold for some actions) | Interact |
| F | Flashlight |
| TAB or I | Inventory and journal |
| H | Hint (25 s cooldown) |

Touch and gamepad bindings are included.

## Project layout

```
default.project.json        Rojo project (also sets lighting, first-person camera, spawning)
src/shared/                 Config, Assets, Items, Lore, Net, Util, Signal, Meshes/ (Blender model
                            names), MeshCatalog (their materials)
src/server/Main.server.luau builds the world, then starts the story
src/server/World/           Terrain, House, Sites, Forest, Props, Lighting, Build helpers
src/server/Systems/         Story, Cannibals, Inventory, Interact, Doors, Hiding, Pickups,
                            AssetService, PlayerService
src/client/Main.client.luau client bootstrap
src/client/Controllers/     Camera, Movement, Viewmodel (flashlight), Effects, Audio,
                            Cutscenes, HidingView, MeshLibrary, CannibalSkins, MonsterForm,
                            Scares, Jumpscare, ChaseFX, Settings
src/client/UI/              Menu, HUD, Prompts, Inventory, Notes, Death, Ending, Theme
tools/blender/              Blender builders (props, buildings, interiors, monsters) and
                            export_combined.py
tools/roblox/               harvest_meshes.luau (files an Import 3D into MeshAssets)
```

Gameplay tuning (speeds, stamina, detection, sedation time, survive timer, map layout) is in `src/shared/Config.luau`.
