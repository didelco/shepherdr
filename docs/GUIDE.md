# Shepherdr guide

A native macOS console for the coding agents running in your [Herdr](https://herdr.dev/) workspaces, locally and over SSH.

The sidebar is your prioritized queue of sessions. Pick one and its live terminal opens in the work area, with a composer underneath for the next prompt. Shepherdr is an independent, open-source client; it is not an official Herdr application and is not affiliated with the Herdr project.

## Features

- **Session queue:** every agent session in your own priority order, shown by workspace and what the agent is doing. Drag to reorder, use the ▲▼ controls, **⌥⌘↑ / ⌥⌘↓**, or jump with **⌘1…⌘9**.
- **Work area:** the selected session's live terminal, embedded in the main window like Herdr's own client. Switching sessions detaches the previous one; the pane keeps running in Herdr.
- **Prompt composer:** type the next prompt below the terminal. **⏎** sends, **⇧⏎** adds a line, **↑/↓** recall this session's prompts. Quick keys send Esc, ^C, Tab, arrows and Return.
- **Live by default:** sessions open with input enabled. If another client controls the terminal, Shepherdr watches instead and offers an explicit **Take Over**.
- **Create and close sessions:** **⌘N** creates a Herdr workspace in a folder and starts Claude Code, Codex, Gemini, opencode or another supported agent (or just a shell). **Close Session…** (⇧⌘W) ends a session's pane after confirmation.
- Overview with working / needs-you / done / idle counts and session cards; plain shell panes are listed separately.
- **Machines** in **Settings → Machines** (⌘,): add SSH machines, disable them to stop polling, or remove them from Herdr's catalog.
- Concurrent queries, independent connection states, and last-known data marked stale after failure.
- Automatic refresh (5, 15, 30 or 60 seconds), pause, manual refresh with **⌘R**, and refresh after wake.
- A dark phosphor console theme in [Fira Code](https://github.com/tonsky/FiraCode) (bundled), any installed monospaced font for the terminal, an 8-bit logo of a German Shepherd watching its flock, and a pixel-art app icon of a German Shepherd in Matrix digital rain.

No worktree management, notifications, or menu-bar UI. Input goes only to the session you are viewing in Live mode; creating, closing and machine changes happen only when you ask, and closing asks for confirmation.

## Download and install

Download the `.dmg` from [the latest GitHub release](../../../releases/latest), open it, and drag **Shepherdr.app** to **Applications**. A `.zip` of the same app and SHA-256 checksums are also available. Requires **Apple Silicon (M1 or later) and macOS 14 Sonoma or later**; no Xcode is needed to run the download.

Current downloads have an **ad hoc signature and are not notarized by Apple**. If macOS blocks the first launch because the developer cannot be verified and you trust this download, use **System Settings → Privacy & Security → Open Anyway** for Shepherdr. Follow [Apple's instructions](https://support.apple.com/en-us/102445); managed Macs may require administrator approval.

Install and start Herdr separately, then open Shepherdr. The app reads your existing sessions and saved machines.

## Requirements

- macOS 14 Sonoma or later.
- A locally installed `herdr` supporting `machine list --json` and `api snapshot`.
- For remote machines, a local Herdr build with the documented global `--machine` option, plus compatible remote installations and an already-running server. Herdr CLI 0.9.3 provides that option; 0.9.0 does not. Shepherdr shows an incompatibility message on older CLIs.
- For interactive terminals, the Herdr installation on the target machine must support `terminal session observe` and `terminal session control`. Verified with CLI/server 0.9.3. Remote terminals require a Unix-like host, OpenSSH access and an existing saved profile.

Local integration has been verified with CLI 0.9.3 querying an existing, compatible 0.9.0 server. Updating the CLI does not require replacing a compatible running server.

## Connect Herdr

Start Herdr normally on your Mac. Shepherdr queries the **local default session** and lists the agents that Herdr itself reports. A shell pane is not an agent: panes without one appear under **Shells**. Machine status and failure details are in **Settings → Machines**.

Configure SSH machines in Herdr, then refresh Shepherdr:

```sh
herdr machine add workbox --label "Build machine"
# A saved profile can target a named remote session:
herdr machine add lab --label "Lab" --remote-session agents
herdr machine list --json
```

One profile represents one session, not every session on its host. Disabled profiles remain visible and are not polled. You can also add, disable, enable and remove machines in **Settings → Machines**; Shepherdr runs the same `herdr machine` commands. Adding a machine lets Herdr prepare its remote server, which can install or start Herdr there. Shepherdr never prompts for credentials: SSH must authenticate without interaction, so load passphrase-protected keys into your SSH agent first, or run the displayed `herdr machine add` command in Terminal. Removing a machine only forgets its profile; its remote server and sessions keep running. Shepherdr never stops or restarts a Herdr server.

Shepherdr locates Herdr in `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.cargo/bin`, then absolute entries in `PATH`. For a custom installation, set `SHEPHERDR_HERDR_PATH` to the absolute executable path in **Scheme → Run → Arguments → Environment Variables**, or launch the built app's executable with that variable:

```sh
SHEPHERDR_HERDR_PATH=/absolute/path/to/herdr \
  build/Build/Products/Debug/Shepherdr.app/Contents/MacOS/Shepherdr
```

Local executable discovery does not source shell startup files. Inherited `HERDR_SESSION`, `HERDR_SOCKET_PATH`, and pane/workspace/tab routing variables are cleared so opening Shepherdr from an agent pane cannot silently retarget Local. Herdr's own configuration environment is otherwise retained.

## Prioritize sessions

The sidebar queue is your saved order across all machines; its numbers are each session's priority. Drag a session to a new position, use the ▲▼ controls that appear on hover or selection, press **⌥⌘↑ / ⌥⌘↓** for the selected session, or choose **Move to Top/Bottom** from its context menu. **⌘1…⌘9** open the first nine sessions, **⌘[ / ⌘]** step through them and **⌘0** returns to the overview.

Ordering is saved on this Mac and restored when you reopen Shepherdr. Newly discovered sessions join the end. Refreshes, lifecycle changes, temporary disconnections and an incomplete machine catalog do not erase existing positions. Priorities follow the machine profile and terminal ID, so sessions with identical names on different machines stay independent. A newly created terminal has a new identity and joins the end.

You can reorder while filtering the queue (**⌘F**): movement is relative to the visible sessions, and hidden sessions retain their saved slots, so a filtered list can have gaps in its numbers. Only stable identifiers and their order are stored in the app's local preferences. Priorities are independent of Herdr state and are not synchronized between Macs.

## Create and close sessions

**⌘N** (or **+** in the sidebar) opens **New Session**: choose a folder (on the selected machine), an optional name, and an agent. Shepherdr runs `herdr workspace create --cwd … --label …` and then `herdr agent start … --kind …` in its first pane, and opens it. If the agent stops at a startup question, such as trusting the folder, the session opens with a notice so you can answer it in the terminal. **Shell only** skips the agent.

**Close Session…** in a session's context menu, the ✕ in its header or **⇧⌘W** asks for confirmation, then runs `herdr pane close`. This ends the agent process. When it is the workspace's last pane, Herdr closes the workspace too.

## Work with a session

1. Select a session in the queue or an overview card. Its terminal opens in the work area in **LIVE** mode.
2. Type the next prompt in the composer and press **⏎**. Multi-line prompts are sent as a bracketed paste followed by a separate Return, so agents and shells receive them verbatim. **⌘L** focuses the composer; you can also click the terminal and type into it directly.
3. **WATCH** (or **⌘E**) switches to read-only observation; **⌘E** again goes live. **⌘⎋** sends Escape, which interrupts most agents.
4. Selecting another session, quitting Shepherdr or pressing ↻ only detaches this client. Herdr keeps the pane and its process running.

Shepherdr never takes input away from another client implicitly. If one is attached, the session falls back to watching with a notice; **Take Over** is an explicit choice that uses Herdr's `--takeover`. If another client later takes over, Shepherdr returns to watching. Terminal resizing uses Herdr's supported viewport/resize messages. Mouse reporting and browsing Herdr's historical scrollback are not implemented; native text selection, copying and keyboard/paste input are supported. Drafts and prompt history are kept in memory per session and are never written to disk.

The interface uses the bundled Fira Code. **Settings → General → Terminal font** chooses the font and size for the terminal and prompt composer from the monospaced families installed on this Mac.

For remote terminals, Shepherdr invokes the remote installed Herdr CLI through `/usr/bin/ssh` using the saved profile's target and session. Host keys must already be trusted and authentication must work without a prompt. It uses the host's `herdr` on PATH, then checks `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin` and `~/.cargo/bin`. Connection or compatibility failures appear in the work area and leave the rest of the app usable.

