# Signing, updates and releases

Builds are signed with the self-signed "Musa Apps Signing" certificate in the login Keychain, so the designated requirement (`identifier "com.musaamir.unicopy" and certificate leaf = H"6b4e…"`) stays the same across rebuilds and updates. Screen Recording approval therefore survives them. Without the certificate, `build.sh` falls back to ad-hoc signing with a warning and `scripts/release.sh` refuses to publish. Gatekeeper still rejects the app until it is notarized with an Apple Developer ID; switching to one resets Screen Recording approval once.

UniCopy uses Sparkle 2.10 (SwiftPM) for in-app updates. The feed is `appcast.xml` on `main` (`SUFeedURL`), and each release zip is a GitHub release asset signed with the EdDSA key in the login Keychain (account `com.musaamir.unicopy`). Back up both keys: losing the update key means installed copies cannot accept updates.

To release:

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` and commit.
2. Run `./scripts/release.sh "What changed in this version."`

The script builds and zips the universal app, signs the zip, creates the GitHub release and publishes `appcast.xml`.

## Verification (0.2.0)

`swift test` (10 tests) and the packaged helper check passed on a universal build signed by Musa Apps Signing, linked against the macOS 27 SDK with a macOS 14 minimum. The redesigned Settings window (General, Recognition, Shortcut) was inspected in a separate preview bundle. Real screen capture still needs a hands-on check after granting Screen Recording to this build.
