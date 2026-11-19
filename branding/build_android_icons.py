"""Generate Android launcher, adaptive-icon and launch-splash resources
from the approved BALKAVACH branding assets.

Usage:  python build_android_icons.py <branding_dir> <android_res_dir> <flutter_images_dir> <preview_dir>
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

BR, RES, FIMG, PREV = (Path(p) for p in sys.argv[1:5])
PREV.mkdir(parents=True, exist_ok=True)

DENS = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

icon = Image.open(BR / "balkavach_app_icon_1024.png").convert("RGB")
fg_src = Image.open(BR / "layers" / "icon_foreground_1024.png").convert("RGBA")


def save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)


# --- legacy launcher icon (pre-Android 8 and launchers without adaptive support)
for d, k in DENS.items():
    px = round(48 * k)
    save(icon.resize((px, px), Image.LANCZOS), RES / f"mipmap-{d}" / "ic_launcher.png")

# --- adaptive icon: 108dp layers; only the centre 66dp circle is guaranteed visible.
#     Fit the panda + B composition inside a circle of radius 31dp (2dp spare).
a = np.asarray(fg_src.getchannel("A")) > 24
ys, xs = np.nonzero(a)
cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
radius = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2).max()
SAFE_R = 31 / 108  # fraction of layer width
FG_MASTER = 1024
scale = SAFE_R * FG_MASTER / radius
w = round(fg_src.width * scale)
fg_scaled = fg_src.resize((w, w), Image.LANCZOS)
fg_master = Image.new("RGBA", (FG_MASTER, FG_MASTER), (0, 0, 0, 0))
ox = round(FG_MASTER / 2 - cx * scale)
oy = round(FG_MASTER / 2 - cy * scale)
fg_master.paste(fg_scaled, (ox, oy), fg_scaled)

# background: same navy radial gradient + soft halo as the 1024 icon, centred on
# the re-centred composition.
S = FG_MASTER
yy, xx = np.mgrid[0:S, 0:S]
dist = np.clip(np.sqrt((xx - S / 2) ** 2 + (yy - S / 2) ** 2) / (S * 0.75), 0, 1)[..., None]
inner = np.array([46, 110, 230], np.float32)
outer = np.array([14, 42, 120], np.float32)
bg_master = Image.fromarray((inner * (1 - dist) + outer * dist).astype(np.uint8), "RGB").convert("RGBA")
halo = Image.new("L", (S, S), 0)
hr = 290 * scale * 1.15
ImageDraw.Draw(halo).ellipse((S / 2 - hr, S / 2 - hr, S / 2 + hr, S / 2 + hr), fill=150)
halo = halo.filter(ImageFilter.GaussianBlur(70 * scale * 1.15))
hl = Image.new("RGBA", (S, S), (190, 225, 255, 0))
hl.putalpha(halo)
bg_master.alpha_composite(hl)
bg_master = bg_master.convert("RGB")

for d, k in DENS.items():
    px = round(108 * k)
    save(fg_master.resize((px, px), Image.LANCZOS), RES / f"mipmap-{d}" / "ic_launcher_foreground.png")
    save(bg_master.resize((px, px), Image.LANCZOS), RES / f"mipmap-{d}" / "ic_launcher_background.png")

# --- launch splash logo (pre-Android 12 windowBackground): 220dp wide, centred
for d, k in DENS.items():
    px = round(220 * k)
    for variant, folder in (("light", f"drawable-{d}"), ("dark", f"drawable-night-{d}")):
        src = Image.open(BR / f"balkavach_logo_{variant}.png").convert("RGBA")
        save(src.resize((px, px), Image.LANCZOS), RES / folder / "launch_logo.png")

# --- in-app splash logo (Flutter asset), 1024 px is ample for a ~280dp logo at 3.5x
logo_light = Image.open(BR / "balkavach_logo_light.png").convert("RGBA")
save(logo_light.resize((1024, 1024), Image.LANCZOS), FIMG / "balkavach_logo_light.png")


# --- previews: launcher masks x sizes x wallpapers
def mask(shape, s):
    m = Image.new("L", (s * 4, s * 4), 0)
    dr = ImageDraw.Draw(m)
    if shape == "circle":
        dr.ellipse((0, 0, s * 4 - 1, s * 4 - 1), fill=255)
    elif shape == "squircle":
        dr.rounded_rectangle((0, 0, s * 4 - 1, s * 4 - 1), radius=int(s * 4 * 0.32), fill=255)
    elif shape == "rounded":
        dr.rounded_rectangle((0, 0, s * 4 - 1, s * 4 - 1), radius=int(s * 4 * 0.12), fill=255)
    elif shape == "teardrop":
        dr.rounded_rectangle((0, 0, s * 4 - 1, s * 4 - 1), radius=int(s * 4 * 0.5), fill=255)
        dr.rectangle((s * 2, s * 2, s * 4 - 1, s * 4 - 1), fill=255)
    return m.resize((s, s), Image.LANCZOS)


def adaptive(s):
    """What a launcher draws: 108dp layers, cropped to the central 72dp, then masked."""
    full = Image.new("RGBA", (FG_MASTER, FG_MASTER))
    full.paste(bg_master)
    full.alpha_composite(fg_master)
    inset = round(FG_MASTER * 18 / 108)
    return full.crop((inset, inset, FG_MASTER - inset, FG_MASTER - inset)).resize((s, s), Image.LANCZOS)


shapes = ["circle", "squircle", "rounded", "teardrop"]
sizes = [48, 72, 96, 144, 192]
walls = [(245, 245, 245), (30, 30, 36), (210, 120, 60)]
cell = 210
sheet = Image.new("RGB", (cell * len(sizes) + 20, cell * len(shapes) * len(walls) + 20), (128, 128, 128))
for wi, wall in enumerate(walls):
    for si, shape in enumerate(shapes):
        row = wi * len(shapes) + si
        for zi, s in enumerate(sizes):
            x0, y0 = 10 + zi * cell, 10 + row * cell
            sheet.paste(wall, (x0, y0, x0 + cell, y0 + cell))
            ic = adaptive(s)
            sheet.paste(ic, (x0 + (cell - s) // 2, y0 + (cell - s) // 2), mask(shape, s))
sheet.save(PREV / "launcher_sheet.png")

# safe-zone overlay on the foreground
ov = Image.new("RGBA", (FG_MASTER, FG_MASTER))
ov.paste(bg_master)
ov.alpha_composite(fg_master)
dr = ImageDraw.Draw(ov)
r = FG_MASTER * 33 / 108
dr.ellipse((FG_MASTER / 2 - r, FG_MASTER / 2 - r, FG_MASTER / 2 + r, FG_MASTER / 2 + r), outline=(255, 0, 0), width=4)
i = FG_MASTER * 18 / 108
dr.rectangle((i, i, FG_MASTER - i, FG_MASTER - i), outline=(0, 255, 0), width=4)
ov.convert("RGB").resize((512, 512), Image.LANCZOS).save(PREV / "safe_zone.png")

# splash previews at phone sizes (dp at 1x) -- logo is 220dp centred
for name, (wdp, hdp) in {"small_320x568": (320, 568), "phone_393x852": (393, 852),
                         "tablet_800x1280": (800, 1280), "landscape_740x360": (740, 360)}.items():
    for variant, bgc in (("light", (250, 250, 250)), ("dark", (0, 0, 0))):
        k = 2
        canvas = Image.new("RGB", (wdp * k, hdp * k), bgc)
        lg = Image.open(RES / f"drawable{'-night' if variant == 'dark' else ''}-xhdpi" / "launch_logo.png")
        canvas.paste(lg, ((canvas.width - lg.width) // 2, (canvas.height - lg.height) // 2), lg)
        canvas.thumbnail((400, 400))
        canvas.save(PREV / f"splash_{name}_{variant}.png")

print("radius", round(radius), "scale", round(scale, 3), "offset", ox, oy)

