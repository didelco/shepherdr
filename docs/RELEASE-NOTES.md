Native macOS console for herding your coding agents across your Herdr machines: one prioritized queue, the real terminal of every session, a browser per session, and a notification when it's your turn.

### What's new in 0.8.5

- **Terminals reconnect on their own.** When a terminal's connection drops, the banner counts down to the next attempt and Shepherdr tries again, waiting twice as long each time, up to 5 minutes. After an hour of trying it says how many times it tried and leaves **RECONNECT** to you. Time asleep with the lid closed doesn't count. The ↻ button in the session's header is gone.
- **Agents that coordinate.** Shepherdr can install a small `shepherdr` command and a skill for Claude Code and Codex on each of your machines, Linux included. Ask an agent to "start a session on buildbox that fixes the failing test": the new session starts there, nests under the agent's own, and hands its result back as a prompt when it's done. Agents can also pin links to Resources, open pages in the session's browser and notify you. Requests from other machines wait for your approval in the session's mail panel. **Settings → Agents** manages the tools on each machine.
- **The guide comes with the app.** **Help → Shepherdr Guide** (**⌘?**), or **?** at the foot of the sidebar, opens a visual quick guide in English and Spanish in the built-in browser, and **Help → Herdr Documentation** opens there too. The overview has a browser of its own for them (**⌘B**).

### Fixed

- The bottom bar showed **RESOURCES** and **BROWSER** as bare icons in most windows. The labels now stay whenever they fit.

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
