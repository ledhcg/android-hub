#!/bin/bash
# Downloads the pinned scrcpy-server and verifies its SHA-256 before it is bundled into ScrcpyKit.
#   scripts/fetch-scrcpy-server.sh
#
# The version here MUST match `ScrcpyServer.version` in Sources/ScrcpyKit/ScrcpySession.swift and the
# resource name in Package.swift. To upgrade scrcpy: change VERSION + SHA256 below, then follow the
# "Upgrading scrcpy-server" steps in CONTRIBUTING.md (the control protocol is not stable between releases).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="3.3.4"
SHA256="8588238c9a5a00aa542906b6ec7e6d5541d9ffb9b5d0f6e1bc0e365e2303079e"
URL="https://github.com/Genymobile/scrcpy/releases/download/v${VERSION}/scrcpy-server-v${VERSION}"
DEST="Sources/ScrcpyKit/Resources/scrcpy-server-${VERSION}.jar"

sha_of() { shasum -a 256 "$1" | awk '{print $1}'; }

if [[ -f "$DEST" && "$(sha_of "$DEST")" == "$SHA256" ]]; then
    echo "scrcpy-server ${VERSION} already present and verified."
    exit 0
fi

mkdir -p "$(dirname "$DEST")"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "Downloading scrcpy-server ${VERSION} from ${URL}"
curl --fail --silent --show-error --location --output "$TMP" "$URL"

ACTUAL="$(sha_of "$TMP")"
if [[ "$ACTUAL" != "$SHA256" ]]; then
    echo "error: SHA-256 mismatch for scrcpy-server ${VERSION}" >&2
    echo "  expected: ${SHA256}" >&2
    echo "  actual:   ${ACTUAL}" >&2
    exit 1
fi

mv "$TMP" "$DEST"
trap - EXIT
echo "Verified and installed ${DEST}"
