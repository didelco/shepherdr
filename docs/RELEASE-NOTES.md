Native macOS console for herding your coding agents across your Herdr machines: one prioritized queue, the real terminal of every session, a browser per session, and a notification when it's your turn.

### What's new in 0.9.0

From 0.8.7 on, Shepherdr offers this version itself, at the foot of the sidebar.

- **A GitHub inbox in the overview.** The **GITHUB** tab lists the reviews requested from you, your assigned issues and your pull requests, with their checks, from the repositories you follow under **REPOS…** and those your sessions work in. A dot marks what changed since you looked. **SUGGEST ORDER** numbers your pull requests in the order to take them: merge, review, address changes, resolve conflicts, fix checks.
- **Start work from the inbox.** An issue offers **IMPLEMENT** and a pull request **REVIEW**, each opening New Session in its own worktree with a prompt ready. Once a session works on it, the button reads **OPEN** and takes you there. **⌘T** also finds sessions by their pull requests, issues and repository, as in `owner/repo#12`, and the overview's cards show their pull requests like the queue does.
- **Sessions stay as you left them.** Switching no longer reloads a session's terminal and browser from scratch. Shepherdr keeps the ones you visit most, and lets go of the rest only when there are many or macOS runs short of memory.
- **A coffee cup keeps this Mac awake,** so agents working here don't pause when it would doze off. Click it in the sidebar's footer, or right-click it to keep the screen on too. It's off every time Shepherdr opens.
- **One status everywhere.** The queue, the overview, ⌘T, the relations panel and Compass agree on each session's status. A session on hold shows its agent's state again once everything it waits for has finished, instead of **READY**. Holds are also kept in Herdr, so another Mac gets them back.
- **Handoffs and closes are your call.** Agents hand off only when you ask, and every session close an agent asks for waits for your **CLOSE**. A session an agent starts keeps it on hold until it finishes. Your machines are offered the updated agent tools.
- **Compass starts its agent only with this Mac fully awake and online,** so a run that falls in a dark wake no longer starts Claude Code without its claude.ai connectors. Its column says what the run waits for.
- **Fewer questions to GitHub.** What Shepherdr learns about pull requests, issues and their checks is kept for later launches, so it doesn't ask again for what it already knows.

### Fixed

- Shepherdr could freeze for good when it rested or closed a terminal that was still connecting.

### Download and install

- **Apple Silicon (M1 or later), macOS 14 Sonoma or later.** Xcode is not required.
- Download **Shepherdr-…-macos-arm64.dmg**, open it, and drag **Shepherdr.app** to **Applications**. A ZIP of the same app is also available.
- **Required:** install and start [Herdr](https://herdr.dev/docs/) separately. Remote machines use Herdr's saved machine profiles and a CLI with `--machine` support, such as 0.9.3.
- **Recommended:** the [GitHub CLI](https://cli.github.com), signed in with `gh auth login`, to confirm pull requests and issues, fetch their titles, watch pull requests' CI checks and fill the GitHub inbox.
- Terminals require `terminal session observe/control` on the target machine (verified with CLI/server 0.9.3). Remote terminals, folder checks, machine load and commands left running use an already-trusted SSH host and noninteractive authentication on Unix-like hosts.
- The agent tools are optional. Shepherdr installs them over SSH only when you accept, writing only `~/.shepherdr` and the agents' skill folders, without `sudo`; on each machine they need only `sh` and Herdr.
- Once installed, Shepherdr offers new versions as they come out and updates itself in place, only with an app signed by the same team and notarized by Apple.
- Shepherdr is **signed with The Agile Monkeys' Developer ID and notarized by Apple**: it opens like any other download, with no trip to **Privacy & Security**.
- macOS asks for permission the first time Shepherdr notifies you or you dictate. Dictation downloads its speech model (about 460 MB) from Hugging Face once, after asking.
- `SHA256SUMS` contains checksums for both downloads. In their download directory, run `shasum -a 256 -c SHA256SUMS` after downloading both packages.

Shepherdr is an independent client for Herdr. It creates, renames or closes sessions and changes machines only when you ask; input goes only to the unlocked session you are viewing, and never replaces another client's input without an explicit Take Over.
