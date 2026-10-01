#!/bin/bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/camelot-distribution-test.XXXXXX")"
trap 'rm -rf "${temporary_directory}"' EXIT
mock_bin="${temporary_directory}/bin"
mkdir -p "${mock_bin}" "${temporary_directory}/existing"
printf 'keep\n' > "${temporary_directory}/existing/sentinel"

cat > "${mock_bin}/swift" <<'STUB'
#!/bin/bash
scratch_path=
triple=
show_bin_path=0
while (($#)); do
  case "$1" in
    --scratch-path) scratch_path="$2"; shift 2 ;;
    --triple) triple="$2"; shift 2 ;;
    --show-bin-path) show_bin_path=1; shift ;;
    *) shift ;;
  esac
done
if [[ "${MOCK_SWIFT_FAIL:-0}" == 1 ]]; then
  echo "noisy mocked Swift failure" >&2
  exit 42
fi
bin_path="${scratch_path}/${triple}/release"
if ((show_bin_path)); then
  echo "${bin_path}"
else
  echo "noisy mocked Swift build log for ${triple}"
  mkdir -p "${bin_path}"
  touch "${bin_path}/Camelot"
fi
STUB
cat > "${mock_bin}/lipo" <<'STUB'
#!/bin/bash
if [[ "$1" == -archs ]]; then
  echo 'arm64 x86_64'
  exit 0
fi
input_one="$2"
input_two="$3"
while (($#)); do
  if [[ "$1" == -output ]]; then output="$2"; break; fi
  shift
done
[[ -f "${input_one}" && -f "${input_two}" ]] || { echo 'lipo received an invalid input path' >&2; exit 2; }
touch "${output}"
STUB
cat > "${mock_bin}/plutil" <<'STUB'
#!/bin/bash
if [[ "$1" == -extract ]]; then
  printf '%s\n' "${MOCK_NOTARY_STATUS:-Rejected}"
fi
STUB
cat > "${mock_bin}/xcrun" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${MOCK_TOOL_LOG}"
if [[ "$1" == actool ]]; then
  while (($#)); do
    if [[ "$1" == --compile ]]; then resource_path="$2"; break; fi
    shift
  done
  mkdir -p "${resource_path}"
  touch "${resource_path}/AppIcon.icns"
elif [[ "$1" == notarytool ]]; then
  printf '{"status":"%s"}\n' "${MOCK_NOTARY_STATUS:-Rejected}"
fi
STUB
cat > "${mock_bin}/codesign" <<'STUB'
#!/bin/bash
printf 'codesign %s\n' "$*" >> "${MOCK_TOOL_LOG}"
STUB
cat > "${mock_bin}/hdiutil" <<'STUB'
#!/bin/bash
printf 'hdiutil %s\n' "$*" >> "${MOCK_TOOL_LOG}"
if [[ "$1" == create ]]; then
  for argument in "$@"; do output="$argument"; done
  touch "${output}"
fi
STUB
cat > "${mock_bin}/spctl" <<'STUB'
#!/bin/bash
printf 'spctl %s\n' "$*" >> "${MOCK_TOOL_LOG}"
STUB
chmod +x "${mock_bin}"/*
export PATH="${mock_bin}:${PATH}"
export MOCK_TOOL_LOG="${temporary_directory}/tools.log"
: > "${MOCK_TOOL_LOG}"

if BUILD_NUMBER=1 MARKETING_VERSION=0.1.0 \
  SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)' \
  CAMELOT_RELEASE_DIR="${temporary_directory}/existing" \
  "${script_directory}/build-direct-release.sh" >/dev/null 2>&1; then
  echo "error: build accepted an existing release directory" >&2
  exit 1
fi
[[ "$(cat "${temporary_directory}/existing/sentinel")" == keep ]]
[[ ! -s "${MOCK_TOOL_LOG}" ]]

if BUILD_NUMBER=1 MARKETING_VERSION=invalid \
  SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)' \
  CAMELOT_RELEASE_DIR="${temporary_directory}/invalid" \
  "${script_directory}/build-direct-release.sh" >/dev/null 2>&1; then
  echo "error: build accepted an invalid marketing version" >&2
  exit 1
fi
[[ ! -e "${temporary_directory}/invalid" ]]

if MOCK_SWIFT_FAIL=1 BUILD_NUMBER=1 MARKETING_VERSION=0.1.0 \
  SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)' \
  CAMELOT_RELEASE_DIR="${temporary_directory}/failed" \
  "${script_directory}/build-direct-release.sh" >/dev/null 2>&1; then
  echo "error: build ignored a Swift compiler failure" >&2
  exit 1
fi
[[ ! -e "${temporary_directory}/failed" ]]
! grep -q '^codesign ' "${MOCK_TOOL_LOG}"

BUILD_NUMBER=1 MARKETING_VERSION=0.1.0 \
  SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)' \
  CAMELOT_RELEASE_DIR="${temporary_directory}/release" \
  "${script_directory}/build-direct-release.sh" >/dev/null 2>&1
[[ -d "${temporary_directory}/release/Camelot.app" ]]
[[ -f "${temporary_directory}/release/Camelot-macos-universal.dmg" ]]

touch "${temporary_directory}/key.p8"
if MOCK_NOTARY_STATUS=Rejected \
  CAMELOT_RELEASE_DIR="${temporary_directory}/release" \
  NOTARY_KEY_PATH="${temporary_directory}/key.p8" \
  APP_STORE_CONNECT_KEY_ID=mock-key APP_STORE_CONNECT_ISSUER_ID=mock-issuer \
  "${script_directory}/notarize-release.sh" >/dev/null 2>&1; then
  echo "error: notarization rejection was treated as success" >&2
  exit 1
fi
[[ ! -e "${temporary_directory}/release/Camelot-macos-universal.dmg.sha256" ]]
! grep -Eq 'stapler|spctl' "${MOCK_TOOL_LOG}"

MOCK_NOTARY_STATUS=Accepted CAMELOT_RELEASE_DIR="${temporary_directory}/release" \
  NOTARY_KEY_PATH="${temporary_directory}/key.p8" \
  APP_STORE_CONNECT_KEY_ID=mock-key APP_STORE_CONNECT_ISSUER_ID=mock-issuer \
  "${script_directory}/notarize-release.sh" >/dev/null
checksum="${temporary_directory}/release/Camelot-macos-universal.dmg.sha256"
[[ "$(awk '{print $2}' "${checksum}")" == Camelot-macos-universal.dmg ]]
(cd "${temporary_directory}/release" && shasum -a 256 -c "$(basename "${checksum}")") >/dev/null
echo "Distribution mock checks passed"
