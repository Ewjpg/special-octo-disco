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
    """Weathered grey-blue concrete with form-work panel lines and soft stains."""
    base = rgb(132, 137, 146)
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
    """Muted navy painted steel: brushed grain, panel seams, rivets."""
    base = rgb(58, 68, 92)
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
    base = rgb(176, 182, 194)
    y, x = np.mgrid[0:N, 0:N]
    streak = fbm(N, 6, 4, 5)
    color = base[None, None, :] + ((streak - 0.5) * 18)[:, :, None]
    # Alternate panel tint for a subtle checker of glass-like and solid panels.
    panel = ((x // 256) + (y // 256)) % 2 == 1
    color[panel] = color[panel] * 0.93 + rgb(150, 168, 196) * 0.07
    seams = ((x % 256) < 4) | ((y % 256) < 4)
    color[seams] = rgb(84, 92, 110)
    height = -seams.astype(np.float32) * 0.7 + streak * 0.1
    rough = np.where(panel, 0.35, 0.55).astype(np.float32) + (streak - 0.5) * 0.1
    metalness = np.where(seams, 0.8, 0.25).astype(np.float32)
    save(outdir, "roof", color, height, rough, metalness, 3.0)


def crowd(outdir: Path):
    """A packed crowd, four seat rows per image (one 256 px band per row).

    Within a band the top 55 % is the seat tread and the bottom 45 % the riser below it;
    the people sit on the tread and overlap the riser, which is what you see from the pitch.
    Each image also carries an aisle (stairs) at the left edge, so every repeat of the
    texture along a stand has one.
    """
    color = np.zeros((N, N, 3), np.float32)
    height = np.zeros((N, N), np.float32)
    y, x = np.mgrid[0:N, 0:N]

    seat_color = rgb(44, 52, 70)
    riser_color = rgb(96, 100, 110)
    band = y // 256
    in_band = y % 256
    color[:] = seat_color
    color[in_band > 150] = riser_color

    # Muted shirts: home blue, away red, plus neutrals.
    shirts = [
        (rgb(74, 98, 150), 30),
        (rgb(58, 78, 124), 14),
        (rgb(150, 72, 78), 18),
        (rgb(122, 60, 66), 8),
        (rgb(196, 198, 204), 14),
        (rgb(110, 114, 124), 10),
        (rgb(42, 48, 66), 6),
    ]
    weights = np.array([w for _, w in shirts], np.float64)
    weights /= weights.sum()
    skins = [rgb(214, 182, 156), rgb(188, 146, 116), rgb(132, 96, 74), rgb(234, 206, 182), rgb(96, 70, 56)]

    aisle_w = 64  # px, left edge of every tile
    person_w = 46
    for b in range(4):
        top = b * 256
        cx = aisle_w + rng.integers(0, 12)
        while cx < N - person_w // 2:
            if rng.random() > 0.06:  # a few empty seats
                shirt = shirts[rng.choice(len(shirts), p=weights)][0] * (0.9 + rng.random() * 0.2)
                skin = skins[rng.integers(0, len(skins))]
                w = person_w * (0.85 + rng.random() * 0.3)
                body_top = top + 70 + rng.integers(-10, 14)
                body_bottom = top + 200
                hx = cx + rng.integers(-4, 5)
                # torso: rounded box
                bx = np.abs(x[top : top + 256, :] - hx) < w / 2
                by = (y[top : top + 256, :] > body_top) & (y[top : top + 256, :] < body_bottom)
                torso = bx & by
                color[top : top + 256][torso] = shirt
                height[top : top + 256][torso] = 0.6
                # head
                hr = w * 0.28
                hy = body_top - hr * 0.9
                head = (x[top : top + 256, :] - hx) ** 2 + (y[top : top + 256, :] - hy) ** 2 < hr**2
                color[top : top + 256][head] = skin
                height[top : top + 256][head] = 1.0
                # hair cap on half the heads
                if rng.random() < 0.6:
                    hair = head & (y[top : top + 256, :] < hy - hr * 0.2)
                    color[top : top + 256][hair] = rgb(40, 34, 30) * (0.7 + rng.random() * 0.6)
                # raised arm sometimes
                if rng.random() < 0.12:
                    arm = (np.abs(x[top : top + 256, :] - (hx + w * 0.45)) < 6) & (y[top : top + 256, :] > body_top - 60) & (y[top : top + 256, :] < body_top + 10)
                    color[top : top + 256][arm] = skin
                    height[top : top + 256][arm] = 0.8
            cx += int(person_w * (1.0 + rng.random() * 0.15))

    # Aisle: concrete steps, light, with a dark nosing per band.
    aisle = x < aisle_w
    step_shade = np.where(in_band > 150, 118, 138).astype(np.float32)
    color[aisle] = np.stack([step_shade, step_shade + 3, step_shade + 8], axis=2)[aisle]
    nosing = aisle & ((in_band < 6) | ((in_band > 148) & (in_band < 154)))
    color[nosing] = rgb(70, 74, 84)
    rail = (np.abs(x - aisle_w // 2) < 2) & (in_band < 150)
    color[rail] = rgb(150, 156, 168)
    height[aisle] = 0.0

    # Overall gentle variation and a touch of atmospheric haze so it reads as distance.
    var = fbm(N, 8, 3, 7)
    color *= (0.92 + var * 0.16)[:, :, None]
    color = color * 0.92 + rgb(120, 128, 142) * 0.08

    rough = np.full((N, N), 0.9, np.float32)
    save(outdir, "crowd", color, height * 0.5 + var * 0.05, rough, np.zeros((N, N), np.float32), 6.0)


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
