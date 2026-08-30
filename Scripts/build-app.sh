#!/bin/zsh

set -euo pipefail

configuration="${1:-debug}"
package_root="${0:A:h:h}"

cd "$package_root"
swift build --configuration "$configuration" --disable-sandbox
binary_path="$(swift build --configuration "$configuration" --show-bin-path --disable-sandbox)/Camelot"
app_path="$package_root/.build/Camelot.app"

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_path" "$app_path/Contents/MacOS/Camelot"
cp "$package_root/AppResources/Info.plist" "$app_path/Contents/Info.plist"

signing_identity="${CAMELOT_SIGNING_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
  signing_identity="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Apple Development:[^"]*\)"/\1/p' \
      | head -n 1
  )"
fi

if [[ -n "$signing_identity" ]]; then
  echo "Signing with: $signing_identity" >&2
  codesign \
    --force \
    --options runtime \
    --sign "$signing_identity" \
    --identifier com.keishingu.camelot \
    --timestamp=none \
    --entitlements "$package_root/AppResources/Camelot.entitlements" \
    "$app_path"
else
  echo "warning: Apple Development certificate unavailable; using ad-hoc signing." >&2
  echo "Accessibility permissions may need to be granted again after rebuilding." >&2
  codesign \
    --force \
    --sign - \
    --entitlements "$package_root/AppResources/Camelot.entitlements" \
    "$app_path"
fi

codesign --verify --deep --strict "$app_path"
print -r -- "$app_path"
