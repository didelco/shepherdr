Native macOS console for herding your coding agents across your Herdr machines: one prioritized queue, the real terminal of every session, a browser per session, and a notification when it's your turn.

### What's new in 0.8.8

From 0.8.7 on, Shepherdr offers this version itself, at the foot of the sidebar.

- **Go anywhere with ⌘T.** A panel like Spotlight lists your sessions, shells and Compass, the one you visited last first, so **⌘T** and **Return** take you back to where you just were. Type a few letters to narrow it, with `name@machine` for a machine. It replaces the queue's filter.
- **Agents can close sessions.** `shepherdr close` closes the agent's own session once its turn ends, or other sessions by name, when you ask it to. A session that's working or needs you stays open unless the agent insists. From another machine, closing a session elsewhere waits for your **CLOSE**. Your machines are offered the updated agent tools.
- **Open a session's folder in Finder** with the folder button in its header, its context menu, or **⇧⌘O**.
- **The queue keeps the open session in sight,** scrolling to it when you open it from Compass, a notification or ⌘T.
- **Lighter on your Mac.** Shepherdr redraws only what a refresh changed and works out the queue once per change. While its window can't be seen, the terminal on screen rests after 30 seconds, other machines are asked every 30 seconds instead of every 5, and browser pages out of sight for 10 minutes let go of their memory. Shepherdr's own SSH commands share one connection per machine.

### Fixed

- Shift with an arrow key, which Codex asks for in some questions, did nothing in the terminal.

### Download and install

- **Apple Silicon (M1 or later), macOS 14 Sonoma or later.** Xcode is not required.
- Download **Shepherdr-…-macos-arm64.dmg**, open it, and drag **Shepherdr.app** to **Applications**. A ZIP of the same app is also available.
- **Required:** install and start [Herdr](https://herdr.dev/docs/) separately. Remote machines use Herdr's saved machine profiles and a CLI with `--machine` support, such as 0.9.3.
- **Recommended:** the [GitHub CLI](https://cli.github.com), signed in with `gh auth login`, to confirm pull requests and issues, fetch their titles and watch pull requests' CI checks.
- Terminals require `terminal session observe/control` on the target machine (verified with CLI/server 0.9.3). Remote terminals, folder checks, machine load and commands left running use an already-trusted SSH host and noninteractive authentication on Unix-like hosts.
- The agent tools are optional. Shepherdr installs them over SSH only when you accept, writing only `~/.shepherdr` and the agents' skill folders, without `sudo`; on each machine they need only `sh` and Herdr.
- Once installed, Shepherdr offers new versions as they come out and updates itself in place, only with an app signed by the same team and notarized by Apple.
- Shepherdr is **signed with The Agile Monkeys' Developer ID and notarized by Apple**: it opens like any other download, with no trip to **Privacy & Security**.
- macOS asks for permission the first time Shepherdr notifies you or you dictate. Dictation downloads its speech model (about 460 MB) from Hugging Face once, after asking.
- `SHA256SUMS` contains checksums for both downloads. In their download directory, run `shasum -a 256 -c SHA256SUMS` after downloading both packages.

Shepherdr is an independent client for Herdr. It creates, renames or closes sessions and changes machines only when you ask; input goes only to the unlocked session you are viewing, and never replaces another client's input without an explicit Take Over.
