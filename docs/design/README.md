# Android Hub design system

The single reference for how Android Hub looks, feels and reads. Every UI change follows it; the checklist in
[06-checklist.md](06-checklist.md) is part of code review.

| Doc | What it answers |
|---|---|
| [01-principles.md](01-principles.md) | Why the UI is the way it is; how to decide when a rule does not cover a case |
| [02-foundations.md](02-foundations.md) | Colour, typography, spacing, radius, elevation, icons, motion (the tokens) |
| [03-components.md](03-components.md) | The reusable pieces and when to use each |
| [04-patterns.md](04-patterns.md) | Window layout, navigation, empty/loading/error states, destructive actions, writing |
| [05-accessibility.md](05-accessibility.md) | Requirements every screen must meet |
| [06-checklist.md](06-checklist.md) | Pre-merge UI review checklist |

Code lives in `Sources/AndroidHub/Design/` (`DesignTokens.swift`, `Glass.swift`). Views import values from there and never
hard-code spacing, radii, fonts or colours.

## Scope

Applies to the macOS app (`AndroidHub`). The CLI follows its own conventions (see `CONTRIBUTING.md`), but shares the writing
rules in [04-patterns.md](04-patterns.md#writing).
