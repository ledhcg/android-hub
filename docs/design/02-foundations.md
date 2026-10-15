# Foundations

All values are defined in `Sources/AndroidHub/Design/DesignTokens.swift`.

## Colour

Colour comes from **system semantic colours** so light/dark, increased contrast and the user's accent keep working.

| Role | Token / API | Use |
|---|---|---|
| Canvas | `Surface.canvas` | Window and detail background. Toolbar and content share it: no visible seam |
| Card | `Surface.card` | Grouped content sitting on the canvas |
| Well | `Surface.well` | Recessed output: logs, errors, command results |
| Text | `.primary`, `.secondary`, `.tertiary` | Three levels only. Secondary for supporting text, tertiary for hints |
| Interactive | system accent (`.tint`) | Buttons, links, selection. **Never override the accent.** |
| Warning / error / success | `.orange`, `.red`, `.green` | State only (chips, banners, indicators), always paired with text or an icon |
| Brand green | `Brand.green` | **Decorative only**: the empty-state glyph, "live" indicator. Never for buttons or links |

Rules: never encode meaning in colour alone; never put body text on a tinted background below 4.5:1 contrast; do not hard-code
hex values in views.

## Typography

System font (SF) through text styles, via `TypeRole`:

| Role | Token | Use |
|---|---|---|
| Title | `TypeRole.title` | Empty-state and page titles |
| Section | `TypeRole.section` | Group titles inside panels |
| Body | `TypeRole.body` | Primary content, row titles |
| Secondary | `TypeRole.secondary` | One-line explanations, row subtitles |
| Caption | `TypeRole.caption` | Hints, counters, row metadata |
| Mono | `TypeRole.mono` | Logs, serials, paths, command output |

Rules: no fixed point sizes except icon glyphs; at most two weights per screen (regular + semibold); sentence case for
descriptions, Title Case for buttons, menu items and window titles.

## Spacing

4-pt scale: `Space.xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32`.
Inside a group use `sm`/`md`; between groups `lg`/`xl`; around a screen's content `lg`; empty states `xl`. No other values.

## Radius

`Radius.control 8` (fields, chips, wells) · `Radius.card 12` (cards, grouped content) · `Radius.panel 16` (large floating
surfaces). Always `.continuous` corners. Capsules for floating bars, pills and toasts.

## Elevation and material

- Flat by default. Separation comes from surface contrast and whitespace, not borders and shadows.
- Floating controls over content (canvas control bar, toasts) use **Liquid Glass** via `glassSurface(in:)`, which falls back to a
  material before macOS 26. Use glass for controls that float over content only, never for panels or rows.
- Hairline borders (`.separator`) only on wells.

## Iconography

SF Symbols only, `.hierarchical` rendering where available, regular weight, matched to the text size beside them. One symbol per
concept across the app (e.g. `iphone.gen3` = phone, `desktopcomputer` = emulator). Icon-only buttons need `.help` and an
accessibility label.

## Motion

Short (≤ 0.25 s), purposeful (state change, appearance of a toast), using system springs/ease. No decorative animation. All
non-essential motion is disabled under Reduce Motion.
