#!/bin/sh
# znnd bootstrap from a community snapshot (e.g. Digital Ocean Spaces).
#
# Skips silently if /data/nom already exists, unless FORCE_BOOTSTRAP=true.
# Skips silently if BOOTSTRAP_URL is unset (lets users opt out of bootstrap).
#
# Resumable: cache lives at /data/.bootstrap-cache and is only removed on
# successful install. wget -c resumes partial downloads on retry. Corrupt
# zips (checksum or unzip failure) are deleted so the next run redownloads.
#
# Expects the snapshot zip to contain backup/{nom.bak,network.bak,consensus.bak}/
# Sibling .hash URL must contain the sha256 of the zip.

set -eu

DATA_DIR=/data
CACHE_DIR="$DATA_DIR/.bootstrap-cache"

if [ -d "$DATA_DIR/nom" ] && [ "${FORCE_BOOTSTRAP:-false}" != "true" ]; then
    echo "[znnd-bootstrap] $DATA_DIR/nom exists -- skipping. Set FORCE_BOOTSTRAP=true to override."
    exit 0
fi

if [ -z "${BOOTSTRAP_URL:-}" ]; then
    echo "[znnd-bootstrap] BOOTSTRAP_URL not set -- skipping. znnd will sync from genesis."
    exit 0
fi

echo "[znnd-bootstrap] Bootstrapping from $BOOTSTRAP_URL"

zip_name=$(basename "$BOOTSTRAP_URL")
hash_url="${BOOTSTRAP_URL%.*}.hash"
hash_name=$(basename "$hash_url")

mkdir -p "$CACHE_DIR"
cd "$CACHE_DIR"

echo "[znnd-bootstrap] Downloading (resumes if partial)..."
wget -q --show-progress -c -O "$zip_name" "$BOOTSTRAP_URL"
wget -q -O "$hash_name" "$hash_url"

downloaded_hash=$(sha256sum "$zip_name" | awk '{print $1}')
expected_hash=$(awk '{print $1}' "$hash_name")

if [ "$downloaded_hash" != "$expected_hash" ]; then
    echo "[znnd-bootstrap] Checksum mismatch -- removing corrupt zip; rerun to retry."
    echo "  got:      $downloaded_hash"
    echo "  expected: $expected_hash"
    rm -f "$zip_name"
    exit 1
fi
echo "[znnd-bootstrap] Checksum verified."

echo "[znnd-bootstrap] Extracting..."
if ! unzip -q -o "$zip_name"; then
    echo "[znnd-bootstrap] Extract failed -- removing corrupt zip; rerun to retry."
    rm -f "$zip_name"
    exit 1
fi

if [ ! -d backup ]; then
    echo "[znnd-bootstrap] Zip did not contain expected backup/ subdir; aborting."
    exit 1
fi

# Move any pre-existing live data aside (force-bootstrap case).
suffix=$(date +%Y%m%d%H%M%S)
for d in nom network consensus; do
    if [ -d "$DATA_DIR/$d" ]; then
        mv "$DATA_DIR/$d" "$DATA_DIR/${d}_$suffix"
        echo "[znnd-bootstrap] $DATA_DIR/$d -> $DATA_DIR/${d}_$suffix"
    fi
done

# Promote the snapshot's .bak dirs to their canonical names.
for d in nom network consensus; do
    if [ -d "backup/$d.bak" ]; then
        mv "backup/$d.bak" "$DATA_DIR/$d"
        echo "[znnd-bootstrap] Installed $DATA_DIR/$d"
    else
        echo "[znnd-bootstrap] WARNING: backup/$d.bak missing from zip"
    fi
done

# Cache cleanup only on full success.
cd "$DATA_DIR"
rm -rf "$CACHE_DIR"

echo "[znnd-bootstrap] Done."
