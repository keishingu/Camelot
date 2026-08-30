#!/bin/zsh

set -euo pipefail

configuration="${1:-debug}"
signing_identity="${CAMELOT_SIGNING_IDENTITY:--}"
package_root="${0:A:h:h}"

cd "$package_root"
swift build --configuration "$configuration" --disable-sandbox
binary_path="$(swift build --configuration "$configuration" --show-bin-path --disable-sandbox)/Camelot"
app_path="$package_root/.build/Camelot.app"

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_path" "$app_path/Contents/MacOS/Camelot"
cp "$package_root/AppResources/Info.plist" "$app_path/Contents/Info.plist"

codesign \
  --force \
  --sign "$signing_identity" \
  --entitlements "$package_root/AppResources/Camelot.entitlements" \
  "$app_path"

codesign --verify --deep --strict "$app_path"
print -r -- "$app_path"
