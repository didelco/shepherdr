Native macOS console for herding your coding agents across your Herdr machines: one prioritized queue, the real terminal of every session, a browser per session, and a notification when it's your turn.

### What's new in 0.8.6

- **Compass, a page of your day.** A second mode (**⌥⌘2**) where an agent of its own keeps a page of what deserves your attention, updated on the schedule you choose in **Settings → Compass**. Talk to it in its terminal beside the page, and use the page's buttons to start the sessions it suggests. Its pages can be kept in a Git remote and restored from it.
- **Sessions from GitHub links and in worktrees.** Paste a repository's link in **New Session** and Shepherdr opens your clone, or clones it into that machine's projects folder first. Paste a pull request's link and it opens a worktree of its branch, with the pull request in **Resources**. **IN A NEW WORKTREE** works on any folder. Each machine now has a projects folder of its own, in **Settings → Machines**; on another machine, a folder name alone now means a folder inside it.
- **Projects inside groups.** Turn on **projects** in the queue's header to gather each repository's sessions, worktrees included, under a heading of their own.
- **Hand off and close.** A session that others wait for can wrap up with **HANDOFF AND CLOSE**: its agent hands its work back with `shepherdr handoff`, and Shepherdr closes the session once the handoff arrives.
- **Find sessions by typing.** **Wait For…** opens a search instead of a long menu: a few letters, **↑**/**↓** and **Return**, with `@` for a machine.
- **Click a session named in a terminal.** Pane IDs such as `w5:p1`, terminal IDs and other sessions' names open those sessions.

### Fixed

- A session waiting for a shell, such as a script, never stopped waiting. Now the wait ends when the command finishes.
- A session waiting for one that had closed kept waiting and showed "session gone". Closed sessions now drop out of holds.

### Download and install

- **Apple Silicon (M1 or later), macOS 14 Sonoma or later.** Xcode is not required.
- Download **Shepherdr-…-macos-arm64.dmg**, open it, and drag **Shepherdr.app** to **Applications**. A ZIP of the same app is also available.
- **Required:** install and start [Herdr](https://herdr.dev/docs/) separately. Remote machines use Herdr's saved machine profiles and a CLI with `--machine` support, such as 0.9.3.
- **Recommended:** the [GitHub CLI](https://cli.github.com), signed in with `gh auth login`, to confirm pull requests and issues, fetch their titles and watch pull requests' CI checks.
- Terminals require `terminal session observe/control` on the target machine (verified with CLI/server 0.9.3). Remote terminals, folder checks, machine load and commands left running use an already-trusted SSH host and noninteractive authentication on Unix-like hosts.
- The agent tools are optional. Shepherdr installs them over SSH only when you accept, writing only `~/.shepherdr` and the agents' skill folders, without `sudo`; on each machine they need only `sh` and Herdr.
- Shepherdr is **signed with The Agile Monkeys' Developer ID and notarized by Apple**: it opens like any other download, with no trip to **Privacy & Security**.
- macOS asks for permission the first time Shepherdr notifies you or you dictate. Dictation downloads its speech model (about 460 MB) from Hugging Face once, after asking.
- `SHA256SUMS` contains checksums for both downloads. In their download directory, run `shasum -a 256 -c SHA256SUMS` after downloading both packages.

Shepherdr is an independent client for Herdr. It creates, renames or closes sessions and changes machines only when you ask; input goes only to the unlocked session you are viewing, and never replaces another client's input without an explicit Take Over.
