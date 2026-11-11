"""Contact sheet: python sheet.py out/Clip [step] -> out/Clip/sheet.png (side row over three-quarter row)."""
import sys, os, glob
from PIL import Image, ImageDraw

d = sys.argv[1]
step = int(sys.argv[2]) if len(sys.argv) > 2 else 2
rows = []
for view in ("side", "tq", "front"):
    files = sorted(glob.glob(os.path.join(d, f"{view}_*.png")))[::step]
    if files:
        rows.append(files)
cols = max(len(r) for r in rows)
w, h = Image.open(rows[0][0]).size
w2, h2 = w // 2, h // 2
sheet = Image.new("RGB", (cols * w2, len(rows) * h2), (30, 30, 34))
draw = ImageDraw.Draw(sheet)
for y, files in enumerate(rows):
    for x, f in enumerate(files):
        im = Image.open(f).convert("RGB").resize((w2, h2))
        sheet.paste(im, (x * w2, y * h2))
        draw.text((x * w2 + 4, y * h2 + 4), os.path.basename(f)[-7:-4], fill=(255, 255, 255))
sheet.save(os.path.join(d, "sheet.png"))
print(os.path.join(d, "sheet.png"))
