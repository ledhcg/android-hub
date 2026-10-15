# Testing and privacy

Applies to every task that runs the app, the CLI against a device, or the integration tests.

- Physical devices are the maintainer's personal phones. **Do not mirror, screenshot, record, pull files from, or run
  integration tests against them.** Read-only metadata (`adbctl list devices`) is fine.
- Run integration tests and UI checks against an **emulator** (`adbctl emulator start Pixel_8 --wait`; stop it afterwards).
  `ADBHUB_TEST_SERIAL` must be an `emulator-*` serial.
- Before pressing "View Screen" (click, shortcut or `controller.start()`), verify the selected device is the emulator, e.g. by
  reading the window title via Accessibility. If unsure, stop.
- The compact window and canvas start mirroring on their own; after launching the app, check no physical device is being mirrored
  (`adb -s <serial> shell 'ps -A -o ARGS' < /dev/null | grep -c '[s]crcpy'` must be 0).
- Screenshots: capture only the app window (`screencapture -x -o -l <windowID>`), never the full screen (it can contain other
  private windows). Delete screenshots when done; never commit them.
- Never put device serials, account names, emails, project names or any content seen on a device or other apps into docs,
  commits, tests or issues.
- Quit the app and stop the emulator you started when finished.
