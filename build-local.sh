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
missing=$(flatpak run --command=bash "$APP_ID" -c "
  find /app -type f \( -name '*.so' -o -name '*.so.*' -o -name 'SlicerApp-real' \) 2>/dev/null \
    | xargs ldd 2>/dev/null \
    | grep 'not found' \
    | awk '{print \$1}' \
    | sort -u
")

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
