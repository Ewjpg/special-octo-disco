"""Pack the stadium for Roblox Studio: one mesh blob per chunk, one texture blob per PBR map,
and a manifest. tools/stadium/studio_load.luau (run through the Studio MCP) fetches them from a
localhost server and rebuilds the stadium as MeshParts with SurfaceAppearance, no upload needed.

    python tools/stadium/export_studio.py <textures dir> <out dir>

mesh.bin (little endian):  "RMSH" u32 version u32 nVerts u32 nUVs u32 nTris
                           f32[nVerts*3] positions (studs, centred on the chunk) f32[nUVs*2] uvs
                           u32[nTris*3] vertex indices  u32[nTris*3] uv indices
tex.bin:                   "RTEX" u32 size  u8[size*size*4] RGBA, row 0 = top of the image
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import geometry  # noqa: E402

MATERIALS = {
    # material: maps with textures; "neon" materials are plain Neon MeshParts without textures.
    "concrete": {"maps": ["color", "normal", "roughness", "metalness"]},
    "crowd": {"maps": ["color", "normal", "roughness", "metalness"]},
    "metal": {"maps": ["color", "normal", "roughness", "metalness"]},
    "roof": {"maps": ["color", "normal", "roughness", "metalness"]},
    "led": {"neon": [78, 112, 176]},  # soft, muted blue light strips
}


def write_mesh(path: Path, tris: np.ndarray, uvs: np.ndarray) -> list[float]:
    lo, hi = tris.reshape(-1, 3).min(axis=0), tris.reshape(-1, 3).max(axis=0)
    center = (lo + hi) / 2.0
    pos = (tris.reshape(-1, 3) - center).astype("<f4")
    uv = uvs.reshape(-1, 2).astype("<f4")
    n = len(pos)
    idx = np.arange(n, dtype="<u4")
    blob = bytearray(struct.pack("<4sIIII", b"RMSH", 1, n, n, n // 3))
    blob += pos.tobytes() + uv.tobytes() + idx.tobytes() + idx.tobytes()
    path.write_bytes(blob)
    return [float(v) for v in center]


def write_texture(path: Path, png: Path) -> int:
    im = Image.open(png)
    im = im.convert("RGBA")
    size = im.width
    assert im.width == im.height, f"{png} must be square"
    path.write_bytes(struct.pack("<4sI", b"RTEX", size) + im.tobytes())
    return size


def main() -> int:
    textures = Path(sys.argv[1])
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)

    chunks, info = geometry.build()
    manifest = {"chunks": [], "materials": {}, "info": info}
    for c in chunks:
        center = write_mesh(out / f"{c['name']}.mesh.bin", c["tris"], c["uvs"])
        manifest["chunks"].append({"name": c["name"], "material": c["material"], "center": center, "tris": len(c["tris"])})

    for name, spec in MATERIALS.items():
        if "neon" in spec:
            manifest["materials"][name] = {"neon": spec["neon"]}
            continue
        for m in spec["maps"]:
            write_texture(out / f"{name}_{m}.tex.bin", textures / f"{name}_{m}.png")
        manifest["materials"][name] = {"maps": spec["maps"]}

    (out / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    total = sum(c["tris"] for c in manifest["chunks"])
    print(f"{len(manifest['chunks'])} chunks, {total} triangles, textures for {len([m for m in MATERIALS if 'maps' in MATERIALS[m]])} materials -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
