"""Draws the app icon and writes it at every size each platform needs.

A white wine glass, holding red wine, on a burgundy tile. Run from the
repository root after changing the design:

    python tool/icons/make_icons.py

It needs Pillow. The outputs are committed, so builds do not run it.

    python tool/icons/make_icons.py --android-adaptive

writes only the Android adaptive icon (Android 8+ masks it to the launcher's
shape; Android 13+ can tint its monochrome layer), and no other platform's
files.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

BURGUNDY = (109, 26, 54, 255)
WINE = (190, 44, 78, 255)
GLASS = (255, 255, 255, 255)
SUPERSAMPLE = 4
SIZE = 1024


def draw(size=SIZE, rounded=True, margin=0.0, tile=True, mono=False):
    """The icon at [size] pixels. [margin] shrinks the artwork towards the
    centre, as Android's and the web's maskable icons need. Without [tile]
    only the glass is drawn, on transparency: an adaptive icon's foreground.
    [mono] draws the glass for a themed icon, which uses only the alpha
    channel: the empty bowl is faint, the wine and the stem solid."""
    s = size * SUPERSAMPLE
    image = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(image)
    if tile and rounded:
        d.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * 0.22), fill=BURGUNDY)
    elif tile:
        d.rectangle((0, 0, s - 1, s - 1), fill=BURGUNDY)
    glass = (0, 0, 0, 110) if mono else GLASS
    wine_colour = (0, 0, 0, 255) if mono else WINE
    stem = (0, 0, 0, 255) if mono else GLASS

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

    image.paste(glass, (0, 0), bowl)
    image.paste(wine_colour, (0, 0), wine)
    # The stem and the foot.
    d.rounded_rectangle(box(494, 584, 530, 800), radius=int(12 * scale), fill=stem)
    d.ellipse(box(392, 786, 632, 830), fill=stem)
    return image.resize((size, size), Image.LANCZOS)


# An adaptive icon's layers are 108 dp square; the launcher shows a mask of
# at most the middle 72 dp and guarantees only the middle 66 dp. The glass is
# 61 % of its canvas tall, so a 5 % margin keeps all of it inside the
# 66 dp circle.
ADAPTIVE_DP = 108
ADAPTIVE_MARGIN = 0.05
ADAPTIVE_DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
"""

BACKGROUND_XML = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#{colour}</color>
</resources>
"""


def android_adaptive(root):
    """The adaptive icon: a burgundy background colour, the glass as the
    foreground, and the glass again as the monochrome layer."""
    res = root / 'android' / 'app' / 'src' / 'main' / 'res'
    for density, factor in ADAPTIVE_DENSITIES.items():
        px = round(ADAPTIVE_DP * factor)
        folder = res / f'mipmap-{density}'
        draw(px, tile=False, margin=ADAPTIVE_MARGIN).save(folder / 'ic_launcher_foreground.png')
        draw(px, tile=False, margin=ADAPTIVE_MARGIN, mono=True).save(
            folder / 'ic_launcher_monochrome.png')
    (res / 'mipmap-anydpi-v26').mkdir(exist_ok=True)
    with open(res / 'mipmap-anydpi-v26' / 'ic_launcher.xml', 'w', encoding='utf-8', newline='\n') as f:
        f.write(ADAPTIVE_XML)
    r, g, b, _ = BURGUNDY
    with open(res / 'values' / 'ic_launcher_background.xml', 'w', encoding='utf-8', newline='\n') as f:
        f.write(BACKGROUND_XML.format(colour=f'{r:02X}{g:02X}{b:02X}'))


def main():
    root = Path(__file__).resolve().parents[2]
    if sys.argv[1:] == ['--android-adaptive']:
        android_adaptive(root)
        return
    master = draw()
    master.save(root / 'tool' / 'icons' / 'app_icon_1024.png')

    # Android launcher icons (legacy, for API 24 and 25), per density, and
    # the adaptive icon every later version uses.
    for folder, px in {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
    }.items():
        draw(px).save(root / 'android' / 'app' / 'src' / 'main' / 'res' / folder / 'ic_launcher.png')
    android_adaptive(root)

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
