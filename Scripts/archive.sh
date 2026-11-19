#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Archives the iOS app (with the embedded Watch app) and exports it for App Store Connect.
#
#   Scripts/archive.sh [build-number]             signed archive + export to build/export
#   Scripts/archive.sh --unsigned [build-number]  unsigned archive only (dry run, no export)
#
# The build number defaults to the current date and time (YYYYMMDDHHMM). The version
# (MARKETING_VERSION) comes from Config/Base.xcconfig. Signing is automatic with the team
# in Config/Local.xcconfig; the exported .ipa is uploaded separately (Xcode Organizer or
# Transporter).

set -euo pipefail

usage() {
    echo "usage: Scripts/archive.sh [--unsigned] [build-number]"
}

unsigned=0
build_number=""
for argument in "$@"; do
    case "$argument" in
        --unsigned) unsigned=1 ;;
        -h | --help) usage; exit 0 ;;
        -*) usage >&2; exit 64 ;;
        *)
            if [ -n "$build_number" ]; then usage >&2; exit 64; fi
            build_number="$argument"
            ;;
    esac
done
build_number="${build_number:-$(date +%Y%m%d%H%M)}"

if ! [[ "$build_number" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "archive.sh: the build number must be one to three period-separated integers, got '$build_number'" >&2
    exit 64
fi

cd "$(dirname "$0")/.."

archive_path="build/Wholeset.xcarchive"
export_path="build/export"

if [ "$unsigned" -eq 0 ] && [ ! -f Config/Local.xcconfig ]; then
    echo "archive.sh: Config/Local.xcconfig is missing; copy Config/Local.xcconfig.example and set DEVELOPMENT_TEAM" >&2
    exit 1
fi

rm -rf "$archive_path" "$export_path"

archive_settings=(CURRENT_PROJECT_VERSION="$build_number")
if [ "$unsigned" -eq 1 ]; then
    archive_settings+=(CODE_SIGNING_ALLOWED=NO)
    provisioning=()
else
    provisioning=(-allowProvisioningUpdates)
fi

echo "Archiving Wholeset, build $build_number$([ "$unsigned" -eq 1 ] && echo ' (unsigned)')"
xcodebuild archive \
    -project Wholeset.xcodeproj \
    -scheme Wholeset \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$archive_path" \
    ${provisioning[@]+"${provisioning[@]}"} \
    "${archive_settings[@]}"

if [ "$unsigned" -eq 1 ]; then
    echo "Unsigned archive at $archive_path (not exported)."
    exit 0
fi

xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist Scripts/ExportOptions.plist \
    -allowProvisioningUpdates

echo "Exported to $export_path. Upload the .ipa with Xcode's Organizer or Transporter."
