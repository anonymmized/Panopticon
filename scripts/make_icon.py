"""Draws the FreeDock app icon and saves Resources/AppIcon.icns (needs Pillow)."""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 1024
ROOT = Path(__file__).resolve().parent.parent


def gradient(size, top, bottom):
    img = Image.new("RGBA", size)
    draw = ImageDraw.Draw(img)
    w, h = size
    for y in range(h):
        t = y / max(1, h - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        draw.line([(0, y), (w, y)], fill=color)
    return img


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# Squircle background with a violet → teal gradient (Aurora theme).
margin = 100
body = (S - 2 * margin, S - 2 * margin)
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([margin, margin + 18, S - margin, S - margin + 18], radius=190,
                                         fill=(0, 0, 0, 110))
icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(22)))
bg = gradient(body, (108, 64, 242), (14, 190, 178))
icon.paste(bg, (margin, margin), rounded_mask(body, 185))

# Glass dock bar.
bar_box = [190, 560, S - 190, 760]
glass = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glass).rounded_rectangle(bar_box, radius=70, fill=(255, 255, 255, 70),
                                        outline=(255, 255, 255, 150), width=6)
icon.alpha_composite(glass)

# Three app tiles, the middle one raised as if magnified.
tiles = [((262, 600), 120, (255, 196, 70)), ((452, 560), 150, (255, 255, 255)), ((672, 600), 120, (255, 102, 140))]
for (x, y), size, color in tiles:
    tile = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle([x, y, x + size, y + size], radius=size * 0.26, fill=color + (255,))
    icon.alpha_composite(tile)

# Space switcher dots above the bar.
draw = ImageDraw.Draw(icon)
for i, x in enumerate([432, 512, 592]):
    r = 26 if i == 1 else 18
    draw.ellipse([x - r, 420 - r, x + r, 420 + r], fill=(255, 255, 255, 255 if i == 1 else 150))

out = ROOT / "Resources" / "AppIcon.icns"
icon.save(out, sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
icon.resize((256, 256), Image.LANCZOS).save(ROOT / "Resources" / "AppIcon-preview.png")
print("saved", out)
