# Patterns

## Window layout

Three columns: **sidebar** (devices and emulators) → **detail** (canvas) → **inspector** (panels for the selected device).

- Sidebar 220–360 pt; inspector 320–560 pt; the detail column flexes and keeps the device centred.
- Toolbar and detail share `Surface.canvas`. Filter/sort live in the toolbar, not in the content.
- The inspector toggles from the toolbar and remembers its state. Its panel switcher is a segmented picker at the top.
- The **compact window** shows only the canvas; it never duplicates inspector controls.

## Navigation and selection

Selecting a device updates the detail and inspector immediately. Selection persists while the device stays connected; when it
disconnects the detail shows a "Device Disconnected" `StatusMessage`. Sidebar sections: *Physical Devices*, *Emulator*; hide an
empty section rather than showing an empty header.

## States

Every screen that loads or depends on a device handles all of these with a `StatusMessage` (never a blank area):

| State | Symbol | Wording pattern |
|---|---|---|
| Nothing selected | `iphone.gen3` | "Select a Device" + where to look |
| Idle / ready | device glyph | Device name, one line on what to do, **one** prominent action |
| Starting / loading | `ProgressView` | What is happening + Cancel when it can take time |
| Unauthorized / offline / no permission | `lock.shield`, `bolt.slash`, `hand.raised` | What is wrong + exact steps to fix |
| Error | `exclamationmark.triangle` (orange) | What failed, selectable technical detail in a well, "Try Again" |

## Progressive disclosure

Long lists (apps, files, logs) show a sensible slice first and offer "Show More"/filter rather than endless scrolling. Advanced
or risky options sit behind a disclosure or menu, not in the primary row.

## Destructive and risky actions

Delete, wipe, clear data, uninstall, overwrite: always confirm; name the target; state the consequence; destructive button uses
`role: .destructive` and the verb ("Delete AVD"). Risky *state* (e.g. unauthorized debugging, wireless debugging on) is shown with
a warning-tinted `StatusPill`, not a modal.

## Feedback

- Immediate setting changes: update the control optimistically, revert and show an error if the device rejects it.
- Transient confirmations ("Screenshot saved") use the glass toast; errors that need action use an alert or inline banner.
- Long operations show progress and are cancellable.

## Writing

- Sentence case for descriptions; Title Case for buttons, menu items and titles. No trailing periods in titles or buttons.
- Buttons are verbs ("Pair Device", "View Screen"); no "Click here".
- Errors: what happened → why (if known) → what to do. No raw exception text without a human sentence first.
- Plain words: "device", not "transport"; show technical terms (adb, serial, dpi) only where users need them.
- All text is English in source; localisation goes through string catalogs when added.
