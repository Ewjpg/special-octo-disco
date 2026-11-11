import bpy, os, math
exec(open(os.path.join(ANIM_ROOT, "rbx_bake.py")).read(), globals())
exec(open(os.path.join(ANIM_ROOT, "rig_pose.py")).read(), globals())
from mathutils import Quaternion, Vector


def report(label):
    parts = part_cframes()
    s = []
    for n in ["Head", "Right Arm", "Left Arm"]:
        m = parts[n]
        s.append(f"{n}: p={[round(v, 2) for v in m.translation]} r={[round(math.degrees(v)) for v in m.to_euler()]}")
    print(label, " | ".join(s))


def local_rot(name, axis, deg):
    pb = ARM.pose.bones[name]
    pb.rotation_quaternion = Quaternion(Vector(axis), math.radians(deg))
    bpy.context.view_layer.update()


for name in ["RightShoulder", "RightUpperArm", "RightArm_FK", "Head", "RightArm-IK"]:
    pb = ARM.pose.bones[name]
    print("AXES", name, "x", [round(v, 2) for v in (ARM.matrix_world @ pb.matrix).col[0][:3]], "y", [round(v, 2) for v in (ARM.matrix_world @ pb.matrix).col[1][:3]], "z", [round(v, 2) for v in (ARM.matrix_world @ pb.matrix).col[2][:3]])
    for c in pb.constraints:
        print("   CON", c.name, c.type, round(c.influence, 2), getattr(c, "subtarget", ""), "mute" if c.mute else "")
for name, axis in [("RightShoulder", (1, 0, 0)), ("RightUpperArm", (1, 0, 0)), ("RightArm_FK", (1, 0, 0)), ("Head", (1, 0, 0)), ("Head", (0, 0, 1))]:
    reset_pose()
    local_rot(name, axis, 40)
    report(f"{name} local{axis} +40")
reset_pose()
ctrl("RightArm-IK", (0, 1, 1))
report("RightArm-IK y+1 z+1")
reset_pose()
