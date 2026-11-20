# Releasing Wholeset

Notes for the maintainer. Contributors don't need any of this.

## Version and build

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in `Config/Base.xcconfig` and are shared by both apps, so the Watch app always carries the iPhone app's version. Raise `MARKETING_VERSION` there for a new release. The build number is set per build (see below).

Move the `[Unreleased]` notes in [CHANGELOG.md](../CHANGELOG.md) under the new version and add its compare link.

## CloudKit schema

Before a release that changes the SwiftData models, update the CloudKit schema:

1. Launch the iPhone app (a Debug build) on a device signed into iCloud with `-WholesetInitCloudKitSchema`. This creates every record type and field in the CloudKit development schema. It uses a throwaway store, never the app's data.
2. Check the record types in the CloudKit console, then deploy the schema to production.

## Archive and export

With `Config/Local.xcconfig` in place:

```sh
Scripts/archive.sh                # build number from the date and time, e.g. 202611191530
Scripts/archive.sh 42             # explicit build number
Scripts/archive.sh --unsigned     # unsigned archive only, to check that it builds
```

The script:

1. Archives the `Wholeset` scheme (the iPhone app with the Watch app inside) to `build/Wholeset.xcarchive` with automatic signing.
2. Exports it for App Store Connect to `build/export` using `Scripts/ExportOptions.plist`.

Upload the exported app with Xcode's Organizer or Transporter.

Both apps declare that they use no non-exempt encryption (`ITSAppUsesNonExemptEncryption`). Each app bundle carries a privacy manifest (`PrivacyInfo.xcprivacy`).

## After approval

1. Tag the released commit (`vX.Y.Z`).
2. Publish a GitHub release with the same notes as the App Store's "What's New" and the CHANGELOG entry.

## App icon

The icons are classic PNG icon sets drawn by a script (CoreGraphics only):

```sh
swift Scripts/make-app-icon.swift               # default variant into both asset catalogs
swift Scripts/make-app-icon.swift barbell       # another variant: ezbar (default), w, dots, barbell
swift Scripts/make-app-icon.swift path/to/dir/  # contact sheet of all variants, catalogs untouched
swift Scripts/make-app-icon.swift --list        # the variants
```

It writes the iPhone icon (default, dark and tinted) and the Watch icon, all 1024 × 1024. The same input always gives the same files.

## README images

The screenshots in `docs/images/` are the App Store screenshots, scaled down, with rounded corners. Update them when the App Store screenshots change.
