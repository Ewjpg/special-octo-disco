"""Stadium bowl geometry, in Roblox space (studs, Y up, origin at the centre spot, grass at y = 0).

Pure numpy, so both the Blender script (render, GLB export) and plain Python (Studio blobs) use the
exact same triangles.

The bowl is a rounded rectangle (superellipse) swept with a cross-section profile:
    concourse floor -> front wall -> lower tier -> walkway + fascia -> middle tier
    -> walkway + fascia -> upper tier -> back wall -> outer wall,
with a ring roof on top whose oval opening sits over the pitch.

`build()` returns a list of chunks: {name, material, tris (T,3,3), uvs (T,3,2)}.
Every quad gets its own four vertices, so the shading stays flat between tiers.
UV v = 0 is the TOP of the texture image (Roblox convention).
"""
from __future__ import annotations

import math

import numpy as np

def _read_fieldspec() -> dict[str, float]:
    """Pitch numbers straight from the game's Shared/FieldSpec.luau, so the bowl always fits the pitch."""
    import re
    from pathlib import Path

    path = Path(__file__).resolve().parents[2] / "src" / "shared" / "FieldSpec.luau"
    text = path.read_text(encoding="utf-8")
    return {k: float(v) for k, v in re.findall(r"^FieldSpec\.(\w+) = ([\d.]+)\s*$", text, re.M)}


FIELD = _read_fieldspec()
HL, HW = FIELD["Length"] / 2, FIELD["Width"] / 2
# Pitch boundary (the boards): half length/width plus the run-off margins.
ARENA_X, ARENA_Z = HL + FIELD["EndMargin"], HW + FIELD["SideMargin"]

# Inner edge of the stands: a superellipse that clears the arena's (cut) corners with room to spare.
EXPONENT = 4.0
A0, B0 = round(ARENA_X * 1.145), round(ARENA_Z * 1.227)
SEGMENTS = 400  # around the bowl
SECTORS = 8  # mesh chunks per material (keeps each mesh well under 10k triangles)

ROW_DEPTH = 4.5
LOWER = dict(rows=16, rise=2.6)
MIDDLE = dict(rows=12, rise=3.4)
UPPER = dict(rows=14, rise=4.2)
FRONT_WALL = 5.0
WALKWAY = 6.0
FASCIA = 7.5

CROWD_TILE = 32.0  # studs of stand per crowd texture repeat (one aisle per repeat)
CONCRETE_TILE = 16.0
ROOF_TILE = 24.0
CROWD_BANDS = 4  # seat rows per crowd texture
TREAD_SPLIT = 150.0 / 256.0  # where the riser part of a band starts (matches textures.py)


# ---------------------------------------------------------------------------
# the plan curve
# ---------------------------------------------------------------------------

def _superellipse(theta: np.ndarray, a: float, b: float) -> np.ndarray:
    c, s = np.cos(theta), np.sin(theta)
    x = a * np.sign(c) * np.abs(c) ** (2.0 / EXPONENT)
    z = b * np.sign(s) * np.abs(s) ** (2.0 / EXPONENT)
    return np.stack([x, z], axis=1)


def _even_angles(n: int) -> np.ndarray:
    """Angles that space points evenly by arc length along the inner curve."""
    dense = np.linspace(0, 2 * math.pi, 20000, endpoint=False)
    pts = _superellipse(dense, A0, B0)
    seg = np.linalg.norm(np.roll(pts, -1, axis=0) - pts, axis=1)
    cum = np.concatenate([[0.0], np.cumsum(seg)])
    targets = np.linspace(0, cum[-1], n, endpoint=False)
    idx = np.searchsorted(cum, targets)
    return dense[np.clip(idx, 0, len(dense) - 1)]


THETA = _even_angles(SEGMENTS)


def ring(d: float) -> np.ndarray:
    """Plan points (x, z) of the curve offset d studs outward from the inner edge."""
    return _superellipse(THETA, A0 + d, B0 + d)


def ring_arclength(d: float) -> np.ndarray:
    """Cumulative arc length at each segment start, with the closing length appended."""
    pts = ring(d)
    seg = np.linalg.norm(np.roll(pts, -1, axis=0) - pts, axis=1)
    return np.concatenate([[0.0], np.cumsum(seg)])


# ---------------------------------------------------------------------------
# strips: a profile edge (d0, y0) -> (d1, y1) swept around the bowl
# ---------------------------------------------------------------------------

class Builder:
    def __init__(self) -> None:
        # material -> sector -> list of (tri positions, tri uvs)
        self.data: dict[str, list[list]] = {}

    def _put(self, material: str, sector: int, tri: np.ndarray, uv: np.ndarray) -> None:
        sectors = self.data.setdefault(material, [[] for _ in range(SECTORS)])
        sectors[sector].append((tri, uv))

    def strip(self, material: str, p0, p1, u_tile: float, v0: float, v1: float, u_offset: float = 0.0, flip: bool = False):
        """Sweep the edge p0 -> p1 (each (d, y)) around the bowl.

        u runs along the curve (tile length u_tile studs, measured on the outer of the two
        offsets), v goes v0 at p0 to v1 at p1. The face normal points towards the pitch / up
        unless flip is set.
        """
        (d0, y0), (d1, y1) = p0, p1
        r0, r1 = ring(d0), ring(d1)
        arc = ring_arclength(max(d0, d1))
        n = SEGMENTS
        for i in range(n):
            j = (i + 1) % n
            a0 = np.array([r0[i, 0], y0, r0[i, 1]])
            b0 = np.array([r0[j, 0], y0, r0[j, 1]])
            a1 = np.array([r1[i, 0], y1, r1[i, 1]])
            b1 = np.array([r1[j, 0], y1, r1[j, 1]])
            u0 = arc[i] / u_tile + u_offset
            u1 = arc[i + 1] / u_tile + u_offset
            quad = [(a0, (u0, v0)), (b0, (u1, v0)), (b1, (u1, v1)), (a1, (u0, v1))]
            self._quad(material, i * SECTORS // n, quad, flip)

    def _quad(self, material: str, sector: int, quad, flip: bool):
        (pa, ua), (pb, ub), (pc, uc), (pd, ud) = quad
        # Roblox renders triangles counter-clockwise as seen from the front.
        tris = [((pa, ua), (pc, uc), (pb, ub)), ((pa, ua), (pd, ud), (pc, uc))]
        for t in tris:
            if flip:
                t = (t[0], t[2], t[1])
            self._put(material, sector, np.array([p for p, _ in t]), np.array([u for _, u in t]))

    def box_between(self, material: str, sector: int, p_in, p_out, y_in: float, y_out: float, height: float, width: float, tile: float):
        """A beam from plan point p_in to p_out (x, z) whose top runs from y_in to y_out: four long faces."""
        p_in, p_out = np.asarray(p_in, float), np.asarray(p_out, float)
        axis = p_out - p_in
        length = float(np.linalg.norm(axis))
        side = np.array([-axis[1], axis[0]]) / length * (width / 2)
        corners = []
        for s in (-1, 1):
            corners.append((p_in + side * s, p_out + side * s))
        (l_in, l_out), (r_in, r_out) = corners

        def v3(p, y):
            return np.array([p[0], y, p[1]])

        u1 = length / tile
        ti, to = y_in, y_out
        bi, bo = y_in - height, y_out - height
        faces = [
            (v3(l_in, bi), v3(l_out, bo), v3(r_out, bo), v3(r_in, bi)),  # bottom
            (v3(l_in, ti), v3(l_out, to), v3(l_out, bo), v3(l_in, bi)),  # left
            (v3(r_in, bi), v3(r_out, bo), v3(r_out, to), v3(r_in, ti)),  # right
            (v3(l_in, bi), v3(r_in, bi), v3(r_in, ti), v3(l_in, ti)),  # inner end
        ]
        for f in faces:
            quad = [(f[0], (0, 0)), (f[1], (u1, 0)), (f[2], (u1, height / tile)), (f[3], (0, height / tile))]
            self._quad(material, sector, quad, False)
            self._quad(material, sector, quad, True)  # beams are thin: make them double sided

    def prism(self, material: str, sector: int, center, inward, width: float, depth: float, y0: float, y1: float, tile: float = 16.0):
        """Upright box at plan point center (x, z), its front facing `inward` (towards the pitch)."""
        c = np.asarray(center, float)
        f = np.asarray(inward, float)
        f = f / np.linalg.norm(f)
        t = np.array([-f[1], f[0]])
        hw, hd = width / 2.0, depth / 2.0
        corners = [c + f * hd - t * hw, c + f * hd + t * hw, c - f * hd + t * hw, c - f * hd - t * hw]

        def v3(q, y):
            return np.array([q[0], y, q[1]])

        h = y1 - y0
        sides = [(corners[k], corners[(k + 1) % 4]) for k in range(4)]
        for q0, q1 in sides:
            w = float(np.linalg.norm(q1 - q0))
            quad = [(v3(q0, y0), (0, h / tile)), (v3(q1, y0), (w / tile, h / tile)), (v3(q1, y1), (w / tile, 0)), (v3(q0, y1), (0, 0))]
            self._quad(material, sector, quad, False)
            self._quad(material, sector, quad, True)
        top = [(v3(corners[k], y1), (0, 0)) for k in range(4)]
        self._quad(material, sector, top, False)
        self._quad(material, sector, top, True)

    def chunks(self):
        out = []
        for material, sectors in self.data.items():
            for s, items in enumerate(sectors):
                if not items:
                    continue
                tris = np.stack([t for t, _ in items])
                uvs = np.stack([u for _, u in items])
                out.append({"name": f"{material}_{s}", "material": material, "tris": tris, "uvs": uvs})
        return out


# ---------------------------------------------------------------------------
# the bowl
# ---------------------------------------------------------------------------

def build(seed: int = 7):
    rng = np.random.default_rng(seed)
    b = Builder()
    profile_points = []  # (d, y) of every profile corner, for the LED strips and the roof

    # Concourse floor between the boards and the stands (sits just under the pitch apron,
    # so where they overlap the apron wins and nothing flickers).
    b.strip("concrete", (-40.0, -0.03), (0.0, -0.03), CONCRETE_TILE, 0.0, 40.0 / CONCRETE_TILE, flip=True)
    # Front wall of the lower tier.
    b.strip("concrete", (0.0, -0.03), (0.0, FRONT_WALL), CONCRETE_TILE, FRONT_WALL / CONCRETE_TILE, 0.0, flip=True)

    d, y = 0.0, FRONT_WALL

    def tier(spec, start_d, start_y, band_offset):
        dd, yy = start_d, start_y
        for r in range(spec["rows"]):
            band = (r + band_offset) % CROWD_BANDS
            top = band / CROWD_BANDS
            split = top + TREAD_SPLIT / CROWD_BANDS
            bottom = top + 1.0 / CROWD_BANDS
            shift = rng.random()  # every row starts the crowd pattern somewhere else
            # tread: front edge = band bottom, back edge = split (legs / seats)
            b.strip("crowd", (dd, yy), (dd + ROW_DEPTH, yy), CROWD_TILE, bottom, split, shift, flip=True)
            dd += ROW_DEPTH
            if r < spec["rows"] - 1:
                # riser up to the next row: split -> band top (torsos and heads)
                b.strip("crowd", (dd, yy), (dd, yy + spec["rise"]), CROWD_TILE, split, top, shift, flip=True)
                yy += spec["rise"]
        return dd, yy

    d, y = tier(LOWER, d, y, 0)
    # walkway + fascia up to the middle tier
    b.strip("concrete", (d, y), (d, y + 2.0), CONCRETE_TILE, 2.0 / CONCRETE_TILE, 0.0, flip=True)
    y += 2.0
    b.strip("concrete", (d, y), (d + WALKWAY, y), CONCRETE_TILE, 0.0, WALKWAY / CONCRETE_TILE, flip=True)
    d += WALKWAY
    profile_points.append(("fascia", d, y, y + FASCIA))
    b.strip("concrete", (d, y), (d, y + FASCIA), CONCRETE_TILE, FASCIA / CONCRETE_TILE, 0.0, flip=True)
    y += FASCIA

    d, y = tier(MIDDLE, d, y, 1)
    b.strip("concrete", (d, y), (d, y + 2.0), CONCRETE_TILE, 2.0 / CONCRETE_TILE, 0.0, flip=True)
    y += 2.0
    b.strip("concrete", (d, y), (d + WALKWAY, y), CONCRETE_TILE, 0.0, WALKWAY / CONCRETE_TILE, flip=True)
    d += WALKWAY
    profile_points.append(("fascia", d, y, y + FASCIA))
    b.strip("concrete", (d, y), (d, y + FASCIA), CONCRETE_TILE, FASCIA / CONCRETE_TILE, 0.0, flip=True)
    y += FASCIA

    d, y = tier(UPPER, d, y, 2)
    # back wall up to the roof, cap, and the outer facade down to the ground
    back_d = d
    roof_y = y + 14.0
    b.strip("concrete", (d, y), (d, roof_y), CONCRETE_TILE, (roof_y - y) / CONCRETE_TILE, 0.0, flip=True)
    b.strip("concrete", (d, roof_y), (d + 4.0, roof_y), CONCRETE_TILE, 0.0, 4.0 / CONCRETE_TILE, flip=True)
    b.strip("metal", (d + 4.0, 0.0), (d + 4.0, roof_y), CONCRETE_TILE, roof_y / CONCRETE_TILE, 0.0)

    # LED strips on the front wall and both fascias (a hair in front of the wall).
    b.strip("neon_blue", (-0.06, FRONT_WALL - 1.2), (-0.06, FRONT_WALL - 0.4), 64.0, 0.6, 0.4, flip=True)
    for k, (_, fd, fy0, fy1) in enumerate(profile_points):
        colour = "neon_purple" if k % 2 == 0 else "neon_blue"
        b.strip(colour, (fd - 0.06, fy1 - 2.4), (fd - 0.06, fy1 - 0.8), 64.0, 0.6, 0.4, flip=True)
    b.strip("neon_blue", (back_d - 0.06, roof_y - 5.0), (back_d - 0.06, roof_y - 3.6), 64.0, 0.6, 0.4, flip=True)

    # Ring roof: inner edge cantilevers over the lower tier, slab slopes down towards the back.
    inner_d = 64.0
    inner_y = roof_y + 8.0
    thick = 3.0
    outer_d = back_d + 6.0
    b.strip("roof", (inner_d, inner_y + thick), (outer_d, roof_y + thick), ROOF_TILE, 0.0, (outer_d - inner_d) / ROOF_TILE, flip=True)  # top
    b.strip("roof", (inner_d, inner_y), (outer_d, roof_y), ROOF_TILE, 0.0, (outer_d - inner_d) / ROOF_TILE)  # underside
    b.strip("metal", (inner_d, inner_y), (inner_d, inner_y + thick), CONCRETE_TILE, thick / CONCRETE_TILE, 0.0, flip=True)  # edge
    b.strip("neon_purple", (inner_d - 0.06, inner_y + 0.4), (inner_d - 0.06, inner_y + 1.6), 64.0, 0.6, 0.4, flip=True)

    # Roof trusses: radial beams under the slab every few segments.
    step = 8
    r_in, r_out = ring(inner_d + 1.0), ring(outer_d - 1.0)
    for i in range(0, SEGMENTS, step):
        # Tops follow the underside of the sloping slab, a hair below it.
        b.box_between("metal", i * SECTORS // SEGMENTS, r_in[i], r_out[i], inner_y - 0.05, roof_y - 0.05, 4.0, 1.4, CONCRETE_TILE)

    # Massive floodlight pylons standing on the back of the bowl and rising far above the roof:
    # a dark steel shaft with two neon stripes facing the pitch, and a floodlight head on top.
    pylons = 8
    top_y = roof_y + 95.0
    for k in range(pylons):
        i = int((k + 0.5) * SEGMENTS / pylons) % SEGMENTS
        sector = i * SECTORS // SEGMENTS
        base = ring(back_d + 3.0)[i]
        inward = -base / np.linalg.norm(base)
        b.prism("metal", sector, base, inward, 16.0, 12.0, 0.0, top_y)
        for off in (-4.5, 4.5):
            t = np.array([-inward[1], inward[0]])
            stripe = base + inward * 6.05 + t * off
            b.prism("neon_purple", sector, stripe, inward, 1.6, 0.3, roof_y + 6.0, top_y - 4.0)
        head = base + inward * 4.0
        b.prism("metal", sector, head, inward, 40.0, 6.0, top_y - 2.0, top_y + 16.0)
        b.prism("neon_white", sector, head + inward * 3.05, inward, 36.0, 0.3, top_y, top_y + 14.0)

    chunks = b.chunks()
    info = {
        "inner": [A0, B0],
        "outer": [A0 + outer_d, B0 + outer_d],
        "roof_y": roof_y,
        "roof_inner_y": inner_y + thick,
        "back_d": back_d,
    }
    return chunks, info


if __name__ == "__main__":
    chunks, info = build()
    total = 0
    for c in chunks:
        total += len(c["tris"])
    biggest = max(len(c["tris"]) for c in chunks)
    print(f"{len(chunks)} chunks, {total} triangles, biggest chunk {biggest}")
    print(info)
