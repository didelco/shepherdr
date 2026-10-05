# Developing Shepherdr

Requires macOS 14 or later and Xcode 16 or later, with its license accepted and first-launch components installed. See [CONTRIBUTING](../CONTRIBUTING.md) for the ground rules.

## Dependencies

The native terminal renderer uses [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), pinned to 1.10.1 (MIT). Fira Code 6.2 is bundled under the SIL Open Font License 1.1 (`Sources/ShepherdrTerminalUI/Resources/Fonts`). This AppKit version builds without an additional Metal compiler component or binary framework. SwiftPM also resolves SwiftTerm's command-line tooling dependency, ArgumentParser; it is not linked into Shepherdr. No API keys, accounts, or server-side Shepherdr service are required.

## Build and run

From this repository's root:

```sh
open Shepherdr.xcodeproj
```

Choose the shared **Shepherdr** scheme and **My Mac** destination, then press **⌘R**. No development team is needed for a local build. The application intentionally does not use App Sandbox: it must launch the user's installed Herdr executable and access Herdr's socket and SSH environment.

Or build and launch the application from Terminal:

```sh
xcodebuild -project Shepherdr.xcodeproj \
  -scheme Shepherdr -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
open build/Build/Products/Debug/Shepherdr.app
```

If Xcode requests setup, open Xcode once to install its components. Review and accept Apple's license with `sudo xcodebuild -license`. If the wrong developer directory is selected, use `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`.

Swift Package Manager also builds the application executable:

```sh
swift build --product shepherdr
swift run shepherdr
```

Use the Xcode-built `.app` for normal Dock/Finder use. See [releasing](RELEASING.md) for the automated Apple Silicon packages and their signing status.

## Tests and diagnostics

```sh
swift test
xcodebuild -project Shepherdr.xcodeproj \
  -scheme Shepherdr -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
# Read-only live transport/store smoke test; exits 1 when no machine is online:
swift run shepherdr-probe
```

Tests use Swift Testing, synthetic JSON fixtures, mock cluster/terminal clients, isolated preferences, an injected command runner, and bounded real subprocess tests. They cover decoding, domain joins, all states, future states, duplicate IDs, aggregation, partial failures, stale retention, recovery, catalog failures, disabled/removed profiles, incremental results, cancellation, literal arguments, pipe draining, terminal JSON streams, observation/input boundaries, detach/reconnect, priority persistence and filtered reordering. No running Herdr or SSH access is needed for the test suite.

Use **Settings → Machines** for failure details. A malformed response is **Incompatible**, never a successful empty session. Temporary failures keep cached rows visible with a stale marker and last-received timestamp. The summary counts exclude stale rows. Last-known snapshots are held in memory only; quitting clears them. The app does not collect telemetry or write snapshot/terminal contents to disk; saved priorities contain only session identifiers.

## Architecture

```text
App/                              SwiftUI presentation: queue sidebar, work area, composer, settings, theme
Sources/ShepherdrCore/
  Transport/                      CLI adapters, executable discovery, bounded process/stream transports
  DTO/                            JSON wire types, validation and domain mapping
  Domain/                         Machine, Workspace, Agent, lifecycle and failure models
  Store/                          MainActor cluster state, local session priorities and terminal connections
Sources/ShepherdrTerminalUI/       Embeddable SwiftTerm AppKit terminal surface and palette
Sources/ShepherdrProbe/            Read-only integration diagnostic
Tests/ShepherdrCoreTests/          Protocol, transport and store regression tests
scripts/make-icon.swift            Regenerates App/Assets.xcassets/AppIcon.appiconset from docs/assets/icon.png
```

`HerdrClient` exposes domain snapshots and the machine catalog. `HerdrTerminalClient` exposes live terminal connections, frames and input. `CLIHerdrClient` implements both; views never execute commands or decode JSON. Agent identity combines the machine profile and terminal ID, so identical pane IDs and names on different machines remain distinct. Native Unix-socket transport and event subscriptions can replace the CLI behind these boundaries.

See [integration notes](HERDR-INTEGRATION.md) for the inspected contract, compatibility policy, event strategy and limitations.

