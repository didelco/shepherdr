Native macOS console for herding your coding agents across your Herdr machines: one prioritized queue, the real terminal of every session, a browser per session, and a notification when it's your turn.

### What's new in 0.7

- **Resources at hand.** The pull requests and issues (GitHub, GitLab, Bitbucket, Linear, Jira) and Claude artifacts a session links to gather in a panel on the right, newest first. Click one to open it in the session's browser.
- **Local files open with a click.** Click a path an agent prints: Markdown opens rendered in the session's browser (tables, task lists, images, no scripts), HTML opens as a page, and any other file in its default app. **⌘-click** always uses the default app.
- **Click to choose.** Click an option of an agent's numbered menu, such as a permission prompt in Claude Code or Codex, to select it; double-click to confirm.
- **Picks up where you left off.** After a restart, the session you had open comes back, and every session keeps its browser tabs, prompt editor and resources. Closing a tab forgets it.
- **Rename sessions** from their context menu; Shepherdr renames the Herdr workspace.

### Fixed

- Terminals could fail to connect in optimized builds: a check that newer Swift compilers optimize wrongly rejected valid sessions. CI now also runs the tests optimized.
- Clicking a notification opens its session in the main window, reopening the window if it was closed, never a second one.

### Download and install

- **Apple Silicon (M1 or later), macOS 14 Sonoma or later.** Xcode is not required.
- Download **Shepherdr-…-macos-arm64.dmg**, open it, and drag **Shepherdr.app** to **Applications**. A ZIP of the same app is also available.
- Install and start [Herdr](https://herdr.dev/docs/) separately. Remote machines use Herdr's saved machine profiles and a CLI with `--machine` support, such as 0.9.3.
- Terminals require `terminal session observe/control` on the target machine (verified with CLI/server 0.9.3). Remote terminals use an already-trusted SSH host and noninteractive authentication on Unix-like hosts.
- This release has an **ad hoc signature and is not notarized by Apple**. If macOS blocks the first launch and you trust this download, use **System Settings → Privacy & Security → Open Anyway** for Shepherdr. See [Apple's instructions](https://support.apple.com/en-us/102445). Managed Macs may require administrator approval.
- macOS asks for permission the first time Shepherdr notifies you or you dictate. Dictation downloads its speech model (about 460 MB) from Hugging Face once, after asking.
- `SHA256SUMS` contains checksums for both downloads. In their download directory, run `shasum -a 256 -c SHA256SUMS` after downloading both packages.

Shepherdr is an independent client for Herdr. It creates, renames or closes sessions and changes machines only when you ask; input goes only to the unlocked session you are viewing, and never replaces another client's input without an explicit Take Over.
