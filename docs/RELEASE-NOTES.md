Native macOS console for herding your coding agents across your Herdr machines: one prioritized queue, the real terminal of every session, a browser per session, and a notification when it's your turn.

### What's new in 0.8.1

- **Scroll back through a session.** The trackpad and mouse wheel now move through the history Herdr keeps for each terminal, and full-screen programs such as `less` scroll themselves. While you read earlier output, **↓ LATEST** brings you back to the bottom; typing does too. Locked sessions don't scroll.
- **Lighter on your Mac.** Terminals redraw only the lines that change, and the sidebar's animations no longer redraw the window. A busy agent's terminal takes about half the CPU it did, and a quiet one with agents working in the sidebar drops from about 15% to under 2%.
- **Ligatures are now off by default**, because they make busy terminals redraw more slowly. Turn them back on in **Settings → General → Terminal font**.
- **⌘-click a link in a session's browser** to open it in your default browser.

### Fixed

- After the window changed size, scrolling could reach an old copy of the screen and hide new output until you typed.

### Download and install

- **Apple Silicon (M1 or later), macOS 14 Sonoma or later.** Xcode is not required.
- Download **Shepherdr-…-macos-arm64.dmg**, open it, and drag **Shepherdr.app** to **Applications**. A ZIP of the same app is also available.
- **Required:** install and start [Herdr](https://herdr.dev/docs/) separately. Remote machines use Herdr's saved machine profiles and a CLI with `--machine` support, such as 0.9.3.
- **Recommended:** the [GitHub CLI](https://cli.github.com), signed in with `gh auth login`, to confirm pull requests and issues, fetch their titles and watch pull requests' CI checks.
- Terminals require `terminal session observe/control` on the target machine (verified with CLI/server 0.9.3). Remote terminals use an already-trusted SSH host and noninteractive authentication on Unix-like hosts.
- This release has an **ad hoc signature and is not notarized by Apple**. If macOS blocks the first launch and you trust this download, use **System Settings → Privacy & Security → Open Anyway** for Shepherdr. See [Apple's instructions](https://support.apple.com/en-us/102445). Managed Macs may require administrator approval.
- macOS asks for permission the first time Shepherdr notifies you or you dictate. Dictation downloads its speech model (about 460 MB) from Hugging Face once, after asking.
- `SHA256SUMS` contains checksums for both downloads. In their download directory, run `shasum -a 256 -c SHA256SUMS` after downloading both packages.

Shepherdr is an independent client for Herdr. It creates, renames or closes sessions and changes machines only when you ask; input goes only to the unlocked session you are viewing, and never replaces another client's input without an explicit Take Over.
