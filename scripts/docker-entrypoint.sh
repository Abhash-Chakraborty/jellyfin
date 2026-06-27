#!/usr/bin/env sh
# Seed bundled plugins into the Jellyfin data directory on container start, then
# hand off to the Jellyfin server.
#
# The plugins folder lives under the persistent /config volume, so it cannot be
# baked into the image. Instead we stage the plugin in the image at
# /app/bundled-plugins and copy it into $JELLYFIN_DATA_DIR/plugins on first run
# (and whenever the image ships a new versioned folder).
#
# Plugin configuration is stored separately (keyed by plugin GUID, outside the
# plugin folder), so re-seeding never clobbers the admin's saved settings.
set -eu

DATA_DIR="${JELLYFIN_DATA_DIR:-/config}"
PLUGINS_DIR="${DATA_DIR}/plugins"
STAGE_DIR="/app/bundled-plugins"

if [ -d "$STAGE_DIR" ]; then
    for staged in "$STAGE_DIR"/*/; do
        # Guard against the no-match case (literal glob).
        [ -d "$staged" ] || continue

        name="$(basename "$staged")"
        target="${PLUGINS_DIR}/${name}"

        if [ ! -d "$target" ]; then
            echo "[entrypoint] Seeding bundled plugin: ${name}"
            mkdir -p "$target"
            cp -a "$staged". "$target"/
        else
            echo "[entrypoint] Bundled plugin already present: ${name}"
        fi
    done
fi

# Hand off to the actual Jellyfin command (passed as CMD / trailing args).
exec "$@"
