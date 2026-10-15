# Components

Use these instead of rebuilding them. Add a new component here when a pattern appears a second time.

| Component | Where | Rules |
|---|---|---|
| `StatusMessage` | Any empty, loading, error or not-ready state | Symbol (40 pt, hierarchical) + title + one sentence + optional actions. At most one prominent action. Tint only for warning/error |
| `StatusPill` | Inline state ("Live", "Recording", "Offline") | Short text (one or two words), tint = state colour, never the only signal |
| `cardStyle()` | Grouped content on the canvas | Padding `Space.md`, radius `Radius.card`, surface `Surface.card` |
| `wellStyle()` | Logs, error text, command output | Monospaced, selectable, hairline border |
| `glassSurface(in:)` | Floating control bar, toast, input composition bubble | Floating over content only |
| `prominentActionStyle()` | The one primary action of a screen | One per screen/sheet. Glass-prominent on macOS 26+ |
| Segmented `Picker` | Switching between peer views (inspector panels) | Icon-only needs per-item `.help`; 3–7 items |
| `Form` + `.formStyle(.grouped)` | Settings-style lists of controls | Sections have titles; controls apply immediately and say so |
| `LabeledContent` | Read-only label/value pairs and label + control rows | Label left, value right; never wrap the label |
| `List(.sidebar)` + `Section` | Device list | Rows: icon, title (1 line, truncating), caption subtitle; context menu for secondary actions |
| `.confirmationDialog` | Destructive actions | Title names the target, message states the consequence, destructive button labelled with the verb |
| `.alert` | Errors that need acknowledgement | Title says what failed; message says why and what to do; single "OK" |
| Toolbar `Menu`/`Button` | Window-level actions | `Label` with title (icon-only presentation), `.help` text |
| Sheet | Multi-step or form tasks (pair device, new emulator) | Title, grouped content, **one** default action bottom-trailing, Cancel with Esc |
