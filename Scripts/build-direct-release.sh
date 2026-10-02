#!/bin/bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "${script_directory}/.." && pwd)"
release_directory="${CAMELOT_RELEASE_DIR:-${project_directory}/build/release}"
build_number="${BUILD_NUMBER:?error: BUILD_NUMBER is required}"
marketing_version="${MARKETING_VERSION:-0.1.0}"
signing_identity="${SIGNING_IDENTITY:?error: SIGNING_IDENTITY is required}"

[[ "${signing_identity}" == "Developer ID Application:"* ]] || {
  echo "error: SIGNING_IDENTITY must be a Developer ID Application identity" >&2
  exit 1
}
[[ "${build_number}" =~ ^[0-9]+$ ]] || {
  echo "error: BUILD_NUMBER must contain digits only" >&2
  exit 1
}
[[ "${marketing_version}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || {
  echo "error: MARKETING_VERSION must use numeric dot notation" >&2
  exit 1
}
[[ ! -e "${release_directory}" ]] || {
  echo "error: release output already exists: ${release_directory}" >&2
  exit 1
}

mkdir -p "$(dirname "${release_directory}")"
work_directory="$(mktemp -d "$(dirname "${release_directory}")/.camelot-release.XXXXXX")"
trap 'rm -rf "${work_directory}"' EXIT
app_path="${work_directory}/Camelot.app"
mkdir -p "${app_path}/Contents/MacOS" "${app_path}/Contents/Resources"

build_architecture() {
  local architecture="$1"
  local triple="${architecture}-apple-macosx26.0"
  local scratch_path="${work_directory}/${architecture}"
  swift build --package-path "${project_directory}" --configuration release \
    --scratch-path "${scratch_path}" --triple "${triple}" --product Camelot >&2 || return $?
  local bin_path
  bin_path="$(swift build --package-path "${project_directory}" --configuration release \
    --scratch-path "${scratch_path}" --triple "${triple}" --product Camelot \
    --show-bin-path | tail -n 1)" || return $?
  printf '%s\n' "${bin_path}"
}

arm64_bin_path="$(build_architecture arm64)"
x86_64_bin_path="$(build_architecture x86_64)"
lipo -create "${arm64_bin_path}/Camelot" "${x86_64_bin_path}/Camelot" \
  -output "${app_path}/Contents/MacOS/Camelot"
cp "${project_directory}/AppResources/Info.plist" "${app_path}/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "${marketing_version}" \
  "${app_path}/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${build_number}" \
  "${app_path}/Contents/Info.plist"
xcrun actool "${project_directory}/AppResources/Assets.xcassets" \
  --compile "${app_path}/Contents/Resources" --platform macosx \
  --minimum-deployment-target 26.0 --app-icon AppIcon \
  --output-partial-info-plist "${work_directory}/asset-info.plist"
[[ -f "${app_path}/Contents/Resources/AppIcon.icns" ]] || {
  echo "error: AppIcon was not included in the release app" >&2
  exit 1
}
architectures="$(lipo -archs "${app_path}/Contents/MacOS/Camelot")"
[[ " ${architectures} " == *" arm64 "* && " ${architectures} " == *" x86_64 "* ]] || {
  echo "error: release executable is not Universal: ${architectures}" >&2
  exit 1
}

codesign --force --sign "${signing_identity}" --identifier com.keishingu.camelot \
  --options runtime --entitlements "${project_directory}/AppResources/Camelot.entitlements" \
  --timestamp "${app_path}"
codesign --verify --deep --strict --verbose=2 "${app_path}"

mkdir "${work_directory}/dmg-root"
cp -R "${app_path}" "${work_directory}/dmg-root/Camelot.app"
ln -s /Applications "${work_directory}/dmg-root/Applications"
hdiutil create -volname Camelot -srcfolder "${work_directory}/dmg-root" \
  -fs HFS+ -format UDZO "${work_directory}/Camelot-macos-universal.dmg"
codesign --force --sign "${signing_identity}" --timestamp \
  "${work_directory}/Camelot-macos-universal.dmg"
codesign --verify --verbose=2 "${work_directory}/Camelot-macos-universal.dmg"
hdiutil verify "${work_directory}/Camelot-macos-universal.dmg"

mkdir "${release_directory}"
mv "${app_path}" "${work_directory}/Camelot-macos-universal.dmg" "${release_directory}/"
echo "Created ${release_directory}/Camelot-macos-universal.dmg (${architectures})"
