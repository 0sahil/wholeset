# Contributing to Wholeset

Thanks for wanting to help. Bug reports, ideas, fixes and translations are all welcome.

## Before you start

- **Bugs:** open an [issue](https://github.com/0sahil/wholeset/issues/new/choose) with the bug report form. Include the app version (iPhone app: Settings > Version) and your iPhone and Apple Watch models.
- **Ideas and questions:** start a thread in [Discussions](https://github.com/0sahil/wholeset/discussions).
- **Pull requests:** open an issue or discussion first and wait for a reply before you write code. Wholeset is a small app with a clear scope, and some good ideas still won't fit. Asking first means your time isn't wasted. Small fixes (typos, an obvious one-line bug) can go straight to a PR.
- **Security problems:** don't open an issue. See [SECURITY.md](SECURITY.md).

## Setting up

Follow [Build from source](README.md#build-from-source) in the README. [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) covers signing your own builds, the demo screens and the import test samples.

## How the code is organised

- Logic goes in the `WholesetKit` Swift package as plain, testable types. This includes prefill, progression, records, units and the import readers. The app targets (`Wholeset/`, `WholesetWatch/`) stay thin and hold mostly views.
- Swift 6 language mode. The app targets use MainActor default isolation and approachable concurrency.
- Apple frameworks only. Please don't add third-party dependencies.
- Weights are stored in kilograms (`Double`) and converted only when shown or entered.
- SwiftData models follow CloudKit's rules:
  - no unique attributes
  - every relationship optional with an explicit inverse
  - every attribute optional or defaulted
  - enums stored as raw `String` values with a typed accessor
- Schema changes go through a new `VersionedSchema` and the migration plan. Changing a released model in place breaks sync for existing users.
- Views should be small. Custom controls need accessibility labels and should work with Dynamic Type. No force unwraps outside tests.
- Public API in `WholesetKit` gets doc comments. No commented-out code.

## Tests

Every logic change comes with tests (Swift Testing: `import Testing`, `@Test`, `#expect`). Before you open a PR:

```sh
cd WholesetKit && swift test
xcodebuild -project Wholeset.xcodeproj -scheme Wholeset \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Wholeset.xcodeproj -scheme WholesetWatch \
  -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

CI runs the same three commands on every pull request.

UI changes: add a screenshot to the PR. The `-WholesetDemo <screen>` launch argument opens any screen with sample data (see [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#demo-screens)).

## Translations

Wholeset is English only for now. Its text lives in Xcode String Catalogs (`Localizable.xcstrings`), which Xcode fills in when you build. If you'd like to translate the app, open an issue first so we can agree on the language and how the exercise names are handled.

## License

Wholeset is licensed under [GPL-3.0-or-later](LICENSE). By sending a contribution, you agree that it is released under the same license.

## Code of conduct

Everyone taking part is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).
