import bpy, os
for f in ("rbx_bake.py", "rig_pose.py", "author_clips.py"):
    exec(open(os.path.join(ANIM_ROOT, f), encoding="utf-8").read(), globals())
show_blocky()
bpy.context.scene.render.fps = 60
names = build_all()
results = []
for name in names:
    act = bpy.data.actions[name]
    ARM.animation_data.action = act
    frames = CLIPS[name]["frames"]
    path, n = bake_action(name, 0, frames, step=2)
    results.append(f"{name}:{n}")
import json
meta = {n: {"length": CLIPS[n]["frames"] / 60, "loop": CLIPS[n]["loop"], "fadeIn": CLIPS[n]["fadeIn"],
            "fadeOut": CLIPS[n]["fadeOut"], "priority": CLIPS[n]["priority"]} for n in names}
json.dump(meta, open(os.path.join(ANIM_ROOT, "baked", "_meta.json"), "w"), indent=1)
# leave the shot on screen to look at
ARM.animation_data.action = bpy.data.actions["Shoot"]
bpy.context.scene.frame_start, bpy.context.scene.frame_end = 0, CLIPS["Shoot"]["frames"]
bpy.context.scene.frame_set(6)
bpy.ops.wm.save_mainfile()
print("baked", ", ".join(results))
