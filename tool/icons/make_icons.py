"""Draws the app icon and writes it at every size each platform needs.

A white wine glass, holding red wine, on a burgundy tile. Run from the
repository root after changing the design:

    python tool/icons/make_icons.py

It needs Pillow. The outputs are committed, so builds do not run it.
"""

from pathlib import Path

from PIL import Image, ImageDraw

BURGUNDY = (109, 26, 54, 255)
WINE = (190, 44, 78, 255)
GLASS = (255, 255, 255, 255)
SUPERSAMPLE = 4
SIZE = 1024


def draw(size=SIZE, rounded=True, margin=0.0):
    """The icon at [size] pixels. [margin] shrinks the artwork towards the
    centre, as Android's and the web's maskable icons need."""
    s = size * SUPERSAMPLE
    image = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(image)
    if rounded:
        d.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * 0.22), fill=BURGUNDY)
    else:
        d.rectangle((0, 0, s - 1, s - 1), fill=BURGUNDY)

    scale = s / 1024 * (1 - 2 * margin)
    offset = s * margin

    def p(x, y):
        return (offset + x * scale, offset + y * scale)

    def box(x0, y0, x1, y1):
        return (*p(x0, y0), *p(x1, y1))

    # The bowl: an ellipse cut flat at the rim.
    bowl = Image.new('L', (s, s), 0)
    b = ImageDraw.Draw(bowl)
    b.ellipse(box(342, 200, 682, 590), fill=255)
    b.rectangle(box(0, 0, 1024, 250), fill=0)
    # The wine: the lower part of the bowl, inset from the glass.
    wine = Image.new('L', (s, s), 0)
    w = ImageDraw.Draw(wine)
    w.ellipse(box(366, 224, 658, 566), fill=255)
    w.rectangle(box(0, 0, 1024, 420), fill=0)

    image.paste(GLASS, (0, 0), bowl)
    image.paste(WINE, (0, 0), wine)
    # The stem and the foot.
    d.rounded_rectangle(box(494, 584, 530, 800), radius=int(12 * scale), fill=GLASS)
    d.ellipse(box(392, 786, 632, 830), fill=GLASS)
    return image.resize((size, size), Image.LANCZOS)


def main():
    root = Path(__file__).resolve().parents[2]
    master = draw()
    master.save(root / 'tool' / 'icons' / 'app_icon_1024.png')

    # Android launcher icons (legacy), per density.
    for folder, px in {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
    }.items():
        draw(px).save(root / 'android' / 'app' / 'src' / 'main' / 'res' / folder / 'ic_launcher.png')

    # Windows: one .ico holding every size Explorer and the taskbar use.
    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    icon = draw(256)
    icon.save(
        root / 'windows' / 'runner' / 'resources' / 'app_icon.ico',
        sizes=[(n, n) for n in sizes],
    )

    # Web: the favicon, the manifest icons, and maskable ones with a margin.
    web = root / 'web'
    draw(32).save(web / 'favicon.png')
    draw(192).save(web / 'icons' / 'Icon-192.png')
    draw(512).save(web / 'icons' / 'Icon-512.png')
    draw(192, rounded=False, margin=0.1).save(web / 'icons' / 'Icon-maskable-192.png')
    draw(512, rounded=False, margin=0.1).save(web / 'icons' / 'Icon-maskable-512.png')


if __name__ == '__main__':
    main()
