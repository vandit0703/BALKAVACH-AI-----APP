---
name: Bal Kavach Safe
colors:
  surface: '#f9f9ff'
  surface-dim: '#cadaff'
  surface-bright: '#f9f9ff'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f1f3ff'
  surface-container: '#e8edff'
  surface-container-high: '#e0e8ff'
  surface-container-highest: '#d7e2ff'
  on-surface: '#041b3c'
  on-surface-variant: '#424754'
  inverse-surface: '#1d3052'
  inverse-on-surface: '#edf0ff'
  outline: '#727785'
  outline-variant: '#c2c6d6'
  surface-tint: '#0059c7'
  primary: '#0051b6'
  on-primary: '#ffffff'
  primary-container: '#1769e0'
  on-primary-container: '#f0f2ff'
  inverse-primary: '#afc6ff'
  secondary: '#006a60'
  on-secondary: '#ffffff'
  secondary-container: '#75f8e5'
  on-secondary-container: '#007166'
  tertiary: '#6e5200'
  on-tertiary: '#ffffff'
  tertiary-container: '#8c6900'
  on-tertiary-container: '#fff1d9'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#d9e2ff'
  primary-fixed-dim: '#afc6ff'
  on-primary-fixed: '#001a43'
  on-primary-fixed-variant: '#004398'
  secondary-fixed: '#75f8e5'
  secondary-fixed-dim: '#55dbc9'
  on-secondary-fixed: '#00201c'
  on-secondary-fixed-variant: '#005048'
  tertiary-fixed: '#ffdf9c'
  tertiary-fixed-dim: '#f5bf34'
  on-tertiary-fixed: '#251a00'
  on-tertiary-fixed-variant: '#5b4300'
  background: '#f9f9ff'
  on-background: '#041b3c'
  surface-variant: '#d7e2ff'
typography:
  display-lg:
    fontFamily: Rubik
    fontSize: 44px
    fontWeight: '700'
    lineHeight: 52px
    letterSpacing: -0.02em
  display-lg-mobile:
    fontFamily: Rubik
    fontSize: 34px
    fontWeight: '700'
    lineHeight: 42px
    letterSpacing: -0.01em
  headline-lg:
    fontFamily: Rubik
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
  headline-lg-mobile:
    fontFamily: Rubik
    fontSize: 26px
    fontWeight: '600'
    lineHeight: 34px
  headline-md:
    fontFamily: Rubik
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 30px
  headline-sm:
    fontFamily: Rubik
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 26px
  body-lg:
    fontFamily: Nunito Sans
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  body-md:
    fontFamily: Nunito Sans
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
  body-sm:
    fontFamily: Nunito Sans
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
  label-lg:
    fontFamily: Rubik
    fontSize: 15px
    fontWeight: '500'
    lineHeight: 20px
  label-md:
    fontFamily: Rubik
    fontSize: 13px
    fontWeight: '500'
    lineHeight: 18px
  label-sm:
    fontFamily: Rubik
    fontSize: 11px
    fontWeight: '600'
    lineHeight: 14px
    letterSpacing: 0.04em
rounded:
  sm: 0.5rem
  DEFAULT: 1rem
  md: 1.5rem
  lg: 2rem
  xl: 3rem
  full: 9999px
spacing:
  gutter: 1rem
  gutter-mobile: 0.75rem
  margin: 1.5rem
  margin-mobile: 1rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 1rem
  space-lg: 1.5rem
  space-xl: 2rem
  space-xxl: 3rem
---

## Brand & Style

This design system expresses a dual-personality ecosystem: unwavering structural safety for parents paired with an energetic, gamified playground for children. It bridges the discipline of digital wellbeing with celebratory educational growth.

The design movement blends modern **Material 3 tonal layering** with a tactile, friendly spirit. Visual tone hinges on three pillars:
- **Protective & Authoritative:** Built on reassuring deep blues that communicate robust data security, parental peace of mind, and clinical screen-time stewardship.
- **Warm & Encouraging:** Soft sky canvases, sunny reward golds, and celebratory badges that transform routine Indian household habits (study sessions, offline playtime, bedtime rituals) into joyful achievements.
- **Dual-Perspective Fluidity:** Effortlessly adapts between an analytical parent dashboard (structured metrics, control toggles, schedule builders) and a responsive, touch-friendly child interface (oversized interaction targets, character badges, streak counters).

## Colors

The palette is engineered to balance vigilant trust with vibrant milestone celebrations:

- **Primary (`#1769E0`):** Royal Blue anchors primary actions, parent security locks, app headers, and core brand identity.
- **Secondary (`#22B8A7`):** Vibrant Teal drives habit completion, focus timers, wellness metrics, and active state indicators.
- **Tertiary (`#FFC83D`):** Warm Reward Gold is reserved for child achievements, daily streaks, coin balances, and celebration accents.
- **Neutral (`#172B4D`):** Dark Navy serves as high-contrast body typography, grounding the interface and avoiding harsh stark blacks.
- **Semantic Accents:**
  - *Success Green (`#20B26B`):* Task verification, positive screen-time boundaries, and safety validation.
  - *Bright Blue (`#2587F7`):* Interactive links, active tab highlights, and hover states.
  - *Canvas Background (`#F4F8FF`):* A soft ice-blue tint that eliminates ocular fatigue during late-night checks.
  - *Surface Containers (`#FFFFFF`):* Elevated cards and modal bottoms that float above the soft blue canvas.

## Typography

Typography balances structured legibility with soft, approachable curvature. 

- **Rubik (Headlines, Titles, Numerical Callouts):** Features softly rounded vertexes and sturdy geometric proportions. It excels in delivering high-impact numbers (streak counts, coin tallies, time remaining) without appearing clinical.
- **Nunito Sans (Body, Descriptions, Form Hints):** Highly legible humanist sans with generous x-height and open counters. It provides reading ease across varying Indian family literacy levels and screen sizes.
- **Hierarchy Rules:** All streak counts and gamified milestones must use `Rubik` bold weights. Informational microcopy, parental advisories, and habit instructions strictly use `Nunito Sans` regular or semi-bold.

## Layout & Spacing

The layout model adopts a fluid, mobile-first column framework optimized for high single-handed thumb accessibility:

- **Mobile Viewports (<600px):** 4-column fluid layout with `1rem` margins and `0.75rem` gutters. Touch targets sit at a minimum of `48px` in Parent mode and `56px` in Child mode to account for juvenile motor control.
- **Tablet / Foldables (600px - 1024px):** 8-column layout with `1.5rem` margins and `1rem` gutters. Splits parental controls into master-detail side panels while preserving centralized quest paths for the child view.
- **Rhythm & Grid:** Built on a baseline 4px/8px incremental grid. Card paddings default to `space-md` (16px) or `space-lg` (24px) for expansive breathing room over soft tinted backgrounds.

## Elevation & Depth

Depth is conveyed through a blend of **tinted ambient shadows** and **tonal surface stacking** rather than severe drop-shadows:

- **Surface Levels:**
  - `Base Canvas`: Background `#F4F8FF`.
  - `Surface Tier 1 (Cards, Modules)`: Pure `#FFFFFF` resting on canvas, cast with an ambient tinted shadow (`box-shadow: 0 4px 16px -2px rgba(23, 105, 224, 0.08)`).
  - `Surface Tier 2 (Floating Pills, Floating Action Buttons)`: `#FFFFFF` or solid primary hues with `box-shadow: 0 8px 24px -4px rgba(23, 105, 224, 0.16)`.
  - `Surface Tier 3 (Modals, Mode-Switch Drawers)`: `#FFFFFF` bottom sheets, overlaying a 40% opacity Navy `#172B4D` backdrop.
- **Child-Mode Depth:** Interactive quest nodes and claimable reward tiles feature an exaggerated bottom border offset (`border-bottom: 3px solid rgba(0, 0, 0, 0.12)`) simulating physical, satisfying push buttons.

## Shapes

The shape architecture relies entirely on welcoming curvature (`roundedness: 3`):

- **Pills & Buttons:** Standard action buttons, filter tags, streak trackers, and bottom bar indicators use full capsule radius (`9999px` / `pill`).
- **Cards & Sheets:** Base cards use `1.5rem` (24px) corner rounding to maintain a friendly, soft profile that eliminates sharp corners across the entire interface.
- **Interactive Badges:** Floating counters and avatar frames utilize circular or super-elliptical boundaries, reinforcing the non-threatening, protective character of the product.

## Components

### Buttons & Action Bars
- **Primary Action (Parent/Child):** Full pill-shaped height (`48px` parent, `54px` child). Background is `#1769E0` with bold white text. On click/press, scales smoothly to `0.98`.
- **Celebration / Claim Button:** Solid `#FFC83D` with `#172B4D` typography and subtle upward bounce animation on unlock states.

### Cards & Content Modules
- **Metric & Habit Card:** Pristine white background, `24px` rounded corners, padded with `20px`. Borderless by default, using blue-tinted elevation. For streak milestones, a subtle inner gradient (from `#FFFFFF` to light sky tint) is applied.

### Streak Pills & Star Counters
- **Streak Pill:** Compact capsule (`32px` height) with `#FFC83D` 15% opacity background, `#172B4D` bold label, and a flame icon in full `#FFC83D`.
- **Star & Coin Counter:** Floating capsule with white backdrop, thin `#22B8A7` border outline, containing a vibrant emerald/gold token balance counter.

### Form Inputs & Parental Lock Controls
- **Input Fields:** Filled style using 50% opacity ice-blue fill (`#EBF2FD`), zero border in default state, transitioning to a crisp 2px `#1769E0` border upon focus. Corner radius defaults to `16px`.
- **Parental Security PIN / Bio Gate:** Distinct 4-cell circular input arrays with haptic feedback and instantaneous visual lock/unlock indicators.

### Navigation Architecture
- **Dual-Mode Bottom Navigation:** Persistent floating dock (`24px` radius) lifted above the canvas. 
  - *Parent Mode:* Sleek icons for Analytics, Geofencing, Rules, and Settings.
  - *Child Mode:* Oversized, vibrant icons for Quests, Rewards, Vault, and Avatar Studio. Mode toggle sits in a protected top-app-bar drawer requiring a 3-second hold or mathematical challenge.