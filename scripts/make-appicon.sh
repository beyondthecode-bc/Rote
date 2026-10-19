#!/usr/bin/env bash
# Builds Rote/Assets.xcassets/AppIcon.appiconset from images/logo.png (1024x1024).
set -euo pipefail
SRC="${1:-images/logo.png}"
# A path given on the command line is relative to the caller; the default is relative to the repo root.
if [[ $# -gt 0 && "$SRC" != /* ]]; then SRC="$PWD/$SRC"; fi
cd "$(dirname "$0")/.."
# sips only warns and exits 0 for a missing or unreadable source, so check it first.
[[ -f "$SRC" ]] || { echo "error: $SRC not found" >&2; exit 1; }
[[ "$(sips -g pixelWidth -g pixelHeight "$SRC" 2>/dev/null | awk '/pixelWidth:/ {w=$2} /pixelHeight:/ {h=$2} END {print w "x" h}')" == 1024x1024 ]] \
  || { echo "error: $SRC is not a 1024x1024 image" >&2; exit 1; }
OUT="Rote/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$OUT"
for pt in 16 32 128 256 512; do
  for scale in 1 2; do
    px=$((pt * scale))
    sips -z "$px" "$px" "$SRC" --out "$OUT/icon_${pt}x${pt}@${scale}x.png" >/dev/null
  done
done
cat > "$OUT/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "icon_16x16@1x.png",   "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32@1x.png",   "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128@1x.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256@1x.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512@1x.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF
echo "AppIcon written to $OUT"
