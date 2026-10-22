#!/bin/sh
# Aborts if the persisted data was created by a different PostgreSQL major version than the image.
set -eu
[ -f "$PGDATA/PG_VERSION" ] || { echo "[version-check] no existing data, initializing on first start"; exit 0; }
data_version="$(cat "$PGDATA/PG_VERSION")"
image_version="$(postgres --version | sed -E 's/.* ([0-9]+)(\.[0-9]+)*.*/\1/')"
if [ "$data_version" != "$image_version" ]; then
    echo "[version-check] ERROR: the data in $PGDATA was created by PostgreSQL $data_version, but the image" >&2
    echo "runs PostgreSQL $image_version. Major versions are not compatible. Either keep the image at major" >&2
    echo "version $data_version or migrate the data with dump/restore (see the chart README)." >&2
    exit 1
fi
echo "[version-check] data version $data_version matches the image"
