"""Рисует макет интерфейса по дереву GUI, выгруженному tools/harness/dump_gui.luau.

    python3 tools/preview/render_gui.py <папка с gui-*.json> <папка для картинок>

Упрощённая раскладка Roblox: Position/Size/AnchorPoint, UIListLayout (по горизонтали), UIPadding,
UICorner, UIStroke. Шрифт другой (DejaVu вместо Gotham), поэтому ширина текста приблизительная.
Цель — увидеть расположение блоков и наложения, а не точный вид.
"""

import json
import sys

from PIL import Image, ImageDraw, ImageFont

W, H = 1280, 720
BACKDROP = (46, 110, 58)

_fonts = {}


def font(size, bold):
    key = (int(size), bold)
    if key not in _fonts:
        path = "/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if bold else "")
        try:
            _fonts[key] = ImageFont.truetype(path, max(6, int(size * 0.92)))
        except OSError:
            _fonts[key] = ImageFont.load_default()
    return _fonts[key]


def rgba(color, transparency):
    alpha = int(max(0.0, min(1.0, 1 - (transparency or 0))) * 255)
    return tuple(int(max(0, min(1, c)) * 255) for c in color) + (alpha,)


def child_of(node, cls):
    for c in node["children"]:
        if c["class"] == cls:
            return c
    return None


def wrap(draw, text, fnt, width):
    lines = []
    for paragraph in text.split("\n"):
        words, line = paragraph.split(" "), ""
        for word in words:
            trial = (line + " " + word).strip()
            if draw.textlength(trial, font=fnt) <= width or not line:
                line = trial
            else:
                lines.append(line)
                line = word
        lines.append(line)
    return lines


class Renderer:
    def __init__(self):
        self.image = Image.new("RGBA", (W, H), BACKDROP + (255,))
        self.problems = []

    def layer(self):
        return Image.new("RGBA", (W, H), (0, 0, 0, 0))

    def draw_node(self, node, rect, clip=None):
        x, y, w, h = rect
        layer = self.layer()
        draw = ImageDraw.Draw(layer)
        corner = child_of(node, "UICorner")
        radius = min(corner["radius"], w / 2, h / 2) if corner else 0
        box = [x, y, x + max(w, 0.5), y + max(h, 0.5)]
        if node.get("bg") is not None and (node.get("bgT") or 0) < 1 and w > 0 and h > 0:
            draw.rounded_rectangle(box, radius=radius, fill=rgba(node["bg"], node.get("bgT")))
        stroke = child_of(node, "UIStroke")
        is_text = node["class"] in ("TextLabel", "TextButton")
        if stroke and (stroke.get("transparency") or 0) < 1 and w > 0 and h > 0:
            draw.rounded_rectangle(box, radius=radius, outline=rgba(stroke["color"], stroke.get("transparency")), width=max(1, int(stroke["thickness"])))
        if is_text and node.get("text") and (node.get("textT") or 0) < 1:
            bold = node.get("font") in ("GothamBold", "GothamBlack")
            fnt = font(node.get("textSize") or 14, bold)
            text = node["text"]
            lines = wrap(draw, text, fnt, w) if node.get("wrapped") else text.split("\n")
            line_h = (node.get("textSize") or 14) * 1.12
            total = line_h * len(lines)
            align_y = node.get("alignY") or "Center"
            ty = y if align_y == "Top" else (y + h - total if align_y == "Bottom" else y + (h - total) / 2)
            for line in lines:
                tw = draw.textlength(line, font=fnt)
                align_x = node.get("alignX") or "Center"
                tx = x if align_x == "Left" else (x + w - tw if align_x == "Right" else x + (w - tw) / 2)
                draw.text((tx, ty), line, font=fnt, fill=rgba(node.get("textColor") or (1, 1, 1), node.get("textT")))
                if not node.get("wrapped") and tw > w + 2 and w > 0:
                    self.problems.append("текст шире блока: %r (%.0f > %.0f) в %s" % (line[:40], tw, w, node["name"]))
                ty += line_h
            if node.get("wrapped") and total > h + 2:
                self.problems.append("текст выше блока: %r (%.0f > %.0f) в %s" % (text[:40], total, h, node["name"]))
        if clip:
            mask = Image.new("L", (W, H), 0)
            ImageDraw.Draw(mask).rectangle([clip[0], clip[1], clip[0] + clip[2], clip[1] + clip[3]], fill=255)
            layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", (W, H), 0), mask))
        self.image = Image.alpha_composite(self.image, layer)

    def walk(self, node, parent_rect, clip=None):
        gui_children = [c for c in node["children"] if "size" in c]
        layout = child_of(node, "UIListLayout")
        padding = child_of(node, "UIPadding")
        px, py, pw, ph = parent_rect
        if padding:
            px, py = px + padding["left"], py + padding["top"]
            pw, ph = pw - padding["left"], ph - padding["top"]

        rects = {}
        if layout and layout.get("fill") == "Horizontal":
            ordered = sorted(gui_children, key=lambda c: c.get("order") or 0)
            sizes = []
            for c in ordered:
                s = c["size"]
                sizes.append((pw * s[0] + s[1], ph * s[2] + s[3]))
            total = sum(sw for sw, _ in sizes) + layout["padding"] * max(0, len(sizes) - 1)
            cursor = px + (pw - total if layout.get("alignH") == "Right" else 0)
            for c, (sw, sh) in zip(ordered, sizes):
                rects[id(c)] = (cursor, py, sw, sh)
                cursor += sw + layout["padding"]
        else:
            for c in gui_children:
                s, p, a = c["size"], c["position"], c["anchor"]
                sw, sh = pw * s[0] + s[1], ph * s[2] + s[3]
                rects[id(c)] = (px + pw * p[0] + p[1] - a[0] * sw, py + ph * p[2] + p[3] - a[1] * sh, sw, sh)

        for c in sorted(gui_children, key=lambda c: c.get("z") or 1):
            if c.get("visible") is False:
                continue
            rect = rects[id(c)]
            self.draw_node(c, rect, clip)
            child_clip = clip
            if c.get("clips") or c["class"] == "ScrollingFrame":
                child_clip = rect
            self.walk(c, rect, child_clip)


def render(src, dst, title):
    tree = json.load(open(src, encoding="utf-8"))
    r = Renderer()
    r.walk(tree, (0, 0, W, H))
    out = r.image.convert("RGB")
    ImageDraw.Draw(out).text((8, H - 20), title, font=font(12, False), fill=(230, 235, 245))
    out.save(dst)
    print("saved", dst)
    for problem in sorted(set(r.problems)):
        print("   !", problem)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    render(src + "/gui-menu.json", dst + "/hud-menu.png", "макет: меню стилей (1280x720)")
    render(src + "/gui-play.json", dst + "/hud-play.png", "макет: игра, мяч у игрока, замах (1280x720)")
    render(src + "/gui-goal.json", dst + "/hud-goal.png", "макет: баннер гола (1280x720)")


if __name__ == "__main__":
    main()
