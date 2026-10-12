# Design System

Derived from `stitch_bal_kavach_ai_mobile_app/bal_kavach_safe/DESIGN.md` and the
Tailwind config embedded in every Stitch `code.html`. Where `DESIGN.md` prose and
its YAML disagree (prose calls `#1769E0` "primary"; YAML and HTML use `#0051B6`
as `primary` and `#1769E0` as `primary-container`), the YAML/HTML values win,
because they are what the screens actually render.

Code: `balkavach-frontend/lib/core/theme/`.

## Colour roles (`app_colors.dart` → `ColorScheme`)

| Role | Hex | Typical use |
|---|---|---|
| primary | `#0051B6` | Filled buttons, active nav, links |
| primaryContainer | `#1769E0` | Selected language row, consent CTA, gradient start |
| secondary | `#006A60` | Habit/teal accents, success copy |
| secondaryContainer | `#75F8E5` | "Move" category cards, approved chip |
| tertiary | `#6E5200` | Star icon colour on light gold |
| tertiaryFixed / Dim | `#FFDF9C` / `#F5BF34` | Star pills, "pending" chip, "Help" category cards |
| error / errorContainer | `#BA1A1A` / `#FFDAD6` | Validation, destructive |
| surface | `#F9F9FF` | Page background |
| surfaceContainerLowest | `#FFFFFF` | Cards |
| surfaceContainerLow … Highest | `#F1F3FF` `#E8EDFF` `#E0E8FF` `#D7E2FF` | Tonal layering, filled inputs, chips |
| onSurface / onSurfaceVariant | `#041B3C` / `#424754` | Text |
| outlineVariant | `#C2C6D6` | Rare dividers (whitespace preferred) |

Extra semantic tokens in `BalKavachColors` (a `ThemeExtension`): `success #20B26B`,
`star #FFC83D`, `brandGradient` (primary → secondary, the "Get Started" button),
category tints for Learn / Move / Help / Create.

## Typography (`app_typography.dart`)

Rubik for display, headlines and labels (all numbers, streaks, stars);
Nunito Sans for body. Sizes mirror the Stitch scale and map to Material roles:

| Stitch token | Material role | Size / line | Weight |
|---|---|---|---|
| display-lg-mobile | displaySmall | 34 / 42 | 700 |
| headline-lg-mobile | headlineMedium | 26 / 34 | 600 |
| headline-md | headlineSmall | 22 / 30 | 600 |
| headline-sm | titleLarge | 18 / 26 | 600 |
| label-lg | labelLarge | 15 / 20 | 500 |
| label-md | labelMedium | 13 / 18 | 500 |
| label-sm | labelSmall | 11 / 14 | 600, +0.04em |
| body-lg | bodyLarge | 16 / 24 | 400 |
| body-md | bodyMedium | 14 / 20 | 400 |
| body-sm | bodySmall | 12 / 16 | 400 |

Text respects the system font scale; layouts are scroll-based and tested at
1.0× and 2.0× (see `test/responsive/`).

## Spacing, radius, elevation (`app_spacing.dart`)

- Spacing: `xs 4`, `sm 8`, `md 16`, `lg 24`, `xl 32`, `xxl 48`. Page margin 16
  (compact) / 24 (≥600 px).
- Radius: `sm 8`, `md 16` (inputs), `lg 24` (cards), `xl 32` (hero cards), pill.
- Elevation: blue-tinted ambient shadows, never grey drop shadows.
  `tier1 = 0 4 16 -2 rgba(23,105,224,.08)` for cards,
  `tier2 = 0 8 24 -4 rgba(23,105,224,.16)` for floating pills and CTAs.
- Child "push button" depth: 3 px darker bottom edge on interactive child tiles.

## Breakpoints (`core/responsive/breakpoints.dart`)

| Name | Width | Behaviour |
|---|---|---|
| compact | < 600 | Single column, bottom `NavigationBar`, 16 px margins |
| medium | 600–839 | Content capped at 600 (forms) / 720 (lists), 24 px margins, mission grid 2 columns |
| expanded | ≥ 840 | `NavigationRail` replaces bottom bar, content capped at 840 |

`ResponsiveContent` centres and caps content width; nothing uses fixed device
heights. Touch targets: ≥ 48 px parent, ≥ 56 px child primary actions.

## Components (`lib/shared/widgets/`)

| Widget | Stitch reference |
|---|---|
| `PrimaryButton` (filled pill, optional gradient, loading state, press-scale 0.98) | Get Started, I Agree & Continue, Start Mission |
| `SecondaryButton` (tonal pill) | Parent Gate, Retake |
| `AppTextField` (filled ice-blue, 2 px primary focus border, 16 radius) | Auth and profile forms |
| `ShieldLogo` (CustomPainter port of the SVG) | Shield logo |
| `BrandHeader` (logo + eyebrow + title) | All screen headers |
| `AppCard` (white, 24 radius, tier-1 shadow, no border) | Metric / habit cards |
| `StarPill`, `StatTile`, `XpProgressBar` | Stats dock, star counters |
| `StatusChip` (pending / approved / rejected / needs redo) | Mission status pills |
| `MissionCard`, `CategoryIcon` | Today's missions list |
| `ChildAvatar` | Avatars |
| `MascotBubble` (image + speech bubble) | "Panda Kavach says" |
| `LoadingView`, `ErrorView` (retry), `EmptyView`, `OfflineBanner` | State screens |

## Imagery

Bundled JPEGs only (see `asset-inventory.md`), displayed with `cacheWidth` and
rounded clipping. Illustrations are decorative and carry `excludeFromSemantics`
unless they convey meaning (avatars carry a label).
