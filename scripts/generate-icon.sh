#!/bin/bash
# generate-icon.sh - Generate AppIcon.icns from AppIcon.svg
#
# Requires macOS with one of:
#   - rsvg-convert (brew install librsvg)  [recommended]
#   - qlmanage (built-in, but lower quality for SVG)
#
# Usage: ./scripts/generate-icon.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SVG_FILE="$PROJECT_DIR/AppIcon.svg"
ICONSET_DIR="$PROJECT_DIR/AppIcon.iconset"
ICNS_FILE="$PROJECT_DIR/AppIcon.icns"

if [ ! -f "$SVG_FILE" ]; then
  echo "Error: $SVG_FILE not found"
  exit 1
fi

# Determine SVG-to-PNG converter
if command -v rsvg-convert &>/dev/null; then
  CONVERTER="rsvg-convert"
elif command -v qlmanage &>/dev/null; then
  CONVERTER="qlmanage"
else
  echo "Error: No SVG converter found."
  echo "Install librsvg: brew install librsvg"
  exit 1
fi

echo "Using converter: $CONVERTER"

# Create iconset directory
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

# Required icon sizes for macOS .iconset
# Format: filename size
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
    # qlmanage: render at largest size then resize with sips
    TMPFILE="$(mktemp /tmp/icon_XXXXXX.png)"
    qlmanage -t -s 1024 -o /tmp "$SVG_FILE" &>/dev/null
    QLOUT="/tmp/$(basename "$SVG_FILE").png"
    if [ -f "$QLOUT" ]; then
      cp "$QLOUT" "$TMPFILE"
      rm "$QLOUT"
    else
      echo "Error: qlmanage failed to render SVG"
      rm -f "$TMPFILE"
      exit 1
    fi
    sips -z "$size" "$size" "$TMPFILE" --out "$output" &>/dev/null
    rm -f "$TMPFILE"
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
