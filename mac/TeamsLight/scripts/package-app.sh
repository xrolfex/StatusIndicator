#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
output_dir="${project_dir}/.build/TeamsLight.app"

cd "$project_dir"
swift build -c release
rm -rf "$output_dir"
mkdir -p "$output_dir/Contents/MacOS"
cp "$project_dir/.build/release/TeamsLight" "$output_dir/Contents/MacOS/TeamsLight"
cp "$project_dir/Resources/Info.plist" "$output_dir/Contents/Info.plist"

if [[ -n "${TEAMSLIGHT_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$TEAMSLIGHT_SIGNING_IDENTITY" "$output_dir"
  echo "Signed $output_dir"
else
  echo "Created unsigned $output_dir"
  echo "Set TEAMSLIGHT_SIGNING_IDENTITY to a Developer ID Application identity to sign it."
fi
