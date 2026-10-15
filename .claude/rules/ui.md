---
paths:
  - "Sources/AndroidHub/**"
  - "docs/design/**"
---

# UI rules (macOS app)

The design system is `docs/design/` (start at `README.md`); code is `Sources/AndroidHub/Design/`.

- Spacing, radii, fonts, surfaces come from `Space`, `Radius`, `TypeRole`, `Surface`. No numeric literals for those in views.
- System accent only for interactive tint. `Brand.green` is decorative (empty-state glyph, "Live"). Never override `.tint`.
- Reuse `StatusMessage`, `StatusPill`, `cardStyle`, `wellStyle`, `glassSurface`, `prominentActionStyle`. A pattern that appears a
  second time becomes a component and is added to `docs/design/03-components.md` in the same change.
- Glass APIs are guarded by `#if compiler(>=6.2)` + `#available(macOS 26, *)` with a macOS 15 fallback (see `Design/Glass.swift`).
- Every screen handles empty / loading / error / offline / unauthorized with `StatusMessage`; never a blank area.
- Destructive actions use `.confirmationDialog` naming the target and consequence; destructive button has `role: .destructive`.
- Accessibility: keyboard reachable, `.help` + `.accessibilityLabel` on icon-only controls, ≥ 24 pt hit targets, state not
  colour-only, honour Reduce Motion / Reduce Transparency. See `docs/design/05-accessibility.md`.
- Text: Title Case for buttons/menus/titles, sentence case for descriptions, errors say what / why / what next.
- Do not name third-party products as design inspiration in docs or comments.
- Check light + dark and the longest realistic English strings (`docs/design/06-checklist.md`).
