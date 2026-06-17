#!/bin/bash
# Downloads the Slicer tarball, computes SHA256, and patches org.slicer.Slicer.yml.
# Run this once before building the Flatpak.
set -euo pipefail

ITEM_ID="6911b598ac7b1c95e7934427"
VERSION="5.10.0"
FILENAME="Slicer-${VERSION}-linux-amd64.tar.gz"
URL="https://slicer-packages.kitware.com/api/v1/item/${ITEM_ID}/download"
MANIFEST="$(dirname "$0")/org.slicer.Slicer.yml"

echo "Downloading Slicer ${VERSION} Linux tarball (~414 MB)..."
wget --content-disposition -O "${FILENAME}" "${URL}"

echo "Computing SHA256..."
SHA256=$(sha256sum "${FILENAME}" | awk '{print $1}')
echo "SHA256: ${SHA256}"

echo "Patching manifest..."
sed -i "s|REPLACE_WITH_SHA256_SEE_COMMENT_ABOVE|${SHA256}|" "${MANIFEST}"

echo "Done. You can now build the Flatpak:"
echo "  flatpak-builder --force-clean build-dir ${MANIFEST}"
