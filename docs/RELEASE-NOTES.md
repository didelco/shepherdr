Native macOS console for herding your coding agents across your Herdr machines: one prioritized queue, the real terminal of every session, a browser per session, and a notification when it's your turn.

### What's new in 0.8

- **Drop files and images on the terminal.** Their paths are pasted into the agent's prompt, escaped as other macOS terminals do, so Claude Code and Codex attach dropped images. An image without a file, from a web page say, is saved as a PNG first. In a session on another machine, each file is copied there over SSH first.
- **Pull request checks.** While you look at a session, its GitHub pull requests show their CI checks: ● running, ✓ passed, ✗ failed. One query covers them all, every 15 seconds while checks run and every 2 minutes after; a notification tells you when they finish. Needs the GitHub CLI, signed in.
- **Resources you can trust.** Each new resource is checked once: links agents write as examples leave the panel, and the rest show their page's title. A GitHub number is listed once, as the pull request or issue it really is. Each kind shows its ten most relevant first, the most opened and mentioned.
- **More in the queue.** Each session shows where it works, its folder or, in cyan, the project of its Git worktree, and its pull request; click it to open the session with the pull request, or with all of them in tabs.
- **Know when to close the lid.** The foot of the sidebar tells you whether it's safe to close the lid, or whether agents are working on this Mac.

### Fixed

- Clicking a notification could open a second window. Shepherdr now keeps a single window.

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
