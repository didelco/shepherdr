Native macOS console for herding your coding agents across your Herdr machines: a prioritized queue, embedded live terminals and a prompt composer.

### First public release

Shepherdr started as a side project and is now open source under the MIT License.

- **One queue for every agent.** Sessions from all your Herdr machines in your own priority order, with drag and drop, ▲▼ controls, **⌥⌘↑ / ⌥⌘↓** and **⌘1…⌘9**. Priorities survive restarts, refreshes and temporarily missing machines.
- **Live terminals in the main window,** with a prompt composer underneath: **⏎** sends, **⇧⏎** adds a line, **↑/↓** recall prompts, plus Esc / ^C / Tab / arrow keys.
- **Watch or drive.** Sessions open **LIVE** by default. If another client has input, Shepherdr watches and offers an explicit **Take Over**.
- **Create and close sessions** with **⌘N**: pick a folder and an agent (Claude Code, Codex, Gemini, opencode…) or a plain shell. **Close Session…** asks for confirmation first.
- **Machines** live in **Settings → Machines** (⌘,), where you can add, disable, enable and remove them. An overview shows working / needs-you / done / idle counts.
- A phosphor console theme in the bundled Fira Code, a configurable monospaced terminal font, an 8-bit flock watched over by a German Shepherd, and a pixel-art app icon of that shepherd in Matrix digital rain. *Do androids dream of electric sheep?*

### Download and install

- **Apple Silicon (M1 or later), macOS 14 Sonoma or later.** Xcode is not required.
- Download **Shepherdr-…-macos-arm64.dmg**, open it, and drag **Shepherdr.app** to **Applications**. A ZIP of the same app is also available.
- Install and start [Herdr](https://herdr.dev/docs/) separately. Remote monitoring uses Herdr's saved machine profiles and requires a CLI with `--machine` support, such as 0.9.3.
- Terminals require `terminal session observe/control` on the target machine (verified with CLI/server 0.9.3). Remote terminals use an already-trusted SSH host and noninteractive authentication on Unix-like hosts.
- This release has an **ad hoc signature and is not notarized by Apple**. If macOS blocks the first launch and you trust this download, use **System Settings → Privacy & Security → Open Anyway** for Shepherdr. See [Apple's instructions](https://support.apple.com/en-us/102445). Managed Macs may require administrator approval.
- `SHA256SUMS` contains checksums for both downloads. In their download directory, run `shasum -a 256 -c SHA256SUMS` after downloading both packages.

Shepherdr is an independent client for Herdr. It creates or closes sessions and changes machines only when you ask; input goes only to the session you are viewing in Live mode, and never replaces another client's input without an explicit Take Over.
