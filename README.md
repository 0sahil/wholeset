# Wholeset

A workout tracker for Apple Watch and iPhone. Log every set from your wrist, sync workouts to Apple Fitness, and keep your full history with no limits.

**Status:** early development. The project skeleton is in place; the app does not do anything useful yet.

## What it is

- **Apple Watch** is where you train: start a routine, log sets with the Digital Crown, rest, finish. Works without the iPhone nearby.
- **iPhone** is where you plan and review: routines, a weekly plan, history and progress.
- Workouts are saved to Apple Health so they count toward your Activity rings.
- Data syncs between your devices through your own iCloud account (CloudKit private database). No accounts, no servers.
- Built with Apple frameworks only: SwiftUI, SwiftData, CloudKit, HealthKit, Swift Charts.

## Requirements

- Xcode 27 or later
- iOS 26 or later, watchOS 26 or later

## Project layout

| Path | Contents |
|---|---|
| `Wholeset/` | iOS app target |
| `WholesetWatch/` | watchOS app target (embedded in the iOS app, also runs on its own) |
| `WholesetKit/` | Swift package with the shared code: SwiftData models and store setup |
| `Config/` | Build settings as `.xcconfig` files |

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

## Tests

The shared logic lives in `WholesetKit` and is tested with Swift Testing. The tests run on macOS:

```sh
cd WholesetKit && swift test
```

## License

[GPL-3.0-or-later](LICENSE).
