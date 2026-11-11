import bpy
arm = bpy.data.objects["__PrimaryArmature"]
internal = bpy.data.objects["InternalArmature"]
print("primary mw", [list(map(lambda v: round(v, 3), r)) for r in arm.matrix_world])
print("internal mw", [list(map(lambda v: round(v, 3), r)) for r in internal.matrix_world])
for n in ["MasterControl", "LowerTorso-FK", "Torso_FK", "UpperTorso-IKTarget", "Torso-Pole", "LeftLeg-IK", "RightLeg-IK", "LeftLeg-Pole", "RightLeg-Pole",
          "LeftArm_GrabPoint", "RightArm_GrabPoint", "LeftArm-Pole", "RightArm-Pole", "LookToPoint", "RightShoulder", "Spine", "Head"]:
    pb = arm.pose.bones[n]
    w = arm.matrix_world @ pb.matrix
    print(n, "head", [round(v, 3) for v in w.translation], "x", [round(v, 2) for v in w.col[0][:3]], "y", [round(v, 2) for v in w.col[1][:3]], "z", [round(v, 2) for v in w.col[2][:3]],
          "locks", tuple(pb.lock_location), tuple(pb.lock_rotation))
for n in ["Torso", "Right Leg", "Head"]:
    pb = internal.pose.bones[n]
    print("INT", n, [round(v, 3) for v in (internal.matrix_world @ pb.matrix).translation])
