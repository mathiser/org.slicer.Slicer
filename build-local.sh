#!/usr/bin/env bash
# Build, check, and optionally bundle the Flatpak locally.
# Usage: ./build-local.sh [--bundle]
set -euo pipefail

MANIFEST="org.slicer.Slicer.yml"
APP_ID="org.slicer.Slicer"
BUILD_DIR="build-dir"
REPO="repo"

bundle=false
[[ "${1:-}" == "--bundle" ]] && bundle=true

# ── 1. Build ──────────────────────────────────────────────────────────────────
echo "==> Building..."
flatpak-builder --user --force-clean --repo="$REPO" --install "$BUILD_DIR" "$MANIFEST"

# ── 2. Check for missing libraries inside the sandbox ─────────────────────────
echo "==> Checking for missing libraries inside sandbox..."
# Most of Slicer's bundled libraries carry no RPATH and are only resolvable
# via the LD_LIBRARY_PATH the CTK launcher sets up at runtime (see
# SlicerLauncherSettings.ini). Reproduce that search path here so ldd checks
# against what the app actually sees, instead of flagging everything as
# unresolved. libqsqlodbc/libqsqlpsql (unused Qt SQL drivers) and Python's
# _crypt module are excluded: they need libpq/libodbc/libcrypt.so.1, which
# aren't bundled or in the runtime, but Slicer never loads them.
missing=$(flatpak run --command=bash "$APP_ID" -c '
  export LD_LIBRARY_PATH=$(find /app -type f -name "*.so*" -not -path "*/lib/debug/*" -exec dirname {} \; | sort -u | tr "\n" ":")
  find /app -type f \( -name "*.so" -o -name "*.so.*" -o -name "SlicerApp-real" \) \
    -not -path "*/sqldrivers/libqsqlodbc.so" \
    -not -path "*/sqldrivers/libqsqlpsql.so" \
    -not -path "*/lib-dynload/_crypt*.so" \
    2>/dev/null \
    | xargs ldd 2>/dev/null \
    | grep "not found" \
    | awk "{print \$1}" \
    | sort -u
')

if [ -n "$missing" ]; then
  echo "FAIL — missing libraries inside Flatpak sandbox:"
  echo "$missing"
  exit 1
fi
echo "OK — all libraries resolved inside sandbox."

# ── 3. Optional bundle export ──────────────────────────────────────────────────
if $bundle; then
  echo "==> Exporting bundle..."
  flatpak build-bundle "${HOME}/.local/share/flatpak/repo" "${APP_ID}.flatpak" "$APP_ID"
  echo "==> Bundle written to ${APP_ID}.flatpak"
fi

echo ""
echo "Done. Run with:"
echo "  flatpak run $APP_ID"
