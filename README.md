# Wholeset

A workout tracker for Apple Watch and iPhone. Log every set from your wrist, sync workouts to Apple Fitness, and keep your full history with no limits.

**Status:** version 1.0, getting ready for its first TestFlight build. The Watch app runs a workout, logs sets, times rests and saves the workout to Apple Health. The iPhone app plans (routines, a weekly plan, an exercise library and settings, all synced to the Watch through iCloud), shows your history with records and charts, and imports workouts exported from Strong, Hevy, FitNotes and other apps.

## What it is

- **Apple Watch** is where you train: start a routine, log sets with the Digital Crown, rest, finish. Works without the iPhone nearby.
- **iPhone** is where you plan and review: routines, a weekly plan, history and progress.
- Workouts are saved to Apple Health so they count toward your Activity rings.
- Data syncs between your devices through your own iCloud account (CloudKit private database). No accounts, no servers.
- Built with Apple frameworks only: SwiftUI, SwiftData, CloudKit, HealthKit, Swift Charts.
- No tracking, no analytics, nothing sent to the developer. See the [privacy policy](PRIVACY.md).

## Requirements

- Xcode 27 or later
- iOS 26 or later, watchOS 26 or later

## Project layout

| Path | Contents |
|---|---|
| `Wholeset/` | iOS app target |
| `WholesetWatch/` | watchOS app target (embedded in the iOS app, also runs on its own) |
| `WholesetKit/` | Swift package with the shared code: versioned SwiftData models and migrations, store setup, sync maintenance and status, the exercise library, the planning and workout logic, and the CSV import (readers, exercise matching, writing) |
| `Config/` | Build settings as `.xcconfig` files |
| `Scripts/` | `curate-exercise-library.py` builds the bundled exercise library; `make-app-icon.swift` draws the app icons; `archive.sh` and `ExportOptions.plist` archive and export a release build |

The Xcode project uses folder-synchronized groups, so adding a file to one of the target folders adds it to that target without editing the project file.

## Building

1. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set `DEVELOPMENT_TEAM` to your Apple Developer team ID. This file is ignored by git, so your team ID never ends up in a commit.
2. Open `Wholeset.xcodeproj` and run the `Wholeset` scheme (iPhone, which also builds the Watch app) or the `WholesetWatch` scheme.

HealthKit, iCloud (CloudKit) and push notifications need a signed build with a team that can use those capabilities. The bundle identifiers (`app.wholeset`, `app.wholeset.watchkitapp`) and the iCloud container (`iCloud.app.wholeset`) belong to the project's own team; to run on your own devices, change them in `Config/*.xcconfig`, the `.entitlements` files and `WholesetStore.cloudKitContainerIdentifier`.

Command-line builds without signing:

```sh
xcodebuild -project Wholeset.xcodeproj -scheme Wholeset \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Wholeset.xcodeproj -scheme WholesetWatch \
  -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Simulator builds use a local store; CloudKit sync is only enabled on device builds.

### Demo screens (Debug builds only)

To look at a screen without setting up data, launch either app with `-WholesetDemo <screen>`.
It then opens straight into that screen with an in-memory store and sample data (on the Watch also a fake HealthKit manager).
Add `-WholesetDemoUnit lb` for pounds. Release builds do not contain this code.

- Watch: `home`, `home-syncing`, `countdown`, `exercise`, `exercise-selected`, `exercise-logged`, `done`, `done-long`, `rest`, `menu`, `stats`,
  `end-confirm`, `summary`, `restored`, `restored-nohealth`.
- iPhone: `welcome`, `units`, `health`, `plan`, `plan-empty`, `routine-editor`, `exercise-picker`, `exercises`, `exercise-detail`, `settings`,
  `progression-steps`, `exercise-settings`, `rest-picker`, `custom-step`, `history`, `history-empty`, `history-search`, `session-detail`,
  `session-edit`, `session-delete-confirm`, `exercise-history`, `exercise-history-volume`, `reps-by-weight`, `exercise-history-empty`,
  `import-start`, `import-how`, `import-detected`, `import-unit`, `import-date-order`, `import-columns`, `import-match`, `import-match-all`,
  `import-progress`, `import-done`, `import-rows-not-read`, `history-imported`.

## Tests

The shared logic lives in `WholesetKit` and is tested with Swift Testing. The tests run on macOS:

```sh
cd WholesetKit && swift test
```

Import tests use synthetic files in `WholesetKit/Tests/WholesetKitTests/Fixtures`: invented workouts in each app's header layout. To also run the importer over a folder of real exports you have locally (they are never part of the repository), set `WHOLESET_IMPORT_SAMPLES_DIR` to that folder; the test prints what it read from each `.csv` file:

```sh
cd WholesetKit && env WHOLESET_IMPORT_SAMPLES_DIR=/path/to/exports swift test --filter ImportSampleFilesTests
```

## Releasing

**Version and build.** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in `Config/Base.xcconfig` and are shared by both apps, so the Watch app always carries the iPhone app's version. Raise `MARKETING_VERSION` there for a new release; the build number is set per build.

**Archive and export.** With `Config/Local.xcconfig` in place:

```sh
Scripts/archive.sh                # build number from the date and time, e.g. 202611191530
Scripts/archive.sh 42             # explicit build number
Scripts/archive.sh --unsigned     # unsigned archive only, to check that it builds
```

The script archives the `Wholeset` scheme (the iPhone app with the Watch app inside) to `build/Wholeset.xcarchive` with automatic signing, then exports it for App Store Connect to `build/export` using `Scripts/ExportOptions.plist`. Upload the exported app with Xcode's Organizer or Transporter. Both apps declare that they use no non-exempt encryption (`ITSAppUsesNonExemptEncryption`), and each app bundle carries a privacy manifest (`PrivacyInfo.xcprivacy`).

**App icon.** The icons are classic PNG icon sets drawn by a script (CoreGraphics only):

```sh
swift Scripts/make-app-icon.swift               # default variant into both asset catalogs
swift Scripts/make-app-icon.swift barbell       # another variant: w (default), dots, barbell
swift Scripts/make-app-icon.swift path/to/dir/  # contact sheet of all variants, catalogs untouched
swift Scripts/make-app-icon.swift --list        # the variants
```

It writes the iPhone icon (default, dark and tinted) and the Watch icon, all 1024 × 1024. The same input always gives the same files.

## License

[GPL-3.0-or-later](LICENSE).

The built-in exercise library is curated from [free-exercise-db](https://github.com/yuhonas/free-exercise-db), which is in the public domain (Unlicense).
