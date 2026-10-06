#!/bin/bash
# Regenerates Shepherdr's pixel art from docs/assets/source: the app icon (and its icon set), the
# README header and the social preview. Every color comes from App/Theme.swift (see pixelate.swift).
#
#   icon      206×206 art pixels: 4 px each in the 1024-pixel icon, 1 px at 256
#   header    480×270 art pixels at 3 px: shown 720 points wide in the README, 3 px each on Retina
#   preview   the header at 2 px, centered on GitHub's 1280×640 social preview
#
# The header's masks and cleaned art come from scripts/make-header-masks.py (Python, only needed when
# the hand-made regions in docs/assets/source/header/regions.json change).
set -euo pipefail
cd "$(dirname "$0")/.."
source=docs/assets/source/header

# The header's sheep, title and code stay in the console's phosphor greens; the dog takes the logo's
# amber coat, the tongue the terminal's pinks; outlines become single lines, brown around the dog.
phosphor=070B09,090C0A,0E1310,141B17,1F2B25,0B3F25,0F5C35,15603C,217A4E,1FA463,2E9E66,36D985,4DFFA0,7CFFB8,8CFFC2,A6E8C4,F2FFF7
coat=070B09,1A1208,3E2A0F,5A3E16,7A5620,A16F27,C98A2E,FFB547,FFC978,FFDEA6
tongue=FF5F57,FF8A80,FFA99F,FFC3BB
header=(--cells 480x270 --only "$phosphor"
    --region "$source/dog-mask.png" --region-only "$coat" --region-coverage 0.4
    --region "$source/tongue-mask.png" --region-only "$tongue"
    --region "$source/green-outline-mask.png" --region-only 4DFFA0 --region-coverage 0.35
    --region "$source/dog-outline-mask.png" --region-only A16F27 --region-coverage 0.35
    --despeckle "$source/dog-mask.png" --touchup "$source/touchups.txt")

# The icon keeps the logo's palette without the in-between shades the header's dog needs.
swift scripts/pixelate.swift docs/assets/source/icon.png docs/assets/icon.png --cells 206x206 --scale 1 \
    --except A16F27,FFC978,FFDEA6,FFA99F,FFC3BB
swift scripts/make-icon.swift docs/assets/icon.png App/Assets.xcassets/AppIcon.appiconset
swift scripts/pixelate.swift "$source/clean.png" docs/assets/header.png --scale 3 "${header[@]}"
swift scripts/pixelate.swift "$source/clean.png" docs/assets/social-preview.png --scale 2 "${header[@]}" \
    --canvas 1280x640 --background 090C0A
