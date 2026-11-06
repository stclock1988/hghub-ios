"""Generate HGHub AppIcon PNGs (violet gradient + white play triangle).

Why a script instead of committing PNGs: the push tool used here only
handles text files, so binary PNGs cannot be pushed directly. This script
runs as a preBuildScript in project.yml (before asset catalog compilation)
and writes every size listed in AppIcon.appiconset/Contents.json.
Requires Pillow: pip install Pillow
"""
from PIL import Image, ImageDraw
import os

TOP = (88, 40, 180)
BOTTOM = (40, 10, 90)
SIZES = [20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]


def grad_color(y, size):
    t = y / max(1, size - 1)
    return (int(TOP[0] + (BOTTOM[0] - TOP[0]) * t),
            int(TOP[1] + (BOTTOM[1] - TOP[1]) * t),
            int(TOP[2] + (BOTTOM[2] - TOP[2]) * t))


def make(size):
    img = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        draw.line([(0, y), (size, y)], fill=grad_color(y, size))
    s = size / 1024.0
    # White play triangle, centred.
    draw.polygon([
        (int(380 * s), int(260 * s)),
        (int(380 * s), int(760 * s)),
        (int(700 * s), int(510 * s)),
    ], fill=(255, 255, 255))
    return img


if __name__ == "__main__":
    out_dir = os.path.join(os.path.dirname(__file__), "..", "HGHub", "Assets.xcassets", "AppIcon.appiconset")
    out_dir = os.path.normpath(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    for size in SIZES:
        path = os.path.join(out_dir, f"icon-{size}.png")
        make(size).save(path)
        print(path)
