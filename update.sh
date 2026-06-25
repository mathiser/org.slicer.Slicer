#!/usr/bin/env bash
# update.sh — Bump org.slicer.Slicer to a new upstream release.
#
# Usage: ./update.sh <VERSION> <BITSTREAM_ID> [REVISION] [RELEASE_DATE]
#
#   VERSION        e.g. 5.10.0
#   BITSTREAM_ID   Kitware item ID for the Linux amd64 tarball
#   REVISION       Slicer internal revision number (auto-extracted from tarball if omitted)
#   RELEASE_DATE   e.g. 2025-11-10 (defaults to today)
#
# How to find BITSTREAM_ID
# ------------------------
# 1. Go to https://download.slicer.org
# 2. Open browser DevTools (F12) → Network tab
# 3. Click the Linux download button and watch for a redirect request
# 4. The URL will be: https://slicer-packages.kitware.com/api/v1/item/<ID>/download
# 5. Copy that hex <ID>
#
# Example:
#   ./update.sh 5.10.0 6911b598ac7b1c95e7934427

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERSION="${1:?Usage: $0 VERSION BITSTREAM_ID [REVISION] [RELEASE_DATE]}"
ITEM_ID="${2:?Usage: $0 VERSION BITSTREAM_ID [REVISION] [RELEASE_DATE]}"
REVISION="${3:-}"
RELEASE_DATE="${4:-$(date +%Y-%m-%d)}"

FILENAME="Slicer-${VERSION}-linux-amd64.tar.gz"
URL="https://slicer-packages.kitware.com/api/v1/item/${ITEM_ID}/download"
MANIFEST="${SCRIPT_DIR}/org.slicer.Slicer.yml"
METAINFO="${SCRIPT_DIR}/org.slicer.Slicer.metainfo.xml"
WRAPPER="${SCRIPT_DIR}/slicer.sh"

# ── 1. Download tarball ────────────────────────────────────────────────────
echo "==> Downloading Slicer ${VERSION} (~414 MB)..."
wget -O "${SCRIPT_DIR}/${FILENAME}" "${URL}"

# ── 2. Compute SHA256 ──────────────────────────────────────────────────────
echo "==> Computing SHA256..."
SHA256=$(sha256sum "${SCRIPT_DIR}/${FILENAME}" | awk '{print $1}')
echo "    ${SHA256}"

# ── 3. Extract revision from tarball (if not supplied) ────────────────────
if [ -z "${REVISION}" ]; then
    echo "==> Extracting revision number from tarball..."
    REVISION=$(tar -xOf "${SCRIPT_DIR}/${FILENAME}" \
        "Slicer-${VERSION}-linux-amd64/bin/SlicerLauncherSettings.ini" 2>/dev/null \
        | awk -F= '/^revision=/{print $2}' | tr -d '[:space:]') || true
    if [ -n "${REVISION}" ]; then
        echo "    Revision: ${REVISION}"
    else
        echo "    WARNING: Could not extract revision; slicer.sh fallback will not be updated"
    fi
fi

# ── 4. Patch manifest ─────────────────────────────────────────────────────
echo "==> Patching ${MANIFEST}..."

# Bitstream ID in URL
sed -i -E "s|/api/v1/item/[a-f0-9]+/download|/api/v1/item/${ITEM_ID}/download|g" "${MANIFEST}"

# dest-filename version number
sed -i -E "s|Slicer-[0-9.]+(-linux-amd64\.tar\.gz)|Slicer-${VERSION}\1|g" "${MANIFEST}"

# sha256 of the Slicer tarball (the line immediately after dest-filename)
sed -i -E "/dest-filename: Slicer-.*-linux-amd64\.tar\.gz/{n; s|sha256: [a-f0-9]+|sha256: ${SHA256}|}" "${MANIFEST}"

# Comment block: version and bitstream ID
sed -i -E "s|# Slicer [0-9.]+ — Linux amd64|# Slicer ${VERSION} — Linux amd64|" "${MANIFEST}"
sed -i -E "s|# Bitstream ID: [a-f0-9]+|# Bitstream ID: ${ITEM_ID}|" "${MANIFEST}"

# ── 5. Patch metainfo ─────────────────────────────────────────────────────
echo "==> Patching ${METAINFO}..."
python3 - "${METAINFO}" "${VERSION}" "${RELEASE_DATE}" <<'PYEOF'
import sys, re

path, version, date = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()

new_entry = (
    f'    <release version="{version}" date="{date}">\n'
    f'      <description>\n'
    f'        <p>Stable release of 3D Slicer {version}.</p>\n'
    f'      </description>\n'
    f'    </release>'
)

# Remove existing entry for this version if present (idempotent re-runs)
text = re.sub(
    rf'\s*<release version="{re.escape(version)}".*?</release>',
    '',
    text,
    flags=re.DOTALL,
)

# Prepend new release entry at the top of the <releases> block
text = re.sub(
    r'(<releases>\s*\n(?:\s*<!--[^>]*-->\s*\n)?)',
    r'\1' + new_entry + '\n',
    text,
)

open(path, 'w').write(text)
PYEOF

# ── 6. Update slicer.sh revision fallback ─────────────────────────────────
if [ -n "${REVISION}" ]; then
    echo "==> Updating slicer.sh revision fallback to ${REVISION}..."
    sed -i -E "s|REVISION=\"\\\$\{REVISION:-[0-9]+\}\"|REVISION=\"\${REVISION:-${REVISION}}\"|" "${WRAPPER}"
fi

echo ""
echo "All done. Review changes with: git diff"
echo ""
echo "Build and test:"
echo "  flatpak-builder --force-clean build-dir org.slicer.Slicer.yml"
echo "  flatpak-builder --run build-dir org.slicer.Slicer.yml slicer"
echo ""
echo "When satisfied, commit:"
echo "  git add org.slicer.Slicer.yml org.slicer.Slicer.metainfo.xml slicer.sh"
echo "  git commit -m \"Update to Slicer ${VERSION}\""
