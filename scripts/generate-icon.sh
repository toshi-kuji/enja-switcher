#!/bin/bash
# generate-icon.sh - Generate AppIcon.icns from AppIcon.svg
#
# Uses a built-in Swift SVG renderer (scripts/svg2png.swift) that preserves
# transparency. Falls back to rsvg-convert if available.
#
# Usage: ./scripts/generate-icon.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SVG_FILE="$PROJECT_DIR/AppIcon.svg"
ICONSET_DIR="$PROJECT_DIR/AppIcon.iconset"
ICNS_FILE="$PROJECT_DIR/AppIcon.icns"
SVG2PNG_SWIFT="$SCRIPT_DIR/svg2png.swift"
SVG2PNG_BIN="/tmp/svg2png_enja"

if [ ! -f "$SVG_FILE" ]; then
  echo "Error: $SVG_FILE not found"
  exit 1
fi

# Determine SVG-to-PNG converter
if command -v rsvg-convert &>/dev/null; then
  CONVERTER="rsvg-convert"
elif [ -f "$SVG2PNG_SWIFT" ]; then
  # Build the Swift converter if needed
  if [ ! -f "$SVG2PNG_BIN" ] || [ "$SVG2PNG_SWIFT" -nt "$SVG2PNG_BIN" ]; then
    echo "Building svg2png tool..."
    swiftc -O -o "$SVG2PNG_BIN" "$SVG2PNG_SWIFT" -framework Cocoa
  fi
  CONVERTER="svg2png"
else
  echo "Error: No SVG converter found."
  echo "Install librsvg (brew install librsvg) or ensure scripts/svg2png.swift exists."
  exit 1
fi

echo "Using converter: $CONVERTER"

# Create iconset directory
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Required icon sizes for macOS .iconset
SIZES=(
  "icon_16x16 16"
  "icon_16x16@2x 32"
  "icon_32x32 32"
  "icon_32x32@2x 64"
  "icon_128x128 128"
  "icon_128x128@2x 256"
  "icon_256x256 256"
  "icon_256x256@2x 512"
  "icon_512x512 512"
  "icon_512x512@2x 1024"
)

# Generate PNGs at each required size
for entry in "${SIZES[@]}"; do
  name="${entry%% *}"
  size="${entry##* }"
  output="$ICONSET_DIR/${name}.png"

  if [ "$CONVERTER" = "rsvg-convert" ]; then
    rsvg-convert -w "$size" -h "$size" "$SVG_FILE" -o "$output"
  else
    "$SVG2PNG_BIN" "$SVG_FILE" "$output" "$size" 2>/dev/null
  fi

  echo "  Generated: ${name}.png (${size}x${size})"
done

# Convert iconset to icns
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"
echo "Created: $ICNS_FILE"

# Clean up iconset directory
rm -rf "$ICONSET_DIR"

echo "Done! AppIcon.icns has been regenerated."
echo ""
echo "Next steps:"
echo "  1. Verify the icon: open $ICNS_FILE"
echo "  2. Rebuild the app (see README)"
