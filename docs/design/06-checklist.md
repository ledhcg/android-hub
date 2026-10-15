# UI review checklist

Copy into the PR description for any change that touches `Sources/AndroidHub/`.

**System**
- [ ] Spacing, radii, fonts and surfaces come from `Design/DesignTokens.swift` (no literals)
- [ ] System accent untouched; brand green only decorative
- [ ] Only SF Symbols; one symbol per concept
- [ ] Reused an existing component, or added the new one to [03-components.md](03-components.md)

**States**
- [ ] Empty, loading, error, offline/unauthorized handled with `StatusMessage`
- [ ] Destructive actions confirmed, naming the target and consequence
- [ ] Long operations show progress and can be cancelled

**Visual**
- [ ] Checked in light and dark mode
- [ ] Checked at the minimum window size and with the inspector open and closed
- [ ] Checked with the longest realistic English strings (no clipped or overlapping text)
- [ ] Glass only on floating controls; macOS 15 fallback looks right

**Accessibility** ([05-accessibility.md](05-accessibility.md))
- [ ] Keyboard path works; VoiceOver labels present
- [ ] Contrast OK; state not colour-only
- [ ] Reduce Motion / Reduce Transparency honoured

**Writing**
- [ ] Title Case buttons/menus, sentence-case descriptions, errors say what/why/what next
