"""Рисует картинки-превью по данным, выгруженным тестовым стендом.

    python3 tools/preview/render.py <папка с stadium.json и anims.json> <папка для картинок>

Это не рендер Roblox: простая ортографическая проекция «коробок» с плоской заливкой.
Нужна, чтобы без Studio увидеть раскладку стадиона и позы анимаций.
"""

import json
import math
import sys

from PIL import Image, ImageDraw, ImageFont

BOX_FACES = [
    # (ось нормали, знак, индексы углов)
    ((1, 0, 0), [1, 3, 7, 5]),
    ((-1, 0, 0), [0, 4, 6, 2]),
    ((0, 1, 0), [2, 6, 7, 3]),
    ((0, -1, 0), [0, 1, 5, 4]),
    ((0, 0, 1), [4, 5, 7, 6]),
    ((0, 0, -1), [0, 2, 3, 1]),
]


def mat_vec(m, v):
    return (
        m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
        m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
        m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
    )


def camera_matrix(yaw_deg, pitch_deg):
    """Матрица поворота мира в систему камеры (x вправо, y вверх, z к зрителю)."""
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(pitch), math.sin(pitch)
    # сначала поворот вокруг Y, потом наклон вокруг X
    ry = (cy, 0, sy, 0, 1, 0, -sy, 0, cy)
    rx = (1, 0, 0, 0, cp, -sp, 0, sp, cp)
    return tuple(sum(rx[r * 3 + k] * ry[k * 3 + c] for k in range(3)) for r in range(3) for c in range(3))


def box_corners(part):
    """8 углов коробки в мире; индекс угла = x + 2*y + 4*z (0 — минус, 1 — плюс по оси)."""
    sx, sy, sz = (v / 2 for v in part["s"])
    r, p = part["r"], part["p"]
    corners = []
    for dz in (-sz, sz):
        for dy in (-sy, sy):
            for dx in (-sx, sx):
                w = mat_vec(r, (dx, dy, dz))
                corners.append((p[0] + w[0], p[1] + w[1], p[2] + w[2]))
    return corners


LIGHT = (0.35, 0.85, 0.4)
_len = math.sqrt(sum(v * v for v in LIGHT))
LIGHT = tuple(v / _len for v in LIGHT)


def shade(color, normal_world, emissive):
    if emissive:
        return tuple(int(min(1.0, c * 1.05) * 255) for c in color)
    d = max(0.0, sum(a * b for a, b in zip(normal_world, LIGHT)))
    k = 0.45 + 0.6 * d
    return tuple(int(max(0.0, min(1.0, c * k)) * 255) for c in color)


def collect_faces(parts, cam, min_alpha=0.05):
    faces = []
    for part in parts:
        alpha = 1.0 - part.get("t", 0)
        if alpha < min_alpha:
            continue
        corners = box_corners(part)
        cam_corners = [mat_vec(cam, c) for c in corners]
        color = part.get("c", (0.8, 0.8, 0.8))
        emissive = part.get("m") in ("Neon", "ForceField")
        for normal, idx in BOX_FACES:
            n_world = mat_vec(part["r"], normal)
            n_cam = mat_vec(cam, n_world)
            if n_cam[2] <= 0.02:
                continue  # грань смотрит от камеры
            pts = [cam_corners[i] for i in idx]
            depth = sum(p[2] for p in pts) / 4
            faces.append((depth, [(p[0], p[1]) for p in pts], shade(color, n_world, emissive), alpha))
    faces.sort(key=lambda f: f[0])
    return faces


def draw_faces(image, faces, scale, origin, outline=None):
    overlay = None
    draw = ImageDraw.Draw(image, "RGBA")
    for _depth, pts, color, alpha in faces:
        poly = [(origin[0] + x * scale, origin[1] - y * scale) for x, y in pts]
        fill = color + (int(alpha * 255),)
        draw.polygon(poly, fill=fill, outline=outline)
    return overlay


def font(size):
    for path in (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def render_stadium(parts, out_path, yaw, pitch, width, title, crop=None):
    cam = camera_matrix(yaw, pitch)
    if crop:
        parts = [p for p in parts if crop(p)]
    faces = collect_faces(parts, cam)
    xs = [x for f in faces for x, _ in f[1]]
    ys = [y for f in faces for _, y in f[1]]
    min_x, max_x, min_y, max_y = min(xs), max(xs), min(ys), max(ys)
    margin = 40
    scale = (width - margin * 2) / (max_x - min_x)
    height = int((max_y - min_y) * scale + margin * 2 + 40)
    image = Image.new("RGB", (width, height), (16, 18, 28))
    origin = (margin - min_x * scale, margin + 40 + max_y * scale)
    draw_faces(image, faces, scale, origin)
    ImageDraw.Draw(image).text((margin, 14), title, fill=(235, 238, 248), font=font(22))
    image.save(out_path)
    print("saved", out_path, image.size, "faces:", len(faces))


def render_animations(anims, out_path):
    """Два ряда на анимацию: вид сбоку (персонаж смотрит вправо) и вид спереди."""
    views = [("сбоку", camera_matrix(-90, 4)), ("спереди", camera_matrix(180, 4))]
    cell_w, cell_h, label_w = 132, 150, 150
    frames = len(anims[0]["frames"])
    width = label_w + frames * cell_w + 16
    row_h = cell_h * len(views) + 14
    height = 64 + len(anims) * row_h
    image = Image.new("RGB", (width, height), (16, 18, 28))
    draw = ImageDraw.Draw(image)
    draw.text((16, 10), "Анимации из Shared/Animations на блочном R15", fill=(235, 238, 248), font=font(18))
    draw.text((16, 36), "верхний ряд — вид сбоку (лицом вправо), нижний — спереди; оранжевым выделена правая сторона тела", fill=(158, 164, 184), font=font(12))
    scale = 22
    body = (0.78, 0.8, 0.88)
    right = (1.0, 0.62, 0.3)
    left = (0.42, 0.62, 1.0)
    for row, anim in enumerate(anims):
        top = 64 + row * row_h
        draw.text((14, top + 46), anim["name"], fill=(255, 224, 120), font=font(16))
        draw.text((14, top + 70), "%.2f c%s" % (anim["length"], ", цикл" if anim["loop"] else ""), fill=(158, 164, 184), font=font(12))
        for view_index, (view_name, cam) in enumerate(views):
            view_top = top + view_index * cell_h
            draw.text((14, view_top + cell_h - 34), view_name, fill=(90, 96, 118), font=font(11))
            for col, frame in enumerate(anim["frames"]):
                cx = label_w + col * cell_w + cell_w / 2
                ground = view_top + cell_h - 14
                # HumanoidRootPart стоит на высоте 3, значит газон — это y = 0
                draw.line([(cx - cell_w / 2 + 6, ground), (cx + cell_w / 2 - 6, ground)], fill=(60, 66, 86), width=2)
                parts = []
                for box in frame["boxes"]:
                    color = body
                    if box["n"].startswith("Right"):
                        color = right
                    elif box["n"].startswith("Left"):
                        color = left
                    parts.append({"s": box["s"], "p": box["p"], "r": box["r"], "c": color, "t": 0})
                faces = collect_faces(parts, cam)
                zero = mat_vec(cam, (0, 0, 0))
                origin = (cx - zero[0] * scale, ground + zero[1] * scale)
                draw_faces(image, faces, scale, origin, outline=(20, 22, 30))
                if view_index == 0:
                    draw.text((cx - 14, view_top + 2), "%.2f" % frame["t"], fill=(110, 116, 138), font=font(11))
    image.save(out_path)
    print("saved", out_path, image.size)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    stadium = json.load(open(src + "/stadium.json", encoding="utf-8"))
    anims = json.load(open(src + "/anims.json", encoding="utf-8"))

    render_stadium(stadium, dst + "/stadium-top.png", 0, 90, 1800, "Стадион: вид сверху (ворота СОЛАР слева, НОКС справа)")
    def no_slabs(p):
        # огромная плита земли и козырьки закрывают обзор в простой проекции — на общем виде их не рисуем
        return p["n"] not in ("Ground", "Roof", "RoofLed")

    render_stadium(stadium, dst + "/stadium-view.png", 32, 34, 1800, "Стадион: общий вид (без козырьков трибун)", crop=no_slabs)

    def near_goal(p):
        x, y, z = p["p"]
        return x > 60 and abs(z) < 70 and y < 30 and x < 150 and max(p["s"]) < 200

    render_stadium(stadium, dst + "/stadium-goal.png", 122, 16, 1400, "Ворота и штрафная (вид с поля)", crop=near_goal)
    render_animations(anims, dst + "/animations.png")


if __name__ == "__main__":
    main()
