"""Bakes the R6IK rig's InternalArmature into Roblox Motor6D.Transform keys. Runs inside Blender.

Loaded into the live session through the bridge (exec of this file defines the functions there).
The InternalArmature has one bone per Roblox part (HumanoidRootPart, Torso, Head, arms, legs) in
Blender space (Z up, +Y forward, +X right). Roblox space is +Y up, -Z forward, +X right, so
Roblox = Q * Blender with Q = [[1,0,0],[0,0,1],[0,-1,0]].
For each frame:  part = D * rest, D = bone pose * bone rest^-1 (moved into Roblox space),
and the Motor6D Transform is  T = C0^-1 * P0^-1 * P1 * C1  (world(P1) = P0 * C0 * T * C1^-1).
"""
import bpy, json, os
from mathutils import Matrix

ANIM_ROOT = globals().get("ANIM_ROOT") or os.path.dirname(os.path.abspath(__file__))
RIG = json.load(open(os.path.join(ANIM_ROOT, "rig.json")))
Q = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0))).to_4x4()
QI = Q.inverted()
REST_CENTRE = {
    "HumanoidRootPart": (0, 3, 0), "Torso": (0, 3, 0), "Head": (0, 4.5, 0),
    "Right Arm": (1.5, 3, 0), "Left Arm": (-1.5, 3, 0), "Right Leg": (0.5, 1, 0), "Left Leg": (-0.5, 1, 0),
}
JOINTS = RIG["joints"]


def cf(d):
    m = Matrix([list(r) for r in d["rows"]]).to_4x4()
    m.translation = d["pos"]
    return m


C0 = {j["name"]: cf(j["c0"]) for j in JOINTS}
C1 = {j["name"]: cf(j["c1"]) for j in JOINTS}


def show_blocky():
    """Only the blocky R6 body, like the game."""
    for o in bpy.data.objects:
        if o.type == "MESH" and not o.name.startswith("_"):
            on = o.name.endswith("_MBlocky")
            o.hide_set(not on)
            o.hide_render = not on


def part_cframes(fixed_root=True):
    internal = bpy.data.objects["InternalArmature"]
    out = {}
    for name, centre in REST_CENTRE.items():
        pb = internal.pose.bones[name]
        d_blender = internal.matrix_world @ pb.matrix @ pb.bone.matrix_local.inverted() @ internal.matrix_world.inverted()
        d = Q @ d_blender @ QI
        out[name] = d @ Matrix.Translation(centre)
    if fixed_root:
        # The game moves the HumanoidRootPart with physics: keep it at rest, so whatever the body does
        # relative to it ends up in the RootJoint.
        out["HumanoidRootPart"] = Matrix.Translation(REST_CENTRE["HumanoidRootPart"])
    return out


def transforms(fixed_root=True):
    parts = part_cframes(fixed_root)
    result = {}
    for j in JOINTS:
        p0, p1 = parts[j["part0"]], parts[j["part1"]]
        t = C0[j["name"]].inverted() @ p0.inverted() @ p1 @ C1[j["name"]]
        result[j["name"]] = t
    return result


def pack(m):
    r = m.to_3x3()
    p = m.translation
    return [round(v, 5) for v in (p.x, p.y, p.z, r[0][0], r[0][1], r[0][2], r[1][0], r[1][1], r[1][2], r[2][0], r[2][1], r[2][2])]


def bake_action(name, start, end, step=1, out_dir=None):
    """Bakes frames start..end of the current action into baked/<name>.json (every `step` frames)."""
    sc = bpy.context.scene
    fps = sc.render.fps / sc.render.fps_base
    keys = []
    for f in range(start, end + 1, step):
        sc.frame_set(f)
        keys.append({"t": round((f - start) / fps, 5), "pose": {k: pack(v) for k, v in transforms().items()}})
    if keys[-1]["t"] < (end - start) / fps - 1e-6:
        sc.frame_set(end)
        keys.append({"t": round((end - start) / fps, 5), "pose": {k: pack(v) for k, v in transforms().items()}})
    out_dir = out_dir or os.path.join(ANIM_ROOT, "baked")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, name + ".json")
    json.dump({"name": name, "fps": fps, "length": keys[-1]["t"], "keys": keys}, open(path, "w"))
    return path, len(keys)
