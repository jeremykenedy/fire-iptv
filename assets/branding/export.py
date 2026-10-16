"""Export fire-iptv native artwork with librsvg's rsvg-convert executable."""
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
BRAND = ROOT / 'assets/branding'
RES = ROOT / 'android/app/src/main/res'
renderer = shutil.which('rsvg-convert')
if not renderer:
    sys.exit('Install librsvg to provide rsvg-convert before exporting artwork.')


def render(source, destination, width, height):
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([renderer, '-w', str(width), '-h', str(height),
                    '-o', str(destination), str(BRAND / source)], check=True)
    print(destination.relative_to(ROOT))


for source, destination, width, height in [
    ('icon.svg', BRAND / 'png/app_icon.png', 1024, 1024),
    ('icon_background.svg', BRAND / 'png/icon_background.png', 1024, 1024),
    ('mark.svg', BRAND / 'png/icon_foreground.png', 1024, 1024),
    ('mark_mono.svg', BRAND / 'png/icon_monochrome.png', 1024, 1024),
    ('mark.svg', BRAND / 'png/splash_mark.png', 1152, 1152),
    ('mark.svg', ROOT / 'assets/images/logo_mark.png', 512, 512),
    ('wordmark.svg', ROOT / 'assets/images/wordmark.png', 800, 200),
    ('tv_banner.svg', RES / 'drawable/tv_banner.png', 320, 180),
    ('tv_banner.svg', RES / 'drawable-xhdpi/tv_banner.png', 640, 360),
]:
    render(source, destination, width, height)
