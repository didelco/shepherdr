Native macOS console for herding your coding agents across your Herdr machines: one prioritized queue, the real terminal of every session, a browser per session, and a notification when it's your turn.

### First public release

Shepherdr is now open source under the MIT License, donated by The Agile Monkeys.

- **One queue for every agent.** Sessions from all your Herdr machines, local and SSH, in your own priority order: drag and drop, ▲▼, **⌥⌘↑ / ⌥⌘↓** and **⌘1…⌘9**. Gather sessions into groups that you prioritize as one.
- **The real terminal, embedded.** Type straight into the agent's TUI. **⇧⏎** adds a line, Option types your keyboard layout's characters (such as **⌥2** for @), and selecting text copies it. Open the prompt editor (**⌘L**) for longer prompts, or dictate them (**⇧⌘D**), transcribed on your Mac.
- **A browser per session.** Click a link in the terminal and it opens next to it, in tabs that stay put while you hop between sessions. **⌘-click** opens your default browser.
- **Know when it's your turn.** A macOS notification tells you when an agent finishes or needs you, with what it last said. Click it to open the session.
- **Sessions on hold.** Mark a planner as waiting for its subagents: they nest under it in a collapsible tree, and its hourglass turns green when they're done.
- **Agents that talk to each other.** Copy a session's Herdr pane ID, or a reference with the `herdr agent prompt` command another agent can run to report back to it.
- **Drive or just watch.** Sessions open unlocked; the padlock makes one read-only. If another client has input, Shepherdr watches and offers an explicit **Take Over**.
- **Spawn and dismiss sessions.** **⌘N** creates a shell in a folder; start any agent in it and the queue picks it up. **Close Session…** asks first.
- **Machines** live in **Settings → Machines** (⌘,), where you can add, disable, enable and remove them.
- Phosphor green and an 8-bit soul: the bundled Fira Code, a pixel-art flock, and a German Shepherd keeping watch. *Do androids dream of electric sheep?*

### Download and install

- **Apple Silicon (M1 or later), macOS 14 Sonoma or later.** Xcode is not required.
- Download **Shepherdr-…-macos-arm64.dmg**, open it, and drag **Shepherdr.app** to **Applications**. A ZIP of the same app is also available.
- Install and start [Herdr](https://herdr.dev/docs/) separately. Remote machines use Herdr's saved machine profiles and a CLI with `--machine` support, such as 0.9.3.
- Terminals require `terminal session observe/control` on the target machine (verified with CLI/server 0.9.3). Remote terminals use an already-trusted SSH host and noninteractive authentication on Unix-like hosts.
- This release has an **ad hoc signature and is not notarized by Apple**. If macOS blocks the first launch and you trust this download, use **System Settings → Privacy & Security → Open Anyway** for Shepherdr. See [Apple's instructions](https://support.apple.com/en-us/102445). Managed Macs may require administrator approval.
- macOS asks for permission the first time Shepherdr notifies you or you dictate. Dictation downloads its speech model (about 460 MB) from Hugging Face once, after asking.
- `SHA256SUMS` contains checksums for both downloads. In their download directory, run `shasum -a 256 -c SHA256SUMS` after downloading both packages.

Shepherdr is an independent client for Herdr. It creates or closes sessions and changes machines only when you ask; input goes only to the unlocked session you are viewing, and never replaces another client's input without an explicit Take Over.
