#!/bin/sh
# Copies the extension JARs of an extension image into GUACAMOLE_HOME/extensions.
# Environment: SOURCE (directory in the image), TARGET (directory mounted as GUACAMOLE_HOME/extensions)
set -eu
found=0
for jar in "$SOURCE"/*.jar; do
    [ -f "$jar" ] || continue
    name="$(basename "$jar")"
    [ ! -e "$TARGET/$name" ] || { echo "[extension] ERROR: $name is provided by more than one extension" >&2; exit 1; }
    cp "$jar" "$TARGET/$name"
    echo "[extension] installed $name"
    found=1
done
[ "$found" = 1 ] || { echo "[extension] ERROR: no *.jar found in $SOURCE" >&2; exit 1; }
