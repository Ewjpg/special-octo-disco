import bpy, os, math
exec(open(os.path.join(ANIM_ROOT, "rbx_bake.py")).read(), globals())
exec(open(os.path.join(ANIM_ROOT, "rig_pose.py")).read(), globals())
if ARM.animation_data:
    ARM.animation_data.action = None


def report(label):
    parts = part_cframes()
    s = []
    for n in ["Torso", "Head", "Right Arm", "Left Arm", "Right Leg", "Left Leg"]:
        m = parts[n]
        e = m.to_euler()
        s.append(f"{n}: p={[round(v, 2) for v in m.translation]} r={[round(math.degrees(v)) for v in e]}")
    print(label, " | ".join(s))


tests = {
    "LowerTorso-FK rx-25": {"LowerTorso-FK": {"rot": (-25, 0, 0)}},
    "LowerTorso-FK z-0.5": {"LowerTorso-FK": {"loc": (0, 0, -0.5)}},
    "Torso_FK rx-25": {"Torso_FK": {"rot": (-25, 0, 0)}},
    "UpperTorsoIK y+0.6": {"UpperTorso-IKTarget": {"loc": (0, 0.6, 0)}},
    "RightLeg-IK y+1.2 z+0.6": {"RightLeg-IK": {"loc": (0, 1.2, 0.6)}},
    "RightGrab y+1 z+1": {"RightArm_GrabPoint": {"loc": (0, 1, 1)}},
    "MasterControl rz+30": {"MasterControl": {"rot": (0, 0, 30)}},
    "LookTo x+3": {"LookToPoint": {"loc": (3, 0, 0)}},
}
report("REST")
for label, poses in tests.items():
    reset_pose()
    for n, p in poses.items():
        ctrl(n, p.get("loc", (0, 0, 0)), p.get("rot", (0, 0, 0)))
    report(label)
reset_pose()
