Native macOS console for herding your coding agents across your Herdr machines: one prioritized queue, the real terminal of every session, a browser per session, and a notification when it's your turn.

### What's new in 0.8.2

- **Filter the overview.** Click the state counters, and the new card for each machine, to list any combination of states and machines. Each row counts what the other lets through, and **SHOW ALL** clears the choice.
- **See how busy each machine is.** Machine cards show processor, memory and disk use, measured every 15 seconds while the overview is open, so you can choose where to start the next agent.
- **Start sessions in the usual folders.** New Session offers the folders your agents work in on the chosen machine, most used first, leaving out Git worktrees.
- **Spot commands left running.** An agent that is done or idle but left a dev server or a watcher running shows a turning clock ◴ instead of its mark, with the command beside its folder. Hover it to see them all.
- **Edit the prompt with ⌘ keys.** ⌘← and ⌘→ go to the start and end of the line, and ⌘⌫ and ⌘⌦ delete to them, as in other Mac apps.
- **Click in programs that use the mouse,** such as Claude Code in full-screen mode (`/tui fullscreen`), where a click in the prompt moves the cursor there. This needs Herdr 0.9.2 or later.

### Fixed

- Scrolling filled blank space with the dotted underline of links.
- Links could stop opening in very long sessions.

### Download and install

- **Apple Silicon (M1 or later), macOS 14 Sonoma or later.** Xcode is not required.
- Download **Shepherdr-…-macos-arm64.dmg**, open it, and drag **Shepherdr.app** to **Applications**. A ZIP of the same app is also available.
- **Required:** install and start [Herdr](https://herdr.dev/docs/) separately. Remote machines use Herdr's saved machine profiles and a CLI with `--machine` support, such as 0.9.3.
- **Recommended:** the [GitHub CLI](https://cli.github.com), signed in with `gh auth login`, to confirm pull requests and issues, fetch their titles and watch pull requests' CI checks.
- Terminals require `terminal session observe/control` on the target machine (verified with CLI/server 0.9.3). Remote terminals, machine load and commands left running use an already-trusted SSH host and noninteractive authentication on Unix-like hosts.
- This release has an **ad hoc signature and is not notarized by Apple**. If macOS blocks the first launch and you trust this download, use **System Settings → Privacy & Security → Open Anyway** for Shepherdr. See [Apple's instructions](https://support.apple.com/en-us/102445). Managed Macs may require administrator approval.
- macOS asks for permission the first time Shepherdr notifies you or you dictate. Dictation downloads its speech model (about 460 MB) from Hugging Face once, after asking.
- `SHA256SUMS` contains checksums for both downloads. In their download directory, run `shasum -a 256 -c SHA256SUMS` after downloading both packages.

Shepherdr is an independent client for Herdr. It creates, renames or closes sessions and changes machines only when you ask; input goes only to the unlocked session you are viewing, and never replaces another client's input without an explicit Take Over.
