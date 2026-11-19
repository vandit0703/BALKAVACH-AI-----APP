"""Build BalKavach brand assets from the existing logo.jpeg reference."""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage

SRC = Path(sys.argv[1])
FONT = Path(sys.argv[2])
OUT = Path(sys.argv[3])
OUT.mkdir(parents=True, exist_ok=True)

src = Image.open(SRC).convert("RGB")


# ---------- 0. replace mixed-case wordmark with BALKAVACH ----------
def wordmark(img):
    img = img.convert("RGBA")
    W0, H0 = img.size
    # wooden plate covering the old lettering
    px0, py0, px1, py1 = 48, 858, 1206, 1104
    plate_m = Image.new("L", img.size, 0)
    ImageDraw.Draw(plate_m).rounded_rectangle((px0, py0, px1, py1), 60, fill=255)
    pm = np.asarray(plate_m) > 0
    yy = np.arange(H0)[:, None].repeat(W0, 1).astype(np.float32)
    xx = np.arange(W0)[None, :].repeat(H0, 0).astype(np.float32)
    t = np.clip((yy - py0) / (py1 - py0), 0, 1)
    top = np.array([236, 150, 60], np.float32)
    bot = np.array([196, 104, 34], np.float32)
    wood = top * (1 - t[..., None]) + bot * t[..., None]
    grain = (np.sin(xx / 37.0 + np.sin(yy / 11.0) * 2.2) * 0.5 + 0.5) ** 6
    wood = wood - grain[..., None] * np.array([40, 30, 15])
    arr = np.asarray(img).astype(np.float32)
    rim = pm & ~ndimage.binary_erosion(pm, iterations=9)
    arr[pm, :3] = wood[pm]
    arr[rim, :3] = (120, 58, 18)
    out = Image.fromarray(arr.astype(np.uint8), "RGBA")

    # lettering
    fsize = 168
    font = ImageFont.truetype(str(FONT), fsize)
    text = "BALKAVACH"
    tmp = ImageDraw.Draw(Image.new("L", (10, 10)))
    tracking = 4
    widths = [tmp.textlength(ch, font=font) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    scale = min(1.0, (px1 - px0 - 110) / total)
    if scale < 1.0:
        font = ImageFont.truetype(str(FONT), int(fsize * scale))
        widths = [tmp.textlength(ch, font=font) for ch in text]
        total = sum(widths) + tracking * (len(text) - 1)
    layer = Image.new("L", img.size, 0)
    gold = Image.new("L", img.size, 0)
    ld, gdr = ImageDraw.Draw(layer), ImageDraw.Draw(gold)
    asc_bb = tmp.textbbox((0, 0), "B", font=font)
    x = (px0 + px1) / 2 - total / 2
    y = (py0 + py1) / 2 - (asc_bb[3] + asc_bb[1]) / 2
    for i, ch in enumerate(text):
        ld.text((x, y), ch, font=font, fill=255)
        if i < 3:
            gdr.text((x, y), ch, font=font, fill=255)
        x += widths[i] + tracking
    g = np.asarray(layer) > 127
    gl = np.asarray(gold) > 127
    navy = ndimage.binary_dilation(g, iterations=11)
    white_rim = ndimage.binary_dilation(navy, iterations=5)
    shadow = np.roll(white_rim, 9, axis=0)
    a = np.asarray(out).astype(np.float32)
    a[shadow & pm, :3] = a[shadow & pm, :3] * 0.6
    a[white_rim, :3] = (255, 255, 255)
    a[navy, :3] = (20, 50, 140)
    ty = np.clip((yy - y) / (asc_bb[3] - asc_bb[1] + 1e-3), 0, 1)[..., None]
    goldc = np.array([255, 232, 80]) * (1 - ty) + np.array([250, 170, 20]) * ty
    whitec = np.array([255, 255, 255]) * (1 - ty) + np.array([222, 232, 245]) * ty
    a[g & ~gl, :3] = whitec[g & ~gl]
    a[gl, :3] = goldc[gl]
    res = Image.fromarray(a.astype(np.uint8), "RGBA").convert("RGB")
    sd = ImageDraw.Draw(res)
    scx, scy = (px0 + px1) / 2, py1 + 4
    def _star(cx, cy, R, r):
        return [(cx + (R if i % 2 == 0 else r) * np.cos(np.deg2rad(-90 + i * 36)),
                 cy + (R if i % 2 == 0 else r) * np.sin(np.deg2rad(-90 + i * 36))) for i in range(10)]
    sd.polygon(_star(scx, scy, 44, 20), fill=(20, 50, 140))
    sd.polygon(_star(scx, scy, 34, 15), fill=(255, 206, 40))
    sd.polygon(_star(scx - 4, scy - 6, 14, 6), fill=(255, 240, 160))
    # anti-alias the lettering region only
    soft = res.filter(ImageFilter.SMOOTH)
    edge = Image.fromarray((ndimage.binary_dilation(white_rim, iterations=2) & ~ndimage.binary_erosion(g, iterations=2)).astype(np.uint8) * 255)
    res.paste(soft, (0, 0), edge.filter(ImageFilter.GaussianBlur(1)))
    return res


src = wordmark(src)
src.save(OUT.parent / "logo_uppercase_source.png")
rgb = np.asarray(src).astype(np.int16)
H, W, _ = rgb.shape


# ---------- 1. background removal (white connected to border) ----------
def background_alpha(arr, thresh=238):
    near_white = (arr.min(axis=2) >= thresh)
    labels, _ = ndimage.label(near_white)
    border = set(np.unique(np.concatenate(
        [labels[0], labels[-1], labels[:, 0], labels[:, -1]])))
    border.discard(0)
    bg = np.isin(labels, list(border))
    fg = ~bg
    fg = ndimage.binary_fill_holes(fg)
    fg = ndimage.binary_opening(fg, iterations=1)
    # soft edge: erode 1px then blur
    fg = ndimage.binary_erosion(fg, iterations=1)
    a = Image.fromarray((fg * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.1))
    return a


def defringe(img_rgba):
    """Pull white halo out of semi-transparent edge pixels."""
    arr = np.asarray(img_rgba).astype(np.float32)
    a = arr[..., 3:4] / 255.0
    edge = (a > 0) & (a < 1)
    safe = np.clip(a, 0.15, 1)
    un = (arr[..., :3] - 255 * (1 - safe)) / safe
    arr[..., :3] = np.where(edge, np.clip(un, 0, 255), arr[..., :3])
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


alpha = background_alpha(rgb)
logo = src.copy().convert("RGBA")
logo.putalpha(alpha)
logo = defringe(logo)
bbox = logo.getbbox()
pad = 24
logo = logo.crop((max(bbox[0] - pad, 0), max(bbox[1] - pad, 0),
                  min(bbox[2] + pad, W), min(bbox[3] + pad, H)))


def square(img, size):
    s = max(img.size)
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    canvas.paste(img, ((s - img.width) // 2, (s - img.height) // 2), img)
    return canvas.resize((size, size), Image.LANCZOS).filter(
        ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))


brand = square(logo, 2048)
brand.save(OUT / "balkavach_brand_logo.png", optimize=True)


def with_shadow(img, offset=(0, 14), blur=22, opacity=70):
    a = img.getchannel("A")
    sh = Image.new("RGBA", img.size, (20, 30, 60, 0))
    sh.putalpha(a.point(lambda v: v * opacity // 255))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(sh, offset)
    out.alpha_composite(img)
    return out


light = with_shadow(brand)
light.save(OUT / "balkavach_logo_light.png", optimize=True)

# dark: white sticker outline + soft glow
a = np.asarray(brand.getchannel("A")) > 40
outline = ndimage.binary_dilation(a, structure=np.ones((3, 3)), iterations=18)
outline_img = Image.fromarray((outline * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
sticker = Image.new("RGBA", brand.size, (255, 255, 255, 0))
sticker.putalpha(outline_img)
glow = Image.new("RGBA", brand.size, (255, 214, 102, 0))
glow.putalpha(outline_img.filter(ImageFilter.GaussianBlur(30)).point(lambda v: v * 90 // 255))
dark = Image.new("RGBA", brand.size, (0, 0, 0, 0))
dark.alpha_composite(glow)
dark.alpha_composite(sticker)
dark.alpha_composite(brand)
dark.save(OUT / "balkavach_logo_dark.png", optimize=True)


# ---------- 2. app icon ----------
# panda head cutout (source coordinates)
cx0, cy0 = 310, 0
crop = src.crop((cx0, cy0, cx0 + 600, cy0 + 470)).convert("RGBA")
carr = np.asarray(crop).astype(np.int16)
cH, cW = carr.shape[:2]

m = Image.new("L", (cW, cH), 0)
d = ImageDraw.Draw(m)
d.ellipse((106, 128, 496, 430), fill=255)            # head
d.ellipse((30, 70, 230, 270), fill=255)             # left ear
d.ellipse((420, 140, 590, 320), fill=255)           # right ear
d.polygon([(150, 58), (336, 0), (566, 126), (444, 190), (216, 145)], fill=255)  # cap board
d.rectangle((220, 60, 450, 180), fill=255)          # cap crown
d.rectangle((470, 80, 600, 300), fill=255)          # tassel
mask = np.asarray(m) > 0

# exclude kids' brown hair / skin near the sides
r, g, b = carr[..., 0], carr[..., 1], carr[..., 2]
brownish = (r - b > 45) & (r > 90) & (r < 215) & (g < 150)
side = np.zeros_like(mask)
side[200:, :125] = True
side[300:, 475:] = True
mask &= ~(brownish & side)
# remove scarf (red) below the chin
red = (r > 150) & (g < 90) & (b < 90)
lower = np.zeros_like(mask)
lower[380:, :] = True
mask &= ~(red & lower)
grey = (carr[..., :3].max(axis=2) - carr[..., :3].min(axis=2) < 45) & (carr[..., :3].mean(axis=2) < 205)
low2 = np.zeros_like(mask)
low2[405:, :] = True
mask &= ~(grey & low2)

bg_mask = np.asarray(alpha.crop((cx0, cy0, cx0 + cW, cy0 + cH))) > 128
mask &= bg_mask
mask = ndimage.binary_opening(mask, iterations=2)
lab, n = ndimage.label(mask)
if n > 1:
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    mask = lab == (np.argmax(sizes) + 1)
mask = ndimage.binary_fill_holes(mask)
mask = ndimage.gaussian_filter(mask.astype(np.float32), 2.5) > 0.5
mask = ndimage.binary_erosion(mask, iterations=1)
pm = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
panda = crop.copy()
panda.putalpha(pm)
panda = defringe(panda)
panda = panda.crop(panda.getbbox())

S = 1024
# background: deep navy radial gradient
yy, xx = np.mgrid[0:S, 0:S]
dist = np.sqrt((xx - S / 2) ** 2 + (yy - S * 0.44) ** 2) / (S * 0.75)
dist = np.clip(dist, 0, 1)[..., None]
inner = np.array([46, 110, 230], np.float32)
outer = np.array([14, 42, 120], np.float32)
bgarr = inner * (1 - dist) + outer * dist
icon = Image.fromarray(bgarr.astype(np.uint8), "RGB").convert("RGBA")

# soft halo behind panda
halo = Image.new("L", (S, S), 0)
ImageDraw.Draw(halo).ellipse((222, 160, 802, 740), fill=150)
halo = halo.filter(ImageFilter.GaussianBlur(70))
hl = Image.new("RGBA", (S, S), (190, 225, 255, 0))
hl.putalpha(halo)
icon.alpha_composite(hl)
icon_bg = icon.copy()  # adaptive-icon background layer (gradient + halo)

# place panda
pw = 600
ph = int(panda.height * pw / panda.width)
pimg = panda.resize((pw, ph), Image.LANCZOS)
pimg.putalpha(pimg.getchannel("A").point(lambda v: 0 if v < 10 else v))
px, py = (S - pw) // 2 - 30, 150
def drop_shadow(canvas, layer, pos, opacity, blur, color=(5, 15, 50)):
    full = np.zeros((canvas.height, canvas.width), np.float32)
    la = np.asarray(layer.getchannel("A")).astype(np.float32)
    x, y = pos
    full[y:y + la.shape[0], x:x + la.shape[1]] = la[:canvas.height - y, :canvas.width - x]
    full = ndimage.gaussian_filter(full, blur) * opacity / 255.0
    sh = np.zeros((canvas.height, canvas.width, 4), np.uint8)
    sh[..., :3] = color
    sh[..., 3] = np.clip(full, 0, 255).astype(np.uint8)
    canvas.alpha_composite(Image.fromarray(sh, "RGBA"))

drop_shadow(icon, pimg, (px, py + 16), 110, 14)
icon.alpha_composite(pimg, (px, py))


# golden B badge with blue star
def star(cx, cy, R, r, rot=-90):
    pts = []
    for i in range(10):
        ang = np.deg2rad(rot + i * 36)
        rad = R if i % 2 == 0 else r
        pts.append((cx + rad * np.cos(ang), cy + rad * np.sin(ang)))
    return pts


B = 360
font = ImageFont.truetype(str(FONT), 330)
glyph = Image.new("L", (B, B), 0)
gd = ImageDraw.Draw(glyph)
bb = gd.textbbox((0, 0), "B", font=font)
gx = (B - (bb[2] - bb[0])) // 2 - bb[0]
gy = (B - (bb[3] - bb[1])) // 2 - bb[1]
gd.text((gx, gy), "B", font=font, fill=255)
g = np.asarray(glyph) > 0

# chunky outline
outer_ring = ndimage.binary_dilation(g, iterations=16)
mid_ring = ndimage.binary_dilation(g, iterations=7)
badge = Image.new("RGBA", (B, B), (0, 0, 0, 0))
barr = np.zeros((B, B, 4), np.uint8)
barr[outer_ring] = (255, 255, 255, 255)
barr[mid_ring & ~g] = (110, 52, 14, 255)
# golden vertical gradient on the glyph
t = (np.arange(B) / B)[:, None]
top = np.array([255, 222, 89]); bot = np.array([240, 140, 20])
grad = (top * (1 - t)[..., None] + bot * t[..., None]).astype(np.uint8)
gradfull = np.broadcast_to(grad, (B, B, 3))
barr[g, :3] = gradfull[g]
barr[g, 3] = 255
# top highlight
inner = ndimage.binary_erosion(g, iterations=10)
hi = inner & (np.arange(B)[:, None] < B * 0.46) & ~ndimage.binary_erosion(g, iterations=22)

badge = Image.fromarray(barr, "RGBA").filter(ImageFilter.SMOOTH_MORE)

# blue star on the lower bowl
sd = ImageDraw.Draw(badge)
cxs, cys = B * 0.50, B * 0.635
sd.polygon(star(cxs, cys + 4, 70, 30), fill=(10, 30, 90, 160))
sd.polygon(star(cxs, cys, 70, 30), fill=(14, 40, 120, 255))
sd.polygon(star(cxs, cys, 56, 24), fill=(30, 90, 220, 255))
sd.polygon(star(cxs - 6, cys - 8, 22, 10), fill=(120, 175, 255, 255))

bx, by = 560, 560
drop_shadow(icon, badge, (bx + 6, by + 14), 120, 12)
icon.alpha_composite(badge, (bx, by))

icon.convert("RGB").save(OUT / "balkavach_app_icon_1024.png", optimize=True)

# adaptive-icon layers: same composition, split into background / foreground
icon_fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
drop_shadow(icon_fg, pimg, (px, py + 16), 110, 14)
icon_fg.alpha_composite(pimg, (px, py))
drop_shadow(icon_fg, badge, (bx + 6, by + 14), 120, 12)
icon_fg.alpha_composite(badge, (bx, by))
(OUT / "layers").mkdir(exist_ok=True)
icon_fg.save(OUT / "layers" / "icon_foreground_1024.png", optimize=True)
icon_bg.convert("RGB").save(OUT / "layers" / "icon_background_1024.png", optimize=True)

# previews
prev = Image.new("RGB", (1024 + 48 + 96 + 48, 1024), (240, 240, 240))
prev.paste(icon.convert("RGB"), (0, 0))
prev.paste(icon.convert("RGB").resize((48, 48), Image.LANCZOS), (1024 + 24, 40))
prev.paste(icon.convert("RGB").resize((96, 96), Image.LANCZOS), (1024 + 24, 140))
prev.save(OUT.parent / "preview_icon.png")
for name, bgc in (("light", (250, 250, 250)), ("dark", (15, 20, 40))):
    im = Image.open(OUT / f"balkavach_logo_{name}.png")
    p = Image.new("RGBA", im.size, bgc + (255,))
    p.alpha_composite(im)
    p.convert("RGB").resize((800, 800), Image.LANCZOS).save(OUT.parent / f"preview_{name}.png")
print("ok", logo.size, panda.size)



