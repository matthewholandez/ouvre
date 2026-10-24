#!/bin/zsh
set -euo pipefail
repo_dir="${0:A:h:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
output_dir="${1:-$repo_dir/.build/ui-review}"
mkdir -p "$output_dir"
cd "$repo_dir"
xcrun swiftc -parse-as-library Sources/OuvreCore/*.swift Sources/OuvreApp/AppModel.swift \
  Sources/OuvreApp/BrowserCatalog.swift Sources/OuvreApp/ProfileAccessStore.swift \
  Sources/OuvreApp/VerificationHooks.swift Sources/OuvreApp/Views.swift scripts/ui/Preview.swift \
  -o "$output_dir/capture"
"$output_dir/capture" "$output_dir" "${@:2}"
