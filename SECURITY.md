# Security policy

## Supported versions

Only the latest release (and `main`) receives security fixes.

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

- Use GitHub's private reporting: **Security → Report a vulnerability** on this repository, or
- email **mail@ledinhcuong.com** with a description, reproduction steps and the affected version.

You can expect an acknowledgement within a few days. Please allow reasonable time for a fix before public disclosure.

## Scope

In scope: command/argument injection into `adb shell` commands, unsafe file writes or deletes (path traversal, overwrite),
mishandling of the emulator console auth token, and integrity of the bundled scrcpy-server.
Out of scope: vulnerabilities in adb, scrcpy-server or Android itself (report those upstream), and anything that requires
an already-authorised, malicious debugging host.
