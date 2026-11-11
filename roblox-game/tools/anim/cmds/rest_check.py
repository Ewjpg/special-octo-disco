import bpy, os
exec(open(os.path.join(ANIM_ROOT, "rbx_bake.py")).read(), globals())
show_blocky()
arm = bpy.data.objects["__PrimaryArmature"]
# clear any pose: rest frame without the file's sample action
if arm.animation_data:
    arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.location = (0, 0, 0)
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.scale = (1, 1, 1)
bpy.context.view_layer.update()
for name, m in part_cframes().items():
    print("PART", name, [round(v, 3) for v in m.translation], [round(v, 3) for v in m.to_euler()])
for name, t in transforms().items():
    print("T", name, [round(v, 3) for v in t.translation], [round(v, 3) for v in t.to_euler()])
