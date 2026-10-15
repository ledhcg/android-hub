# Accessibility

Every screen must meet all of these before merge.

- **Keyboard:** every action is reachable by keyboard; sheets close with Esc; the default action responds to Return; menu commands
  have shortcuts that do not clash with system ones.
- **VoiceOver:** icon-only controls have an accessibility label (and `.help`); images that carry meaning are labelled, decorative
  ones are hidden; the device canvas exposes a label with device name and state.
- **Contrast:** text ≥ 4.5:1 (3:1 for large text) in light, dark and Increased Contrast. Use system colours; verify any tint.
- **Colour independence:** state is never colour-only; pair with text or a symbol.
- **Motion and transparency:** respect Reduce Motion (no non-essential animation) and Reduce Transparency (glass/material falls
  back to solid surfaces automatically when using the system APIs; do not draw custom blurs).
- **Text size and layout:** use text styles; labels never truncate meaning; rows wrap or truncate with a tooltip, never overlap.
- **Hit targets:** at least 24 × 24 pt for clickable icons.
- **Focus:** a visible focus ring is never removed.
