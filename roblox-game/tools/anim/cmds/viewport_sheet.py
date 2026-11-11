import bpy, os, math
from mathutils import Vector

CLIP_LIST = globals().get("SHEET_CLIPS") or ["Shoot", "PowerShot", "Slide", "DiveRight", "Run", "Celebrate"]
STEP = globals().get("SHEET_STEP") or 3
sc = bpy.context.scene
arm = bpy.data.objects["__PrimaryArmature"]
cam = bpy.data.objects.get("SheetCam")
if not cam:
    cam = bpy.data.objects.new("SheetCam", bpy.data.cameras.new("SheetCam"))
    sc.collection.objects.link(cam)
cam.data.type = "ORTHO"
cam.data.ortho_scale = 8.5
sc.camera = cam
sc.render.resolution_x = sc.render.resolution_y = 260
win = bpy.context.window_manager.windows[0]
area = next(a for a in win.screen.areas if a.type == "VIEW_3D")
space = area.spaces.active
old_overlay = space.overlay.show_overlays
space.overlay.show_overlays = False
space.shading.type = "SOLID"
space.shading.color_type = "OBJECT"
for o in bpy.data.objects:
    if o.name.endswith("_MBlocky"):
        o.color = (0.95, 0.45, 0.25, 1) if "Right" in o.name else (0.35, 0.7, 0.95, 1) if "Left" in o.name else (0.85, 0.85, 0.85, 1)
views = {"side": Vector((12, 0, 0)), "tq": Vector((9, 9, 3)), "front": Vector((0, 12, 1))}
out_root = os.path.join(ANIM_ROOT, "out_vp")
for name in CLIP_LIST:
    act = bpy.data.actions[name]
    arm.animation_data.action = act
    end = int(act.frame_range[1])
    d = os.path.join(out_root, name)
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        os.remove(os.path.join(d, f))
    for vn, offset in views.items():
        target = Vector((0, 0, 2.4)) if name.startswith("Dive") or name == "Slide" else Vector((0, 0.6, 2.6))
        cam.location = target + offset
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        for f in range(0, end + 1, STEP):
            sc.frame_set(f)
            sc.render.filepath = os.path.join(d, f"{vn}_{f:03d}.png")
            with bpy.context.temp_override(window=win, area=area, region=next(r for r in area.regions if r.type == "WINDOW")):
                bpy.ops.render.opengl(write_still=True, view_context=False)
space.overlay.show_overlays = old_overlay
arm.animation_data.action = bpy.data.actions["Shoot"]
print("rendered", CLIP_LIST)
