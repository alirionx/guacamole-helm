#!/bin/sh
# Downloads an extension JAR and verifies its SHA-256 checksum; the pod does not start on failure.
# Environment: URL, SHA256, FILE_NAME, TARGET (directory mounted as GUACAMOLE_HOME/extensions)
set -eu
partial="$TARGET/.download-$FILE_NAME"
trap 'rm -f "$partial"' EXIT
[ ! -e "$TARGET/$FILE_NAME" ] || { echo "[extension] ERROR: $FILE_NAME is provided by more than one extension" >&2; exit 1; }
echo "[extension] downloading $URL"
curl -fsSL --retry 3 --retry-delay 2 -o "$partial" "$URL"
echo "$SHA256  $partial" | sha256sum -c - >/dev/null 2>&1 || {
    echo "[extension] ERROR: checksum mismatch for $URL (expected $SHA256, got $(sha256sum "$partial" | cut -d' ' -f1))" >&2
    exit 1
}
mv "$partial" "$TARGET/$FILE_NAME"
echo "[extension] installed $FILE_NAME"
