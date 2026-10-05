# Verification

## Session console redesign (0.4.0)

Validated on 2026-10-04 on Apple Silicon with Xcode 27 / Swift 6.4:

- `swift test` and the README's `xcodebuild … test` command — **45 tests in 6 suites passed**, including the native application build. The built bundle contains `AppIcon.icns` and `CFBundleIconName = AppIcon`.
- New tests cover drag-and-drop offsets within filtered queues, the explicit `--takeover` flag, prompt encoding (bracketed paste, escape stripping, separate Return), prompt submission order, conflict fallback to watching, user takeover, and returning to watching when another client takes over.
- A separate Herdr 0.9.3 session (`--session shptest`) held demo workspaces running a small mock agent, with lifecycle states set through `pane report-agent`. A wrapper routed a SwiftPM build of the app to that session; the user's default session was never connected to. A temporary in-process harness (not committed) drove the UI and rendered window images:
  - Overview counts and cards, sidebar queue with states, shells section, Settings → General and Settings → Machines rendered as intended.
  - Selecting a session embedded its live terminal in the work area in LIVE mode. A single-line prompt typed into the composer and submitted with Return arrived as one line in the agent (`pane read` confirmed).
  - A multi-line prompt submitted to a zsh pane ran both lines, confirming bracketed paste plus a separate Return against a real bracketed-paste consumer.
  - With another control client attached, opening that session fell back to WATCH, showed the conflict notice and offered TAKE OVER. A CLI check confirmed Herdr's `--takeover` gives the new client frames and closes the old one with `terminal attach taken over`.
  - Moving a session to the top and down one place from the sidebar updated the saved ranking; filtering kept movement relative to visible rows.
- Creating and closing (same day, later): 51 tests pass. New tests cover the exact `workspace create` / `agent start` / `pane close` / `machine add|enable|disable|remove` arguments, remote `--machine` routing, `agent_not_ready` as a waiting agent, option-like values rejected before running Herdr, preserved SSH diagnostics, and store refresh after a change. Against the isolated session, Herdr 0.9.3 behaviour was checked first: `workspace create` returns the root pane and terminal; `agent start --kind claude` resolves the real agent executable and reports `agent_not_ready` while Claude Code asks to trust the folder (that test agent was closed immediately, without a prompt); `pane close` on a workspace's only pane also closes the workspace. Through the app, a shell-only session was created, opened in the work area, then closed; the queue and shells list updated. The New Session sheet, Fira Code interface and terminal, font settings (monospaced families only) and the logo and app icon (later redrawn as a German Shepherd watching the flock, and a German Shepherd in Matrix sunglasses) were inspected in rendered images. Adding, disabling and removing machines were not run against a real SSH host, to avoid changing the user's Herdr catalog.
- Not verified: prompts against a real Claude Code (or other) agent, keyboard shortcuts delivered through real key events, drag gestures with a pointer, and remote SSH terminals. Screenshots of the real screen were unavailable; images were rendered in-process.

## Session priorities (0.3.0)

Validated on 2026-10-03:

- `swift test` and the README's Xcode test command — **40 tests in 6 suites passed**, including the native application build.
- Five new tests cover relaunch persistence, identical terminal IDs on different machines, late arrivals, missing sessions, filtered movement, boundaries, invalid preferences, duplicate identifiers, and aggregation through a mock Herdr client during failures and recovery.
- A disposable app copy with a separate bundle identifier and synthetic local/remote machines displayed eight sessions with priorities. Via native accessibility automation, selecting the last remote session and clicking **Raise Priority** moved it from position 8 to 7; **⌥⌘↑** then moved it to 6. Selection and the enabled/disabled movement controls updated correctly.
- Sorting by State kept saved priority numbers and disabled movement; sorting Priority ascending restored **My order** and its controls. In the remote machine view, moving that session to its first visible slot changed its global priority to 5 and disabled further upward movement. Returning to All Agents confirmed that the four hidden local sessions retained positions 1–4.
- The GUI launch was slow and screenshot capture was unavailable. These checks verified accessibility state and control behavior; they do not claim a screenshot-based layout review. Preference reload and hidden-slot preservation were verified by automated tests.
- This feature's GUI tests use a fixture executable, not the user's Herdr installation or active sessions.

## Interactive terminals (0.2.0)

Validated on 2026-10-03 on the same Apple Silicon host with Xcode 27 / Swift 6.4:

- `swift test` and the README's `xcodebuild … test` command — **35 tests in 5 suites passed**, including the native application build.
- Terminal tests cover structured frames and binary input, malformed frames, explicit local routing, safe quoting of SSH arguments, no forced takeover, shell panes without agents, streaming subprocess input/output, startup timeout, connection failure, observation/input isolation, mode changes, detach and reconnect.
- A separate real Herdr 0.9.3 instance used temporary configuration/state and a newly created test workspace. A disposable app copy displayed its workspace and the live shell prompt in a native **Observing** window.
- A live harness using the actual `CLIHerdrClient` attached in control mode, sent a shell command, detached and reattached twice. It verified the same terminal ID and shell PID on both passes. The running shell survived each client disconnect.
- Release packaging — **passed**: optimized arm64 build, ZIP extraction/signature check, bundled SwiftTerm license comparison, DMG verification and SHA-256 checksums.
- The user's normal local server and active remote sessions were not changed. No authenticated remote terminal was available. SSH quoting and failure behavior are tested locally; real multi-host terminal transport remains unverified.
- Automated GUI access became unavailable after verifying observation. Enabling input through the button and typing through the native view still need a manual end-to-end check; input/detach/reconnect are verified through the real transport and mocked store.

## Dashboard (0.1.0)

Validated on 2026-09-30 on macOS 26.6.2 (Apple Silicon), using Xcode 27.0 / Swift 6.4. Deployment target is macOS 14; an actual macOS 14 runtime has not been tested.

## Automated and live checks

- `xcodebuild -project Shepherdr.xcodeproj -scheme Shepherdr -configuration Debug -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO test` — **passed**, building the native application and running 27 tests in 3 suites.
- `swift test` — **passed**, the same 27 tests.
- `shepherdr-probe` against the real local installation — **passed**: executable discovered, Herdr 0.9.0 / protocol 22 decoded, one real workspace, no detected agents at verification time.
- Repeated the live probe on 2026-10-01 after updating the CLI to 0.9.3 — **passed** against the existing 0.9.0 server. Structured server status reported `compatible: true` and `restart_needed: false`; no server restart or session changes were performed.
- Xcode scheme XML, project plist and synthetic JSON fixtures — valid.
- Multiple machines, same IDs across machines, partial failures, recovery and stale retention — covered by the mock-client tests. No saved remote machine was available for real SSH verification.

## UI verification

The built native application was opened and inspected interactively:

- **Real installation:** All Agents showed Local as online and the expected empty agent state. Selecting Local displayed its actual workspace, directory, tab and pane counts, Herdr version and default session.
- **Synthetic cluster:** a separate disposable app copy used `SHEPHERDR_HERDR_PATH` to query an isolated fixture executable. Local and a remote profile supplied agents; another profile reported Herdr not running; a disabled profile stayed visible. No real Herdr configuration was changed.
- **Navigation and inspection:** checked All Agents, machine selection, workspace filtering, search by machine, the Blocked filter, and the metadata inspector. Machine/workspace ownership and routing identifiers matched the fixtures. Blocked agents appeared first with restrained orange emphasis.
- **Partial failure:** after a remote became unreachable, its four cached agents remained visible and marked stale while Local continued updating. The machine view exposed the error and last-received timestamp; summary counts excluded stale data.
- **Refresh and recovery:** pausing automatic refresh preserved the displayed snapshot. Manual refresh then recovered the remote and replaced cached rows, clearing stale markers.
- **Scale and layout:** checked 60 aggregate agents across two reachable machines, including unknown and future lifecycle values displayed as Unknown. Inspected a roughly 900 × 550 window with the inspector open: native horizontal table scrolling and vertical inspector scrolling kept content accessible.

The synthetic cluster validates application behavior, not a real SSH connection. No saved remote machine or real running coding agent was available during the initial verification. The updated CLI 0.9.3 supports `--machine`; real multi-host forwarding still needs successful SSH authentication and a saved profile targeting an existing remote session.
