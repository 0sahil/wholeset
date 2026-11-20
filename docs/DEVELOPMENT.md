# Developing Wholeset

How to build, run and test Wholeset from source. For contribution rules, see [CONTRIBUTING.md](../CONTRIBUTING.md).

## Requirements

- A Mac with Xcode 27 or later
- iOS 26 or later and watchOS 26 or later on the devices you run it on

The project has no third-party dependencies, so there is nothing to install besides Xcode.

## Local settings

Build settings live in `Config/*.xcconfig`. Your own values go in `Config/Local.xcconfig`, which git ignores, so your team ID never ends up in a commit:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

| Setting | Default | Meaning |
|---|---|---|
| `DEVELOPMENT_TEAM` | none | Your Apple Developer team ID, shown in Xcode > Settings > Accounts. |
| `BUNDLE_ID_PREFIX` | `app.wholeset` | Set this to run on your own devices: a reverse-DNS prefix you own, such as `com.yourname.wholeset`. The iPhone app uses the prefix itself, the Watch app `<prefix>.watchkitapp`, and the iCloud container `iCloud.<prefix>`. |
| `WHOLESET_ICLOUD` | `YES` | `NO` builds both apps without the iCloud (CloudKit) and push entitlements. HealthKit stays. Write it exactly as `YES` or `NO`. |

The default identifiers belong to the project's own team, so a build signed with your team needs your own `BUNDLE_ID_PREFIX`. You don't need to edit anything else: the entitlements, the Watch app's companion ID and the iCloud container all follow from it.

## Running on your own devices

### With a paid Apple Developer account

```
DEVELOPMENT_TEAM = <your team ID>
BUNDLE_ID_PREFIX = com.yourname.wholeset
```

Open `Wholeset.xcodeproj` and run the `Wholeset` scheme on your iPhone. The Watch app is embedded in the iPhone app; run the `WholesetWatch` scheme to install it on the Watch directly. Xcode registers the app IDs and the iCloud container for you through automatic signing.

### With a free Apple ID

A free Apple ID can sign HealthKit but not iCloud (CloudKit) or push notifications ([Apple's capability table](https://developer.apple.com/help/account/reference/supported-capabilities-ios)). Turn iCloud off:

```
DEVELOPMENT_TEAM = <your personal team ID>
BUNDLE_ID_PREFIX = com.yourname.wholeset
WHOLESET_ICLOUD = NO
```

In this mode, each device keeps its own data and the iPhone and Watch don't sync with each other. iPhone Settings > iCloud Sync shows "Off in this build". Everything else, including saving workouts to Apple Health, works as usual.

On first run, turn on Developer Mode on the iPhone and the Watch (Settings > Privacy & Security), and trust your developer certificate on the iPhone (Settings > General > VPN & Device Management).

## Simulator and command-line builds

Simulator builds don't need signing and use a local store; CloudKit sync is only used on device builds.

```sh
xcodebuild -project Wholeset.xcodeproj -scheme Wholeset \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Wholeset.xcodeproj -scheme WholesetWatch \
  -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The Xcode project uses folder-synchronized groups, so adding a file to one of the target folders adds it to that target without editing the project file.

## Demo screens

Debug builds can open any screen with sample data, which is handy for checking UI changes and taking screenshots. Launch either app with `-WholesetDemo <screen>`: it opens straight into that screen with an in-memory store and sample data (on the Watch, also a fake HealthKit manager). Add `-WholesetDemoUnit lb` for pounds. Release builds don't contain this code.

- Watch: `home`, `home-syncing`, `countdown`, `exercise`, `exercise-selected`, `exercise-logged`, `done`, `done-long`, `rest`, `menu`, `stats`,
  `end-confirm`, `summary`, `restored`, `restored-nohealth`.
- iPhone: `welcome`, `units`, `health`, `plan`, `plan-empty`, `routine-editor`, `exercise-picker`, `exercises`, `exercise-detail`, `settings`,
  `progression-steps`, `exercise-settings`, `rest-picker`, `custom-step`, `history`, `history-empty`, `history-search`, `session-detail`,
  `session-edit`, `session-delete-confirm`, `exercise-history`, `exercise-history-volume`, `reps-by-weight`, `exercise-history-empty`,
  `import-start`, `import-how`, `import-detected`, `import-unit`, `import-date-order`, `import-columns`, `import-match`, `import-match-all`,
  `import-progress`, `import-done`, `import-rows-not-read`, `history-imported`.

In Xcode, add the arguments under Product > Scheme > Edit Scheme > Run > Arguments.

## Tests

The shared logic lives in `WholesetKit` and is tested with Swift Testing. The tests run on macOS:

```sh
cd WholesetKit && swift test
```

Import tests use synthetic files in `WholesetKit/Tests/WholesetKitTests/Fixtures`: invented workouts in each app's header layout. To also run the importer over a folder of real exports you have locally (they are never part of the repository), set `WHOLESET_IMPORT_SAMPLES_DIR` to that folder. The test prints what it read from each `.csv` file:

```sh
cd WholesetKit && env WHOLESET_IMPORT_SAMPLES_DIR=/path/to/exports swift test --filter ImportSampleFilesTests
```

## Continuous integration

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs the WholesetKit tests and both unsigned simulator builds on every push to `main` and every pull request. Dependabot keeps the workflow's actions up to date.

## Releasing

Maintainer notes for versioning, the CloudKit schema, archiving and the app icon are in [RELEASING.md](RELEASING.md).
