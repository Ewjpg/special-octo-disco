"""Posing helpers for the R6IK rig in the live Blender session (exec'd after rbx_bake.py).

World axes of the rig (= character axes): +X right, +Y forward, +Z up, units = Roblox studs.
ctrl(name, loc=(dx, dy, dz), rot=(rx, ry, rz)) puts a control bone at its REST world position plus
loc, rotated by world-axis Euler degrees about its own head:
  rx < 0 tips the top of the bone FORWARD (bow), ry > 0 tips it to the RIGHT, rz > 0 turns it LEFT.
key(frame, {ctrl: {...}}) poses the listed controls and keys them (location + rotation) at frame;
controls left out of a key keep their curve, so a key only needs what moves.
"""
import bpy, math
from mathutils import Matrix, Euler

ARM = bpy.data.objects["__PrimaryArmature"]
CONTROLS = ["MasterControl", "LowerTorso-FK", "Torso_FK", "UpperTorso-IKTarget", "Torso-Pole", "LookToPoint",
            "LeftLeg-IK", "RightLeg-IK", "LeftLeg-Pole", "RightLeg-Pole",
            "LeftArm_GrabPoint", "RightArm_GrabPoint", "LeftArm-Pole", "RightArm-Pole"]


def reset_pose():
    for pb in ARM.pose.bones:
        pb.location = (0, 0, 0)
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.scale = (1, 1, 1)
    bpy.context.view_layer.update()


def _rest_world():
    saved_action = ARM.animation_data.action if ARM.animation_data else None
    if ARM.animation_data:
        ARM.animation_data.action = None
    reset_pose()
    rest = {n: (ARM.matrix_world @ ARM.pose.bones[n].matrix).copy() for n in CONTROLS}
    if ARM.animation_data:
        ARM.animation_data.action = saved_action
    return rest


REST_WORLD = _rest_world()


def ctrl(name, loc=(0, 0, 0), rot=(0, 0, 0)):
    rest = REST_WORLD[name]
    head = rest.translation
    r = Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    world = Matrix.Translation(head + __import__("mathutils").Vector(loc)) @ r @ rest.to_3x3().to_4x4()
    pb = ARM.pose.bones[name]
    # Offsets are relative to the parent control (MasterControl): when the whole body turns or dives,
    # the pelvis and feet go with it instead of staying where they were in the world.
    parent = pb.parent
    if parent is not None and parent.name in REST_WORLD:
        moved = (ARM.matrix_world @ parent.matrix) @ REST_WORLD[parent.name].inverted()
        world = moved @ world
    pb.matrix = ARM.matrix_world.inverted() @ world
    bpy.context.view_layer.update()
    return pb


def new_action(name, length_frames):
    sc = bpy.context.scene
    act = bpy.data.actions.get(name) or bpy.data.actions.new(name)
    act.use_fake_user = True
    if not ARM.animation_data:
        ARM.animation_data_create()
    ARM.animation_data.action = act
    # Blender 4.4+ layered actions need a slot for the armature
    if hasattr(ARM.animation_data, "action_slot") and ARM.animation_data.action_slot is None and hasattr(act, "slots"):
        slot = act.slots[0] if len(act.slots) else act.slots.new(id_type="OBJECT", name=ARM.name)
        ARM.animation_data.action_slot = slot
    sc.frame_start, sc.frame_end = 0, length_frames
    return act


# FK bones: rotation only, in the bone's REST axes = character axes (rx/ry/rz as above):
#   arms hang down: rx > 0 swings the arm FORWARD, ry < 0 swings the RIGHT arm out, ry > 0 the LEFT arm out
#   head: rx < 0 nods down, rz > 0 turns left, ry > 0 tilts right
FK = {"RightUpperArm", "LeftUpperArm", "RightShoulder", "LeftShoulder", "Head"}
_last_q = {}


def fk(name, rot=(0, 0, 0)):
    pb = ARM.pose.bones[name]
    b = pb.bone.matrix_local.to_3x3()
    w = Euler([math.radians(a) for a in rot], "XYZ").to_matrix()
    pb.rotation_quaternion = (b.inverted() @ w @ b).to_quaternion()
    bpy.context.view_layer.update()
    return pb


def _keep_continuous(pb):
    # quaternions q and -q are the same rotation; keep each key on the side of the previous one so the
    # curve never takes the long way round
    q = pb.rotation_quaternion.copy()
    prev = _last_q.get(pb.name)
    if prev is not None and prev.dot(q) < 0:
        q.negate()
        pb.rotation_quaternion = q
    _last_q[pb.name] = q.copy()


def key(frame, poses):
    """poses: {bone: {"loc": (..), "rot": (..)}}. FK bones take rot only."""
    bpy.context.scene.frame_set(frame)
    for name, p in poses.items():
        if name in FK:
            pb = fk(name, p.get("rot", (0, 0, 0)))
        else:
            pb = ctrl(name, p.get("loc", (0, 0, 0)), p.get("rot", (0, 0, 0)))
            pb.keyframe_insert("location", frame=frame, group=name)
        _keep_continuous(pb)
        pb.keyframe_insert("rotation_quaternion", frame=frame, group=name)


def mirror_pose(poses):
    """Left <-> right: swap sides, negate x offsets and the ry/rz rotations."""
    out = {}
    for name, p in poses.items():
        other = name.replace("Right", "#").replace("Left", "Right").replace("#", "Left")
        q = {}
        if "loc" in p:
            q["loc"] = (-p["loc"][0], p["loc"][1], p["loc"][2])
        if "rot" in p:
            q["rot"] = (p["rot"][0], -p["rot"][1], -p["rot"][2])
        out[other] = q
    return out


def set_interp(action, interp="BEZIER", handles="AUTO_CLAMPED"):
    for fc in _fcurves(action):
        for kp in fc.keyframe_points:
            kp.interpolation = interp
            kp.handle_left_type = handles
            kp.handle_right_type = handles
        fc.update()


def _fcurves(action):
    if hasattr(action, "fcurves") and len(getattr(action, "fcurves", [])):
        return list(action.fcurves)
    out = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


def clear_action_keys(action):
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in list(bag.fcurves):
                    bag.fcurves.remove(fc)
    if hasattr(action, "fcurves"):
        try:
            for fc in list(action.fcurves):
                action.fcurves.remove(fc)
        except Exception:
            pass
