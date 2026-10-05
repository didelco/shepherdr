#!/bin/bash
set -euo pipefail

tag="${1:?Usage: scripts/package-release.sh vMAJOR.MINOR.PATCH}"
if [[ ! "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Expected a stable version tag such as v0.1.0." >&2
    exit 1
fi
version="${tag#v}"
build_number="${GITHUB_RUN_NUMBER:-1}"
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "Build number must be a positive integer." >&2
    exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
mkdir -p build dist
asset="Shepherdr-${version}-macos-arm64"
for extension in zip dmg; do
    if [[ -e "dist/$asset.$extension" ]]; then
        echo "Refusing to overwrite dist/$asset.$extension." >&2
        exit 1
    fi
done
work_dir="$(mktemp -d "$repo_root/build/package.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

xcodebuild -project Shepherdr.xcodeproj -scheme Shepherdr \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$work_dir/DerivedData" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=14.0 \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGNING_ALLOWED=NO build

app="$work_dir/DerivedData/Build/Products/Release/Shepherdr.app"
binary="$app/Contents/MacOS/Shepherdr"
plist="$app/Contents/Info.plist"
[[ "$(xcrun lipo -archs "$binary")" == arm64 ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "$version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")" == "$build_number" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")" == 14.0 ]]

mkdir -p "$app/Contents/Resources"
cp LICENSE "$app/Contents/Resources/LICENSE"
# Keep the terminal renderer's MIT notices in every downloadable app, independently
# of SwiftPM's platform-specific resource bundle layout.
cp Sources/ShepherdrTerminalUI/Resources/SwiftTerm-LICENSE "$app/Contents/Resources/SwiftTerm-LICENSE"
# The bundled Fira Code fonts are distributed under the SIL Open Font License.
cp Sources/ShepherdrTerminalUI/Resources/Fonts/FiraCode-OFL.txt "$app/Contents/Resources/FiraCode-OFL.txt"
# An ad hoc signature makes the arm64 bundle valid, but does not confer Developer ID trust.
codesign --force --sign - --options runtime --timestamp=none "$app"
codesign --verify --deep --strict --verbose=2 "$app"

ditto -c -k --sequesterRsrc --keepParent "$app" "dist/$asset.zip"
mkdir "$work_dir/unpacked"
ditto -x -k "dist/$asset.zip" "$work_dir/unpacked"
codesign --verify --deep --strict --verbose=2 "$work_dir/unpacked/Shepherdr.app"
cmp "$binary" "$work_dir/unpacked/Shepherdr.app/Contents/MacOS/Shepherdr"
cmp Sources/ShepherdrTerminalUI/Resources/SwiftTerm-LICENSE "$work_dir/unpacked/Shepherdr.app/Contents/Resources/SwiftTerm-LICENSE"

mkdir "$work_dir/dmg"
ditto "$app" "$work_dir/dmg/Shepherdr.app"
ln -s /Applications "$work_dir/dmg/Applications"
cp docs/INSTALL.txt "$work_dir/dmg/Install Shepherdr.txt"
hdiutil create -volname Shepherdr -srcfolder "$work_dir/dmg" \
    -format UDZO "dist/$asset.dmg"
hdiutil verify "dist/$asset.dmg"

cd dist
shasum -a 256 "$asset.dmg" "$asset.zip" > SHA256SUMS
shasum -a 256 -c SHA256SUMS
echo "Release packages are ready in $repo_root/dist"
