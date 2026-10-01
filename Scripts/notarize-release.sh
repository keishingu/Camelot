#!/bin/bash
set -euo pipefail

release_directory="${CAMELOT_RELEASE_DIR:-build/release}"
disk_image_path="${release_directory}/Camelot-macos-universal.dmg"
key_path="${NOTARY_KEY_PATH:?error: NOTARY_KEY_PATH is required}"
key_id="${APP_STORE_CONNECT_KEY_ID:?error: APP_STORE_CONNECT_KEY_ID is required}"
issuer_id="${APP_STORE_CONNECT_ISSUER_ID:?error: APP_STORE_CONNECT_ISSUER_ID is required}"
[[ -f "${disk_image_path}" && -f "${key_path}" ]] || {
  echo "error: DMG or notary API key file is missing" >&2
  exit 1
}
[[ ! -e "${disk_image_path}.sha256" ]] || {
  echo "error: checksum already exists; refusing to overwrite release output" >&2
  exit 1
}

result_path="$(mktemp "${TMPDIR:-/tmp}/camelot-notary.XXXXXX")"
trap 'rm -f "${result_path}"' EXIT
xcrun notarytool submit "${disk_image_path}" --key "${key_path}" \
  --key-id "${key_id}" --issuer "${issuer_id}" --wait --timeout 30m \
  --output-format json > "${result_path}"
status="$(plutil -extract status raw -o - "${result_path}")"
[[ "${status}" == "Accepted" ]] || {
  echo "error: Apple notarization was not accepted: ${status}" >&2
  exit 1
}
xcrun stapler staple "${disk_image_path}"
xcrun stapler validate "${disk_image_path}"
codesign --verify --verbose=2 "${disk_image_path}"
hdiutil verify "${disk_image_path}"
spctl --assess --type open --context context:primary-signature --verbose=4 "${disk_image_path}"
(
  cd "${release_directory}"
  shasum -a 256 "$(basename "${disk_image_path}")" > "$(basename "${disk_image_path}").sha256"
  shasum -a 256 -c "$(basename "${disk_image_path}").sha256"
)
echo "Notarized and verified ${disk_image_path}"
