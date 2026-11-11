import bpy
arm = bpy.data.objects["__PrimaryArmature"]
print("blender", bpy.app.version_string, "fps", bpy.context.scene.render.fps, "frames", bpy.context.scene.frame_start, bpy.context.scene.frame_end)
print("visible meshes:", [o.name for o in bpy.data.objects if o.type == "MESH" and not o.hide_get() and not o.name.startswith("_")])
for pb in arm.pose.bones:
    props = {k: pb[k] for k in pb.keys() if not k.startswith("_")}
    if props:
        print("PROPS", pb.name, props)
print("arm props", {k: arm[k] for k in arm.keys() if not k.startswith("_")})
print("data props", {k: arm.data[k] for k in arm.data.keys() if not k.startswith("_")})
print("rotation modes", {pb.name: pb.rotation_mode for pb in arm.pose.bones if not pb.bone.hide})
print("shown bones", [pb.name for pb in arm.pose.bones if not pb.bone.hide])
print("action", arm.animation_data.action.name if arm.animation_data and arm.animation_data.action else None)
