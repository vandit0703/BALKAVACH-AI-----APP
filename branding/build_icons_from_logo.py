"""Generate the Android launcher icon and launch splash images from the approved logo.

Source: balkavach-frontend/assets/images/logo.jpeg (read only; never modified or moved).
Run from the repository root:  python branding/build_icons_from_logo.py

Writes, under balkavach-frontend/android/app/src/main/res:
  mipmap-*/ic_launcher.png              legacy square icon (Android 7 and older)
  mipmap-*/ic_launcher_foreground.png   adaptive icon layer (logo inside the 66dp safe zone)
  mipmap-*/ic_launcher_background.png   adaptive icon layer (plain white)
  drawable-*/launch_logo.png and drawable-night-*/launch_logo.png   splash logo, 220dp

Requires Pillow. This supersedes branding/build_android_icons.py output (that script used the earlier
artwork); do not run both.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "balkavach-frontend" / "assets" / "images" / "logo.jpeg"
RES = ROOT / "balkavach-frontend" / "android" / "app" / "src" / "main" / "res"

DENSITY = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}
LEGACY_DP = 48
ADAPTIVE_DP = 108
# The launcher masks the 108dp canvas; only the centre ~72dp circle is always visible. The logo is a
# square whose wordmark nearly touches the bottom corners, so it is sized to sit inside that circle.
LOGO_IN_ADAPTIVE_DP = 64
SPLASH_DP = 220
CORNER = 0.16  # rounded-corner radius as a fraction of the side, so the white card suits dark mode too


def rounded(image: Image.Image, fraction: float) -> Image.Image:
    image = image.convert("RGBA")
    mask = Image.new("L", image.size, 0)
    radius = round(min(image.size) * fraction)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.size[0] - 1, image.size[1] - 1), radius, fill=255)
    image.putalpha(mask)
    return image


def resized(image: Image.Image, side: int) -> Image.Image:
    return image.resize((side, side), Image.LANCZOS)


def main() -> None:
    logo = Image.open(SOURCE).convert("RGB")
    if logo.size[0] != logo.size[1]:
        raise SystemExit(f"{SOURCE.name} must be square, it is {logo.size}")
    for name, scale in DENSITY.items():
        # Legacy icon.
        legacy = rounded(resized(logo, round(LEGACY_DP * scale)), CORNER)
        (RES / f"mipmap-{name}").mkdir(parents=True, exist_ok=True)
        legacy.save(RES / f"mipmap-{name}" / "ic_launcher.png")

        # Adaptive layers.
        canvas_px = round(ADAPTIVE_DP * scale)
        logo_px = round(LOGO_IN_ADAPTIVE_DP * scale)
        foreground = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
        offset = (canvas_px - logo_px) // 2
        foreground.paste(rounded(resized(logo, logo_px), CORNER), (offset, offset))
        foreground.save(RES / f"mipmap-{name}" / "ic_launcher_foreground.png")
        Image.new("RGB", (canvas_px, canvas_px), (255, 255, 255)).save(RES / f"mipmap-{name}" / "ic_launcher_background.png")

        # Splash logo (same image in day and night; the card is white with rounded corners).
        splash = rounded(resized(logo, round(SPLASH_DP * scale)), CORNER)
        for folder in (f"drawable-{name}", f"drawable-night-{name}"):
            (RES / folder).mkdir(parents=True, exist_ok=True)
            splash.save(RES / folder / "launch_logo.png")
    print("Icons and splash images written from", SOURCE.relative_to(ROOT))


if __name__ == "__main__":
    main()
