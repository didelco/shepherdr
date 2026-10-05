# Releases

The [Release workflow](../.github/workflows/release.yml) builds on a GitHub-hosted Apple Silicon Mac. It runs the tests, builds an optimized arm64 app for macOS 14+, embeds the tag's version and the workflow run number, applies an ad hoc signature, verifies the app after ZIP extraction, verifies the DMG, and produces SHA-256 checksums.

The `.dmg` includes an Applications shortcut and installation instructions. The `.zip` contains the same `.app`. Both include the SwiftTerm renderer and its MIT notices. Neither package bundles Herdr or needs Xcode on the user's machine. Committed SwiftPM lockfiles pin the dependency revisions.

## Publish a version

Use a stable tag in the exact form `vMAJOR.MINOR.PATCH`. From the reviewed commit on `main`:

```sh
git tag -a v0.1.0 -m 'Shepherdr 0.1.0'
git push origin v0.1.0
```

Use a new version number for each release. The workflow first creates a draft and uploads all assets, then makes the release public and marks it latest. A failed run can leave a draft, which can be resumed using **Actions → Release → Run workflow** with the existing tag. An already-public release is never overwritten; use a new tag for corrections. The workflow only needs GitHub's automatic `GITHUB_TOKEN` with `contents: write`; no personal access token is required.

Update [release notes](RELEASE-NOTES.md) when installation requirements change. GitHub-generated change notes are appended automatically. The build takes its version from the tag, so changing the Xcode project's development version is optional.

## Reproduce packaging locally

On a Mac with Xcode 16+ and its first-launch setup completed:

```sh
bash scripts/package-release.sh v0.1.0
```

Packages are written to `dist/`. The script refuses to overwrite an existing package of the same version. It does not publish anything. `GITHUB_RUN_NUMBER` supplies the bundle build number in CI; local builds use `1`.

## Signing status

Current releases use an ad hoc signature, not an Apple Developer ID certificate, and are not notarized. The signature supports execution on Apple Silicon and detects bundle changes; it does not authenticate the publisher to Gatekeeper. First launch may require the app-specific **Open Anyway** exception described in [Apple's instructions](https://support.apple.com/en-us/102445).

To distribute without that exception, a maintainer must supply a Developer ID Application certificate and notarization credentials. The packaging step must then sign with that identity, submit with `notarytool`, require an accepted result, staple the ticket, and only afterward create the final downloads. That credential-dependent path is not enabled or claimed by this workflow. Never commit certificates or credentials, or ask users to disable Gatekeeper globally.
