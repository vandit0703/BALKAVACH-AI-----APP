# Asset Inventory

Source: `stitch_bal_kavach_ai_mobile_app/` (Google Stitch export). Nothing in that
folder was moved, renamed, or edited.

## What the export contains

| Folder | `code.html` | `screen.png` | Used in app slice 1 |
|---|---|---|---|
| `bal_kavach_safe/` | – (`DESIGN.md` only) | – | Design tokens source |
| `bal_kavach_shield_logo/` | Inline SVG (160×160) | 120×168 | Ported to `ShieldLogo` CustomPainter |
| `welcome_language/` | ✓ | 706×1600 | ✓ Welcome / language |
| `parent_safety_consent/` | ✓ | 562×1600 | ✓ Parent consent |
| `parent_authentication/` | ✓ | 701×1600 | ✓ Parent sign-in (email/password — see B1) |
| `create_child_profile/` | ✓ | 390×1290 | ✓ Create child profile |
| `child_home_dashboard/` | ✓ | 490×1600 | ✓ Child home |
| `today_s_missions/` | ✓ | 483×1600 | ✓ Missions list |
| `mission_details_custom_mission/` | ✓ | 600×1600 | ✓ Mission details |
| `complete_your_mission/` | ✓ | 603×1600 | ✓ Mission submit (note proof only — see B2) |
| `parent_mission_approval/` | ✓ | 502×1600 | Next slice |
| `parent_dashboard_reports/` | ✓ | 453×1600 | Next slice |
| `child_profile_family_management/` | ✓ | 584×1600 | Partially (parent home child list) |
| `child_rewards_achievements/` | ✓ | 354×1600 | Later |
| `my_garden/` | ✓ | 432×1600 | Later |
| `parent_settings_security/` | ✓ | 417×1600 | Later |
| `3d_cute_cartoon_avatar_…_aarav_wearing/` | – | 1024×1024 PNG, 1.1 MB | Not bundled (too large; the six Stitch avatars cover the picker) |

`screen.png` files are full-page reference renders. They are **not** embedded in
the app.

## Fonts

The HTML loads Rubik (headlines/labels), Nunito Sans (body) and Material Symbols
from Google Fonts at runtime. The app bundles static TTFs instead so it works
offline and does not contact Google from a child's device:

`balkavach-frontend/assets/fonts/` — `Rubik-{Regular,Medium,SemiBold,Bold}.ttf`,
`NunitoSans-{Regular,SemiBold,Bold}.ttf`, plus `OFL-Rubik.txt` and
`OFL-NunitoSans.txt` (SIL Open Font License 1.1, must ship with the fonts).
Material Symbols are replaced with Flutter's built-in Material Icons (rounded).

Rubik and Nunito Sans have no Gujarati or Devanagari glyphs. Android falls back
to the system Noto fonts for ગુજરાતી / हिन्दी text.

## Illustrations

Every illustration in the HTML is a remote `lh3.googleusercontent.com/aida-public/…`
URL, not a local file. Those URLs are unsigned temporary hosting and can stop
working. Fourteen were downloaded on 2026-10-12, verified as JPEG, and bundled:

| Bundled file | Stitch source screen | Subject |
|---|---|---|
| `assets/images/panda_welcome.jpg` | welcome_language | Kavach panda waving in a garden |
| `assets/images/panda_hoodie.jpg` | child_home_dashboard | Panda in blue "K" hoodie (banner) |
| `assets/images/panda_missions.jpg` | today_s_missions | Panda mascot ("Panda Kavach says") |
| `assets/images/panda_drawing.jpg` | mission_details_custom_mission | Panda painting at an easel (mission hero) |
| `assets/images/panda_cheering.jpg` | complete_your_mission | Panda giving thumbs up (submit / waiting) |
| `assets/images/parent_auth_hero.jpg` | parent_authentication | Parent and child with tablet |
| `assets/images/garden_scene.jpg` | my_garden | Garden (reserved for garden slice) |
| `assets/images/treasure_chest.jpg` | child_rewards_achievements | Treasure chest (reserved for rewards slice) |
| `assets/images/avatars/avatar_{explorer,braids,cap,hero,scientist,astro}.jpg` | create_child_profile | Six child avatar choices |

Not bundled: the shield logo URL (HTTP 403 — the local SVG is used instead), a
robot mascot with a baked-in fake-transparency checkerboard, and photos of
specific named people/families used as sample data in parent screens.

Total bundled image weight ≈ 660 KB. Images are ~512 px wide; Flutter decodes
them with `cacheWidth` sized to the layout to keep memory low.
