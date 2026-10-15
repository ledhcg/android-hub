---
name: ui-change
description: Procedure for any change under Sources/AndroidHub/ (views, panels, sheets, windows, menus). Applies the design system, reuses components, and checks the review checklist. Use before and after editing UI code.
---

# UI change procedure

1. **Read** `docs/design/README.md`, then the doc that matches the change (`02-foundations` for values, `03-components` for pieces,
   `04-patterns` for states/layout/writing) and `.claude/rules/ui.md`.
2. **Find the existing pattern.** Search `Sources/AndroidHub/Design/` and sibling views. Reuse `StatusMessage`, `StatusPill`,
   `cardStyle()`, `wellStyle()`, `glassSurface(in:)`, `prominentActionStyle()`. Do not rebuild them.
3. **Use tokens.** `Space.*`, `Radius.*`, `TypeRole.*`, `Surface.*`. No literal spacing, radii, fonts or colours. Never override the accent.
4. **Cover states.** Empty, loading, error, offline, unauthorized — each via `StatusMessage`. Destructive actions confirmed.
5. **Accessibility.** Keyboard path, `.help` and `.accessibilityLabel` on icon-only controls, ≥ 24 pt targets, not colour-only.
6. **New pattern?** If it appears a second time, add it to `Design/` and document it in `docs/design/03-components.md` in the same change.
7. **Verify** with the `verify-app` skill (emulator only). Work through `docs/design/06-checklist.md` and say which items you did
   not verify.
8. **Record** user-visible changes in `CHANGELOG.md` and leftover follow-ups in `ROADMAP.md`.

Do not name third-party apps as inspiration in docs or comments.
