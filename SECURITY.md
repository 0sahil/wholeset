# Security policy

## Supported versions

Only the latest version on the App Store gets fixes.

## Reporting a vulnerability

Please report security problems privately, not in a public issue:

- Use GitHub's [private vulnerability reporting](https://github.com/0sahil/wholeset/security/advisories/new) for this repository, or
- email 0sahil.dev@gmail.com with "Wholeset security" in the subject.

Include what you found, how to reproduce it, and which app version and devices you used. You'll get a reply within a week. Once a fix is out, the report can be made public, with credit to you if you'd like.

## Scope

Wholeset has no servers and no accounts. Your data lives on your devices, in your own iCloud private database and in Apple Health. The most relevant reports are about:

- data leaving your devices other than through iCloud sync, Apple Health or a problem report you send yourself
- the CSV importer misbehaving on crafted files
- one user's data reaching another

Problems in iCloud, CloudKit or HealthKit themselves should go to [Apple](https://security.apple.com).
