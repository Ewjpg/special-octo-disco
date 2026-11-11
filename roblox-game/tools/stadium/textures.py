"""PBR textures for the stadium mesh: colour, normal, roughness and metalness maps, 1024x1024.

    python tools/stadium/textures.py <outdir>

Everything is procedural (numpy + Pillow), so the look can be changed by editing the
palettes below and re-running. Colours are deliberately muted.

Maps per material:
    <name>_color.png      sRGB albedo
    <name>_normal.png     tangent-space normal (OpenGL convention, +Y up), linear
    <name>_roughness.png  linear, white = rough
    <name>_metalness.png  linear, white = metal

UV convention used by build.py: u runs along the stand, v = 0 is the TOP row of the image.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

N = 1024
rng = np.random.default_rng(20261111)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def value_noise(size: int, cells: int, seed: int) -> np.ndarray:
    """Smooth tileable noise in 0..1: a random grid upscaled with bicubic filtering."""
    r = np.random.default_rng(seed)
    grid = r.random((cells, cells)).astype(np.float32)
    # Tile 3x3 and crop the middle so the edges wrap.
    tiled = np.tile(grid, (3, 3))
    img = Image.fromarray((tiled * 255).astype(np.uint8)).resize((size * 3, size * 3), Image.BICUBIC)
    a = np.asarray(img, np.float32)[size : size * 2, size : size * 2] / 255.0
    return a


def fbm(size: int, base_cells: int, octaves: int, seed: int) -> np.ndarray:
    total = np.zeros((size, size), np.float32)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        total += value_noise(size, base_cells * 2**o, seed + o) * amp
        norm += amp
        amp *= 0.5
    return total / norm


def normal_from_height(h: np.ndarray, strength: float) -> np.ndarray:
    """Tangent-space normal map from a height field (wraps at the edges)."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    nx, ny, nz = -dx, dy, np.ones_like(h)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / length, ny / length, nz / length], axis=2)
    return ((n * 0.5 + 0.5) * 255).clip(0, 255).astype(np.uint8)


def save(outdir: Path, name: str, color: np.ndarray, height: np.ndarray, rough: np.ndarray, metal: np.ndarray, bump: float):
    Image.fromarray(color.clip(0, 255).astype(np.uint8), "RGB").save(outdir / f"{name}_color.png")
    Image.fromarray(normal_from_height(height, bump), "RGB").save(outdir / f"{name}_normal.png")
    Image.fromarray((rough.clip(0, 1) * 255).astype(np.uint8), "L").save(outdir / f"{name}_roughness.png")
    Image.fromarray((metal.clip(0, 1) * 255).astype(np.uint8), "L").save(outdir / f"{name}_metalness.png")
    print(f"  {name}: color, normal, roughness, metalness")


def rgb(*c) -> np.ndarray:
    return np.array(c, np.float32)


# ---------------------------------------------------------------------------
# materials
# ---------------------------------------------------------------------------

def concrete(outdir: Path):
    """Dark blue-grey concrete with form-work panel lines and soft stains (neon reads well on it)."""
    base = rgb(62, 68, 86)
    grain = fbm(N, 16, 5, 1)
    stains = fbm(N, 4, 3, 2)
    shade = (grain - 0.5) * 22 + (stains - 0.5) * 30
    color = base[None, None, :] + shade[:, :, None]
    # Form-work joints every 1/4 of the tile.
    y, x = np.mgrid[0:N, 0:N]
    joints = ((x % 256) < 3) | ((y % 256) < 3)
    color[joints] *= 0.82
    # Slight darkening towards the bottom of each panel (dirt runs down).
    color *= (0.94 + 0.06 * (1 - (y % 256) / 256.0))[:, :, None]
    height = grain * 0.6 + stains * 0.2 - joints * 0.5
    rough = 0.82 + (grain - 0.5) * 0.15
    save(outdir, "concrete", color, height, rough, np.zeros((N, N), np.float32), 3.0)


def metal(outdir: Path):
    """Dark navy painted steel: brushed grain, panel seams, rivets."""
    base = rgb(30, 36, 56)
    y, x = np.mgrid[0:N, 0:N]
    brushed = value_noise(N, 512, 3)[:, :]  # fine streaks
    brushed = np.asarray(Image.fromarray((brushed * 255).astype(np.uint8)).resize((N, 8)).resize((N, N)), np.float32) / 255.0
    wear = fbm(N, 8, 4, 4)
    color = base[None, None, :] + ((brushed - 0.5) * 10 + (wear - 0.5) * 16)[:, :, None]
    seams = ((y % 128) < 2)
    color[seams] *= 0.7
    rivets = (((x % 64) - 32) ** 2 + ((y % 128) - 8) ** 2) < 9
    color[rivets] *= 1.25
    height = brushed * 0.2 - seams * 0.6 + rivets * 0.8
    rough = 0.48 + (wear - 0.5) * 0.25
    metalness = np.full((N, N), 0.75, np.float32)
    save(outdir, "metal", color, height, rough, metalness, 4.0)


def roof(outdir: Path):
    """Roof cladding: pale grey-blue panels in a grid with darker seams and gentle streaks."""
    base = rgb(70, 78, 100)
    y, x = np.mgrid[0:N, 0:N]
    streak = fbm(N, 6, 4, 5)
    color = base[None, None, :] + ((streak - 0.5) * 18)[:, :, None]
    # Alternate panel tint for a subtle checker of glass-like and solid panels.
    panel = ((x // 256) + (y // 256)) % 2 == 1
    color[panel] = color[panel] * 0.93 + rgb(150, 168, 196) * 0.07
    seams = ((x % 256) < 4) | ((y % 256) < 4)
    color[seams] = rgb(30, 34, 48)
    height = -seams.astype(np.float32) * 0.7 + streak * 0.1
    rough = np.where(panel, 0.35, 0.55).astype(np.float32) + (streak - 0.5) * 0.1
    metalness = np.where(seams, 0.8, 0.25).astype(np.float32)
    save(outdir, "roof", color, height, rough, metalness, 3.0)


def crowd(outdir: Path):
    """Hologram crowd: faceless standing silhouettes, all in ONE solid colour, on dark seats.

    Four seat rows per image (one 256 px band each). The figures stand on the tread and rise over the
    riser above it, which is what you see from the pitch. Every image starts with an aisle at the left
    edge, so every repeat along a stand has one.
    """
    holo = rgb(112, 168, 255)  # the single crowd colour
    seats = rgb(13, 15, 26)
    riser = rgb(20, 23, 36)
    color = np.zeros((N, N, 3), np.float32)
    y, x = np.mgrid[0:N, 0:N]
    in_band = y % 256
    color[:] = seats
    color[in_band > 150] = riser
    mask = np.zeros((N, N), bool)

    def rect(x0, y0, x1, y1):
        mask[max(0, int(y0)) : max(0, int(y1)), max(0, int(x0)) : max(0, int(x1))] = True

    def disc(cx, cy, r):
        ys, xs = slice(max(0, int(cy - r)), int(cy + r + 1)), slice(max(0, int(cx - r)), int(cx + r + 1))
        yy, xx = np.mgrid[ys, xs]
        mask[ys, xs] |= (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r

    aisle_w = 64
    for b in range(4):
        top = b * 256
        cx = aisle_w + 14 + rng.integers(0, 10)
        while cx < N - 22:
            if rng.random() > 0.05:
                s = 0.85 + rng.random() * 0.3  # body size
                head_r = 11 * s
                head_y = top + 40 + rng.integers(-8, 10)
                shoulder_y = head_y + head_r + 6 * s
                hip_y = shoulder_y + 70 * s
                half = 17 * s
                disc(cx, head_y, head_r)
                rect(cx - 5 * s, head_y + head_r - 2, cx + 5 * s, shoulder_y + 2)  # neck
                # torso narrowing a little towards the hips
                for row in range(int(shoulder_y), int(hip_y)):
                    t = (row - shoulder_y) / max(1.0, hip_y - shoulder_y)
                    w = half * (1.0 - 0.18 * t)
                    rect(cx - w, row, cx + w + 1, row + 1)
                # legs down to the band edge
                rect(cx - half * 0.8, hip_y, cx - 2 * s, top + 254)
                rect(cx + 2 * s, hip_y, cx + half * 0.8, top + 254)
                arm_w = 7 * s
                if rng.random() < 0.25:  # cheering: both arms up
                    rect(cx - half - arm_w + 2, shoulder_y - 52 * s, cx - half + 2, shoulder_y + 10)
                    rect(cx + half - 2, shoulder_y - 52 * s, cx + half + arm_w - 2, shoulder_y + 10)
                elif rng.random() < 0.2:  # one arm up
                    rect(cx + half - 2, shoulder_y - 52 * s, cx + half + arm_w - 2, shoulder_y + 10)
                    rect(cx - half - arm_w + 3, shoulder_y + 2, cx - half + 3, hip_y)
                else:  # arms down
                    rect(cx - half - arm_w + 3, shoulder_y + 2, cx - half + 3, hip_y)
                    rect(cx + half - 3, shoulder_y + 2, cx + half + arm_w - 3, hip_y)
            cx += int(46 * (0.95 + rng.random() * 0.2))

    color[mask] = holo
    # aisle: dark steps with a faint glowing nosing
    aisle = x < aisle_w
    color[aisle] = np.where((in_band > 150)[:, :, None], rgb(26, 30, 44), rgb(34, 38, 54))[aisle]
    nosing = aisle & ((in_band < 4) | ((in_band > 148) & (in_band < 152)))
    color[nosing] = rgb(70, 110, 190)
    mask[aisle] = False

    height = mask.astype(np.float32) * 0.4
    rough = np.where(mask, 0.35, 0.9).astype(np.float32)
    save(outdir, "crowd", color, height, rough, np.zeros((N, N), np.float32), 2.0)


def main() -> int:
    outdir = Path(sys.argv[1] if len(sys.argv) > 1 else "build/stadium/textures")
    outdir.mkdir(parents=True, exist_ok=True)
    print(f"textures -> {outdir}")
    concrete(outdir)
    metal(outdir)
    roof(outdir)
    crowd(outdir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
