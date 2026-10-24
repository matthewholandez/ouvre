#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
derived_dir="$repo_dir/.build/DerivedData"
output_dir="$repo_dir/dist"

DEVELOPER_DIR="$developer_dir" xcodebuild \
  -project "$repo_dir/Ouvre.xcodeproj" \
  -scheme Ouvre \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_dir" \
  CODE_SIGNING_ALLOWED=NO \
  build

mkdir -p "$output_dir"
ditto "$derived_dir/Build/Products/Release/Ouvre.app" "$output_dir/Ouvre.app"
codesign --force --deep --sign - "$output_dir/Ouvre.app"
print "Built $output_dir/Ouvre.app"
