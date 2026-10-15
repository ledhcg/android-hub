# Principles

1. **Native first.** Use system controls, system colours, SF Symbols and standard window structure. The app should feel like it
   shipped with macOS. A custom control needs a reason a system control cannot meet.
2. **The device is the hero.** The device screen is the most important thing in the window. Chrome (toolbars, panels) is quiet,
   low-contrast and gets out of the way; colour is reserved for state and the single primary action.
3. **Calm density.** Compact, aligned and generous with whitespace around groups rather than inside them. Prefer fewer, clearer
   elements over many small ones. Long lists disclose progressively ("Show more") instead of scrolling forever.
4. **One look per idea.** The same concept (empty state, status, destructive confirmation, grouped settings) has exactly one
   appearance everywhere. If two screens differ, one is a bug.
5. **Direct and reversible.** Controls act immediately where that is safe and say what happened. Anything destructive or hard to
   undo is confirmed first, names its target, and never defaults to the destructive choice.
6. **Honest state.** Always show what is happening (connecting, starting, offline, unauthorized) and what the user can do next.
   Never leave a blank area where a state should be.
7. **Accessible by default.** Keyboard-reachable, VoiceOver-labelled, readable in light/dark and increased contrast, honours Reduce
   Motion and Reduce Transparency. See [05-accessibility.md](05-accessibility.md).

## Deciding when the rules are silent

Ask in order: (1) What would a stock macOS app do? (2) Which existing pattern in this app is closest? (3) Does it keep the device
as the focus? If still unclear, choose the simpler option and document the new pattern here in the same change.
