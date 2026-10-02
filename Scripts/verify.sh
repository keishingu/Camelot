#!/bin/bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "${script_directory}/.." && pwd)"
cd "${project_directory}"
swift test --disable-sandbox
bash -n Scripts/build-direct-release.sh Scripts/notarize-release.sh \
  Scripts/test-distribution.sh Scripts/verify.sh
Scripts/test-distribution.sh
