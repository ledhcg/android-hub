---
paths:
  - "Sources/**/*.swift"
  - "Tests/**/*.swift"
---

# Swift style

- Match the surrounding file: comment density, naming, idiom. Doc comments (`///`) explain *why*/contract, not what the code says.
- No `try!`, `as!`, force unwraps on external data. `fatalError` only for truly unreachable initialisers.
- Blocking adb calls run off the main actor (`offMain { … }` in the app).
- Libraries: Swift 6 strict concurrency, `Sendable` types; keep public API minimal (`internal` by default).
- Tests use Swift Testing: `@Suite("…")`, `@Test("sentence describing behaviour")`, `#expect`/`#require`. Put captured device
  output in test fixtures inline; Unicode samples are allowed as test data.
- New warnings are not acceptable; fix or document in `ROADMAP.md`.
