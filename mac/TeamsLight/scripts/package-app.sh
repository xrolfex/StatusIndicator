#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
project_path="${project_dir}/TeamsLight.xcodeproj"
scheme="TeamsLight Production"
archive_path="${project_dir}/.build/TeamsLight.xcarchive"
output_dir="${project_dir}/.build/TeamsLight.app"
archived_app="${archive_path}/Products/Applications/TeamsLight.app"

mkdir -p "${project_dir}/.build"
rm -rf "$archive_path" "$output_dir"

xcodebuild \
  -project "$project_path" \
  -scheme "$scheme" \
  -destination "generic/platform=macOS" \
  -archivePath "$archive_path" \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  archive

if [[ -n "${TEAMSLIGHT_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$TEAMSLIGHT_SIGNING_IDENTITY" "$archived_app"
  codesign --verify --deep --strict "$archived_app"
  echo "Signed $archived_app"
else
  echo "Created unsigned $archived_app"
  echo "Set TEAMSLIGHT_SIGNING_IDENTITY to a Developer ID Application identity to sign it."
fi

ditto "$archived_app" "$output_dir"
echo "Archive: $archive_path"
echo "Application: $output_dir"
