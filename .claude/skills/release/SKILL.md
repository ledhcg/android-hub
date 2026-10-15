---
name: release
description: Prepare and cut a release (version, changelog, build, checks, tag). Only when the maintainer explicitly asks for a release; never publish or push tags on your own.
---

# Release

Do not run this unprompted. Pushing tags, creating GitHub releases and making the repo public are the maintainer's decisions —
prepare everything locally, then stop and ask before any outward-facing step.

1. Clean tree on `main`, up to date. `scripts/fetch-scrcpy-server.sh`, `swift build`, `swift test` all green. CI is green.
2. `gitleaks dir . --no-banner` and `gitleaks git . --no-banner`: no leaks.
3. Bump `VERSION`; move `CHANGELOG.md` *Unreleased* into a dated version section; make sure `ROADMAP.md` matches reality.
4. `scripts/build-app.sh release`: check `Info.plist` version/bundle ID, icon, `codesign -v`.
5. Distribution (ask first; needs the maintainer's Apple Developer account): Developer ID signing, notarization, DMG, checksum file.
   Ad-hoc builds only run on the machine that built them — say so in the release notes.
6. Commit "Release vX.Y.Z", then **ask** before tagging (`git tag vX.Y.Z`), pushing, or creating a GitHub release.
7. Release notes: highlights from the changelog, requirements (macOS 15+, platform-tools), known limitations, checksums.
