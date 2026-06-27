#!/usr/bin/env sh
# Patch Jellyfin Web to survive a null/undefined item|serverId being passed to
# getApiClient(). On some clients (observed on an Android tablet running the
# bundled Jellyfin Web and the official Jellyfin Android app) the app got stuck
# on the loading logo with:
#
#   Uncaught (in promise) Error: item or serverId cannot be null
#       at t.value (main.jellyfin.bundle.js)
#
# Instead of throwing, fall back to the first known ApiClient. We also cache-bust
# index.html so clients stop executing the previously cached main bundle.
#
# This runs during the Docker image build, after Jellyfin Web has been built.
# Override the web root with JELLYFIN_WEB_ROOT (defaults to /app/jellyfin-web).
set -eu

WEB_ROOT="${JELLYFIN_WEB_ROOT:-/app/jellyfin-web}"
MAIN="$WEB_ROOT/main.jellyfin.bundle.js"
APICLIENT="$WEB_ROOT/node_modules.jellyfin-apiclient.bundle.js"
INDEX="$WEB_ROOT/index.html"

echo "Patching Jellyfin Web at: $WEB_ROOT"

# Required files must exist or the build fails.
test -f "$MAIN"
test -f "$INDEX"

THROW='if(!e)throw new Error("item or serverId cannot be null");'
MAIN_REPLACEMENT='if(!e)return console.warn("getApiClient called with null in main bundle; using first client"),this._apiClients[0];'
APICLIENT_REPLACEMENT='if(!e)return console.warn("getApiClient called with null; using first client"),this._apiClients[0];'

# The main bundle must contain exactly one occurrence of the throw we expect.
MAIN_COUNT="$(grep -oF "$THROW" "$MAIN" | wc -l | tr -d ' ')"

if [ "$MAIN_COUNT" != "1" ]; then
  echo "Expected exactly 1 matching throw in $MAIN, found $MAIN_COUNT" >&2
  exit 1
fi

python3 - "$MAIN" "$THROW" "$MAIN_REPLACEMENT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
old = sys.argv[2]
new = sys.argv[3]

s = path.read_text(encoding="utf-8")
if s.count(old) != 1:
    raise SystemExit(f"Expected exactly 1 match in {path}, found {s.count(old)}")

path.write_text(s.replace(old, new), encoding="utf-8")
print(f"Patched {path}")
PY

# The apiclient bundle is patched only if present and it contains the same throw.
if [ -f "$APICLIENT" ]; then
  API_COUNT="$(grep -oF "$THROW" "$APICLIENT" | wc -l | tr -d ' ')"

  if [ "$API_COUNT" = "1" ]; then
    python3 - "$APICLIENT" "$THROW" "$APICLIENT_REPLACEMENT" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
old = sys.argv[2]
new = sys.argv[3]

s = path.read_text(encoding="utf-8")
if s.count(old) != 1:
    raise SystemExit(f"Expected exactly 1 match in {path}, found {s.count(old)}")

path.write_text(s.replace(old, new), encoding="utf-8")
print(f"Patched {path}")
PY
  else
    echo "Skipping $APICLIENT because match count is $API_COUNT"
  fi
else
  echo "Skipping $APICLIENT because it does not exist"
fi

# Cache-bust the main bundle reference in index.html so stale caches reload it.
python3 - "$INDEX" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
s = path.read_text(encoding="utf-8")

s2 = re.sub(
    r"main\.jellyfin\.bundle\.js\?[^\"'<> ]+",
    "main.jellyfin.bundle.js?patched-main-v2",
    s,
)

if s2 == s:
    raise SystemExit("No main.jellyfin.bundle.js reference changed in index.html")

path.write_text(s2, encoding="utf-8")
print(f"Patched {path}")
PY

# Inject the Abhash Themes loader so the served web client pulls custom CSS/JS
# from the plugin endpoint (/AbhashThemes/inject.js) on every load. This is
# applied at build time so it survives the upstream jellyfin-web mirror, and is
# idempotent + non-fatal: if the marker is already present or </body> is not
# found, we leave index.html untouched rather than failing the build.
python3 - "$INDEX" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
s = path.read_text(encoding="utf-8")

tag = '<script defer src="/AbhashThemes/inject.js"></script>'

if tag in s:
    print(f"Abhash Themes loader already present in {path}")
elif "</body>" in s:
    s = s.replace("</body>", f"    {tag}\n</body>", 1)
    path.write_text(s, encoding="utf-8")
    print(f"Injected Abhash Themes loader into {path}")
else:
    print(f"WARNING: no </body> found in {path}; skipped Abhash Themes loader", file=sys.stderr)
PY

# Verify the patch actually landed.
grep -q "getApiClient called with null in main bundle" "$MAIN"
grep -q "main.jellyfin.bundle.js?patched-main-v2" "$INDEX"

echo "Jellyfin Web patch verification passed."
