"""Box GLBs for a standard R6 body at its rest centres (feet at y=0), one file per part.

  blender --background --python-exit-code 1 --python make_parts.py -- <outdir>

Colours make the limbs easy to tell apart in contact sheets: right side warm, left side cool.
"""
import bpy, sys, os

out = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
os.makedirs(out, exist_ok=True)

PARTS = {
    # name: (size, centre, colour)
    "Torso": ((2, 2, 1), (0, 3, 0), (0.20, 0.47, 1.0)),
    "Head": ((2, 1, 1), (0, 4.5, 0), (0.98, 0.80, 0.30)),
    "RightArm": ((1, 2, 1), (1.5, 3, 0), (0.95, 0.45, 0.25)),
    "LeftArm": ((1, 2, 1), (-1.5, 3, 0), (0.35, 0.80, 0.95)),
    "RightLeg": ((1, 2, 1), (0.5, 1, 0), (0.85, 0.30, 0.20)),
    "LeftLeg": ((1, 2, 1), (-0.5, 1, 0), (0.25, 0.60, 0.85)),
}

for name, (size, centre, colour) in PARTS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.mesh.primitive_cube_add(size=1)
    ob = bpy.context.active_object
    ob.name = name
    # Blender = Q * Roblox with Q:(X,Y,Z)->(-X,Z,Y), the frame r6_clip.py reads back after import.
    ob.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(scale=True)
    for v in ob.data.vertices:
        v.co.x += -centre[0]
        v.co.y += centre[2]
        v.co.z += centre[1]
    mat = bpy.data.materials.new(name + "_mat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*colour, 1)
    ob.data.materials.append(mat)
    path = os.path.join(out, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB")
    print("wrote", path)
