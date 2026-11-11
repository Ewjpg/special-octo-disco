"""Blender side of the stadium: build the meshes with PBR materials, render previews, export a GLB.

    blender --background --python-exit-code 1 --python tools/stadium/build_blender.py -- \
        <textures dir> <out dir> [--no-render] [--no-glb]

Writes <out>/Stadium.glb (for Studio's File > Import 3D, units: studs) and <out>/preview_*.png.
Geometry comes from geometry.py in Roblox space (Y up) and is converted to Blender (Z up):
    Roblox (x, y, z) -> Blender (x, -z, y)
UVs: geometry.py uses v = 0 at the top of the image; Blender uses v = 0 at the bottom.
The pitch, lines and goals in the renders are context only and are not exported.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import geometry  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
TEX = Path(argv[0]).resolve()
OUT = Path(argv[1]).resolve()
RENDER = "--no-render" not in argv
GLB = "--no-glb" not in argv
OUT.mkdir(parents=True, exist_ok=True)


def to_blender(p):
    return (p[..., 0], -p[..., 2], p[..., 1])


# ---------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------

def image(path: Path, data: bool):
    img = bpy.data.images.load(str(path), check_existing=True)
    img.colorspace_settings.name = "Non-Color" if data else "sRGB"
    return img


def pbr_material(name: str):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    col = nodes.new("ShaderNodeTexImage")
    col.image = image(TEX / f"{name}_color.png", False)
    links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    rough = nodes.new("ShaderNodeTexImage")
    rough.image = image(TEX / f"{name}_roughness.png", True)
    links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    metal = nodes.new("ShaderNodeTexImage")
    metal.image = image(TEX / f"{name}_metalness.png", True)
    links.new(metal.outputs["Color"], bsdf.inputs["Metallic"])
    nrm = nodes.new("ShaderNodeTexImage")
    nrm.image = image(TEX / f"{name}_normal.png", True)
    nmap = nodes.new("ShaderNodeNormalMap")
    links.new(nrm.outputs["Color"], nmap.inputs["Color"])
    links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def flat_material(name: str, rgb, emission: float = 0.0, roughness: float = 0.8):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    color = (rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1.0)
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = roughness
    if emission > 0:
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = emission
    return mat


# ---------------------------------------------------------------------------
# scene
# ---------------------------------------------------------------------------

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

materials = {
    "concrete": pbr_material("concrete"),
    "crowd": pbr_material("crowd"),
    "metal": pbr_material("metal"),
    "roof": pbr_material("roof"),
    # Emissive "neon_*" materials. Roblox Import 3D does not turn emission into Neon by itself:
    # the game does it at runtime for every part whose name starts with neon_<colour>.
    "ads": pbr_material("ads"),
    "dark": pbr_material("dark"),
    "neon_white": flat_material("neon_white", (235, 240, 255), emission=2.0),
}

stadium = bpy.data.collections.new("Stadium")
scene.collection.children.link(stadium)
context = bpy.data.collections.new("Context")
scene.collection.children.link(context)

chunks, info = geometry.build()
# One empty per bowl sector: in Roblox each becomes a Model (Sector_0..7) of dockable pieces.
sector_roots = {}
for s_index in range(geometry.SECTORS):
    e = bpy.data.objects.new(f"Sector_{s_index}", None)
    stadium.objects.link(e)
    sector_roots[s_index] = e
for c in chunks:
    tris = c["tris"]
    uvs = c["uvs"]
    t = len(tris)
    bx, by, bz = to_blender(tris.reshape(-1, 3))
    verts = np.stack([bx, by, bz], axis=1)
    faces = np.arange(t * 3).reshape(t, 3)
    me = bpy.data.meshes.new(c["name"])
    me.from_pydata(verts.tolist(), [], faces.tolist())
    layer = me.uv_layers.new(name="UVMap")
    uv = uvs.reshape(-1, 2).copy()
    uv[:, 1] = 1.0 - uv[:, 1]
    layer.data.foreach_set("uv", uv.ravel())
    me.materials.append(materials[c["material"]])
    me.update()
    obj = bpy.data.objects.new(c["name"], me)
    stadium.objects.link(obj)
    obj.parent = sector_roots[int(c["name"].rsplit("_", 1)[1])]

print(f"[stadium] {len(chunks)} objects, {sum(len(c['tris']) for c in chunks)} triangles")

# --- context only: pitch stripes, lines, goals, boards ---------------------------
HL, HW = geometry.HL, geometry.HW
ARENA_X, ARENA_Z = geometry.ARENA_X, geometry.ARENA_Z
PD, PW = geometry.FIELD["PenaltyDepth"], geometry.FIELD["PenaltyWidth"]
GW, GH = geometry.FIELD["GoalWidth"], geometry.FIELD["GoalHeight"]


def box(name, size_r, center_r, mat):
    """A box given in Roblox axes (size and centre)."""
    sx, sy, sz = size_r
    cx, cy, cz = center_r
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, -cz, cy))
    o = bpy.context.active_object
    o.name = name
    o.scale = (sx, sz, sy)
    for col in o.users_collection:
        col.objects.unlink(o)
    context.objects.link(o)
    o.data.materials.append(mat)
    return o


grass_a = flat_material("grass_a", (70, 132, 58), roughness=0.95)
grass_b = flat_material("grass_b", (58, 114, 48), roughness=0.95)
apron = flat_material("apron", (52, 98, 44), roughness=0.95)
white = flat_material("line", (240, 242, 246), roughness=0.6)
goal_neon = flat_material("goal_frame", (240, 242, 246), roughness=0.4)
figure = flat_material("figure", (60, 64, 76), roughness=0.7)
board_home = flat_material("board_home", (52, 120, 255), emission=0.8)
board_away = flat_material("board_away", (240, 62, 72), emission=0.8)

stripes = 19
w = 2 * HL / stripes
for i in range(stripes):
    box(f"grass{i}", (w, 1, 2 * HW), (-HL + w * (i + 0.5), -0.5, 0), grass_a if i % 2 == 0 else grass_b)
box("apron", (2 * ARENA_X, 0.9, 2 * ARENA_Z), (0, -0.55, 0), apron)
for (sx, sz, cx, cz) in [(2 * HL, 1, 0, -HW), (2 * HL, 1, 0, HW), (1, 2 * HW, -HL, 0), (1, 2 * HW, HL, 0), (1, 2 * HW, 0, 0)]:
    box("line", (sx, 0.1, sz), (cx, 0.03, cz), white)
for s in (-1, 1):
    gx = s * HL
    for (sx, sz, cx, cz) in [(PD, 1, gx - s * PD / 2, -PW / 2), (PD, 1, gx - s * PD / 2, PW / 2), (1, PW, gx - s * PD, 0)]:
        box("line", (sx, 0.1, sz), (cx, 0.03, cz), white)
    for z in (-GW / 2, GW / 2):
        box("post", (1.8, GH, 1.8), (gx, GH / 2, z), goal_neon)
    box("bar", (1.8, 1.8, GW + 2), (gx, GH, 0), goal_neon)
    # Player figures for scale (R6 proportions at Config.Player.Scale = 0.75: 3.75 studs tall).
    for k, fz in enumerate((-12, 0, 9)):
        fx = gx - s * (8 + 6 * k)
        box("figure_legs", (2, 2, 1), (fx, 1, fz), figure)
        box("figure_torso", (2, 2, 1), (fx, 3, fz), figure)
        box("figure_head", (1.2, 1, 1.2), (fx, 4.5, fz), figure)
for zs in (-1, 1):
    box("board", (ARENA_X, 4.5, 2), (-ARENA_X / 2, 2.25, zs * (ARENA_Z + 1)), board_home)
    box("board", (ARENA_X, 4.5, 2), (ARENA_X / 2, 2.25, zs * (ARENA_Z + 1)), board_away)
for s, mat in ((-1, board_home), (1, board_away)):
    box("board", (2, 4.5, 2 * ARENA_Z), (s * (ARENA_X + 1), 2.25, 0), mat)

# --- light and world ----------------------------------------------------------------
sun_data = bpy.data.lights.new("Sun", type="SUN")
sun_data.energy = 3.4
sun_data.angle = math.radians(2.0)
sun_data.color = (1.0, 0.97, 0.92)
sun = bpy.data.objects.new("Sun", sun_data)
sun.rotation_euler = (math.radians(38), math.radians(8), math.radians(-35))
scene.collection.objects.link(sun)

world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
bg.inputs["Color"].default_value = (0.45, 0.58, 0.78, 1.0)  # daytime sky
bg.inputs["Strength"].default_value = 0.9

# ---------------------------------------------------------------------------
# renders
# ---------------------------------------------------------------------------

def camera(name, pos_r, target_r, lens):
    cam_data = bpy.data.cameras.new(name)
    cam_data.lens = lens
    cam_data.clip_end = 4000
    cam = bpy.data.objects.new(name, cam_data)
    p = Vector((pos_r[0], -pos_r[2], pos_r[1]))
    t = Vector((target_r[0], -target_r[2], target_r[1]))
    cam.location = p
    cam.rotation_euler = (t - p).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam)
    return cam


if RENDER:
    try:
        scene.render.engine = "BLENDER_EEVEE"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.image_settings.file_format = "PNG"
    try:
        scene.eevee.taa_render_samples = 48
    except AttributeError:
        pass
    # Standard keeps saturated neon colours (AgX bleaches bright emission towards white).
    scene.view_settings.view_transform = "Standard"

    views = [
        ("preview_broadcast", (0, 80, ARENA_Z + 120), (0, 10, -HW * 0.3), 22),
        ("preview_aerial", (geometry.A0 * 2.2, 560, geometry.B0 * 2.6), (0, 20, 0), 28),
        ("preview_pitch", (-HL * 0.8, 5, 0), (HL * 0.75, 40, -HW * 0.5), 18),
        ("preview_goal", (-HL * 0.6, 12, -HW * 0.5), (-HL - 10, 30, HW * 0.3), 20),
    ]
    for name, pos, target, lens in views:
        scene.camera = camera(name, pos, target, lens)
        scene.render.filepath = str(OUT / f"{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[stadium] rendered {name}.png")

# ---------------------------------------------------------------------------
# GLB for Studio (stadium only)
# ---------------------------------------------------------------------------

if GLB:
    bpy.ops.object.select_all(action="DESELECT")
    for o in stadium.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = sector_roots[0]
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / "Stadium.glb"),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
    )
    print(f"[stadium] exported Stadium.glb")
