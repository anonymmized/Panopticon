from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parent.parent
folder = root / 'build' / 'AppIcon.iconset'
folder.mkdir(parents=True, exist_ok=True)
s = 1024
image = Image.new('RGBA', (s, s))
mask = Image.new('L', (s, s)); ImageDraw.Draw(mask).rounded_rectangle((50, 50, 974, 974), radius=212, fill=255)
base = Image.new('RGBA', (s, s)); pixels = base.load()
for y in range(s):
    for x in range(s):
        t = (x + y) / (s * 2)
        pixels[x,y] = (int(20 + t * 15), int(32 + t * 30), int(53 + t * 31), 255)
image.paste(base, (0, 0), mask)
d = ImageDraw.Draw(image)
d.rounded_rectangle((144, 460, 880, 766), radius=91, fill=(79, 128, 145, 125), outline=(152, 218, 218, 160), width=5)
for x, y, size, color in [(208, 540, 130, '#56c7ef'), (386, 498, 174, '#68e0c2'), (606, 540, 130, '#af94ee')]:
    d.rounded_rectangle((x, y, x+size, y+size), radius=int(size*0.25), fill=color)
    d.rounded_rectangle((x+17, y+15, x+size-17, y+25), radius=5, fill=(255,255,255,80))
    d.rounded_rectangle((x+size//2-8,y+size+20,x+size//2+8,y+size+28), radius=4, fill='white')
for size in [16,32,128,256,512]:
    for scale in [1,2]:
        name = f'icon_{size}x{size}' + ('@2x' if scale == 2 else '') + '.png'
        image.resize((size*scale,size*scale),Image.Resampling.LANCZOS).save(folder/name)
image.save(root/'resources'/'AppIcon.icns', format='ICNS')
