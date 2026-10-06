# Shepherdr guide

A native macOS console for the coding agents running in your [Herdr](https://herdr.dev/) workspaces, locally and over SSH.

The sidebar is your prioritized queue of sessions. Pick one and its live terminal opens in the work area, with a composer underneath for the next prompt. Shepherdr is an independent, open-source client; it is not an official Herdr application and is not affiliated with the Herdr project.

## Features

- **Session queue:** every agent session in your own priority order, shown by workspace and what the agent is doing. Drag to reorder, use the ▲▼ controls, **⌥⌘↑ / ⌥⌘↓**, or jump with **⌘1…⌘9**. Gather sessions into **groups** that you prioritize like a single session, each with its own internal order.
- **Work area:** the selected session's live terminal, embedded in the main window like Herdr's own client. Switching sessions detaches the previous one; the pane keeps running in Herdr.
- **Type in the terminal:** work in the agent's own TUI; **⇧⏎** adds a line instead of sending. A bottom bar has quick keys (Esc, ^C, Tab, arrows, Return).
- **Optional prompt editor:** open it (**⌘L**) for long prompts you want to think through and edit with the mouse. **⏎** sends, **⇧⏎** adds a line, **↑/↓** recall this session's prompts.
- **Dictation:** record a prompt (**⇧⌘D**); it is transcribed on this Mac and lands in the prompt editor for you to review.
- **Unlocked by default:** sessions open with input enabled. Click the padlock to lock one read-only. If another client controls the terminal, Shepherdr stays locked and offers an explicit **Take Over**.
- **A browser per session:** click a link in the terminal and it opens in the session's own browser, next to the terminal; its tabs stay put while you work elsewhere. **⌘-click** opens your default browser instead.
- **Sessions on hold:** mark a session as waiting for others, such as a planner waiting for the subagents it launched. It shows an hourglass, and its related sessions are one click away.
- **Create and close sessions:** **⌘N** creates a Herdr workspace with a shell in a folder; start Claude Code, Codex or any other supported agent in it and it joins the queue. Create one in a group with its **+**, or next to a session with **New Session in Same Folder…**. **Close Session…** in a session's context menu ends its pane after confirmation.
- Overview with working / needs-you / done / idle counts and session cards; plain shell panes are listed separately.
- **Machines** in **Settings → Machines** (⌘,): add SSH machines, disable them to stop polling, or remove them from Herdr's catalog.
- Concurrent queries, independent connection states, and last-known data marked stale after failure.
- Automatic refresh (5, 15, 30 or 60 seconds), pause, manual refresh with **⌘R**, and refresh after wake.
- A dark phosphor console theme in [Fira Code](https://github.com/tonsky/FiraCode) (bundled), any installed monospaced font for the terminal, an 8-bit logo of a German Shepherd watching its flock, and a pixel-art app icon of a German Shepherd in Matrix digital rain.

No worktree management, notifications, or menu-bar UI. Input goes only to the session you are viewing, while it is unlocked; creating, closing and machine changes happen only when you ask, and closing asks for confirmation.

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

Start Herdr normally on your Mac. Shepherdr queries the **local default session** and lists the agents that Herdr itself reports. A shell pane is not an agent: panes without one appear under **Shells**, or in their group when created there, and move into the queue as soon as Herdr detects an agent in them. Machine status and failure details are in **Settings → Machines**.

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

The sidebar queue is your saved order across all machines; its numbers are each session's priority. Drag a session to a new position (a line shows where it will land), use the ▲▼ controls that appear on hover or selection, press **⌥⌘↑ / ⌥⌘↓** for the selected session, or choose **Move to Top/Bottom** from its context menu. **⌘1…⌘9** open the first nine sessions, **⌘[ / ⌘]** step through them and **⌘0** returns to the overview.

Ordering is saved on this Mac and restored when you reopen Shepherdr. Newly discovered sessions join the end. Refreshes, lifecycle changes, temporary disconnections and an incomplete machine catalog do not erase existing positions. Priorities follow the machine profile and terminal ID, so sessions with identical names on different machines stay independent. A newly created terminal has a new identity and joins the end.

### Groups

Groups gather sessions however you like: a project, a client, personal work. Create one with **+ group** in the queue header, **Session → New Group…**, or **Move to Group → New Group…** in a session's context menu; a group created from a session takes its place in the queue.

- A group is one position in the queue: drag its header, use its ▲▼ controls or its context menu to prioritize it like a session. Inside, its sessions keep their own order with the same controls.
- Drop a session on a group's header to add it, or between grouped sessions to place it exactly. **Move to Group** and **Remove from Group** in a session's context menu do the same without dragging. Groups do not nest.
- Click a header to collapse or expand the group. A collapsed group still shows how many of its sessions need you, and its sessions are skipped by **⌘1…⌘9**. Filtering shows matching sessions even inside collapsed groups.
- Hover a header and click **+** (or use **New Session in Group…** in its context menu) to create a session in the group. Until you start an agent in it, it is listed in the group as a shell.
- **Rename…** and **Ungroup** are in the header's context menu. Ungrouping leaves the sessions where the group was, in their order; it never closes them.

Numbers run through the whole queue, groups included, so they always reflect overall priority.

You can reorder while filtering the queue (**⌘F**): movement is relative to the visible sessions, and hidden sessions retain their saved slots, so a filtered list can have gaps in its numbers. Only stable identifiers, their order, and group names and collapse state are stored in the app's local preferences. Priorities are independent of Herdr state and are not synchronized between Macs.

## Create and close sessions

**⌘N** (or **+** in the sidebar) opens **New Session**: choose a folder (on the selected machine) and an optional name. Shepherdr runs `herdr workspace create --cwd … --label …` and opens its shell. Start an agent there as you would in any terminal: Herdr detects it, and the session joins the queue within one refresh.

On this Mac, **CHOOSE…** always starts in your projects folder, `~/projects` unless you change it in **Settings → General**, and a folder name alone means a folder inside it. **New Session in Same Folder…** in a session's or shell's context menu prefills its folder and machine and places the new session right after it, in the same group. A group header's **+** places it in that group.

**Close Session…** in a session's context menu asks for confirmation, then runs `herdr pane close`. It is deliberately only in the context menu, away from everyday controls. This ends the agent process. When it is the workspace's last pane, Herdr closes the workspace too.

## Work with a session

1. Select a session in the queue or an overview card. Its terminal opens in the work area with keyboard focus, unlocked: the open padlock in the header means your input goes to the session.
2. Type in the terminal as you would in any terminal. **⇧⏎** sends Esc-Return, which Claude Code, Codex and Gemini read as a new line, so it no longer submits the first line of a multi-line prompt.
3. For longer prompts, open the prompt editor with **✎ PROMPT** in the bottom bar or **⌘L**. It is closed by default and keeps its draft while closed (the button shows a •). **⏎** or **SEND** sends the prompt as a bracketed paste followed by a separate Return, so agents receive it verbatim, then closes the editor and returns to the terminal.
4. Click the padlock (or press **⌘E**) to lock the session read-only; click it again to unlock. A locked session's editor still takes drafts. **⌘⎋** sends Escape, which interrupts most agents.
5. Click a web link in the terminal to open it in the session's browser, or **⌘-click** it to open your default browser. Links agents mark up explicitly and plain-text `http(s)://` URLs both work, including URLs that wrap across lines; the pointer turns into a hand over them.
6. Selecting another session, quitting Shepherdr or pressing ↻ only detaches this client. Herdr keeps the pane and its process running.

Shepherdr never takes input away from another client implicitly. If one is attached, the session stays locked with a notice; **Take Over** is an explicit choice that uses Herdr's `--takeover`. If another client later takes over, Shepherdr locks the session again. Terminal resizing uses Herdr's supported viewport/resize messages. Mouse reporting and browsing Herdr's historical scrollback are not implemented; native text selection, copying and keyboard/paste input are supported. Drafts and prompt history are kept in memory per session and are never written to disk.

### Browser

Each session has its own browser column, to the right of the terminal. Clicking a link opens it there in a new tab, or switches to the tab already showing it; **◫ BROWSER** in the bottom bar or **⌘B** shows or hides the column, and **+** opens an empty tab. The tabs stay loaded, scrolled and signed in while you switch sessions, so a pull request you are reviewing is still where you left it. Pages that open new windows open new tabs. **⧉** opens the current page in your default browser.

Sign-ins are shared by every session's browser and persist across launches, in WebKit's own storage for Shepherdr. Safari's sessions and cookies cannot be shared with other apps, so sign in once here, or **⌘-click** links to use Safari. Tabs live in memory and close when you quit or close the session.

### Dictation

**🎙 DICTATE** in the bottom bar, or **⇧⌘D**, starts recording right away and opens the prompt editor. Press **STOP** (or **⇧⌘D** again) and the transcript is added to the draft for you to read and edit before sending; **×** discards the recording. Transcription runs on this Mac with NVIDIA's [Parakeet TDT v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) through [FluidAudio](https://github.com/FluidInference/FluidAudio), the same engine as [scribe](https://github.com/theam/scribe). It detects the language among 25 European ones, and handles English technical terms inside Spanish speech well.

The model is about 460 MB. The first time, Shepherdr asks before downloading it from Hugging Face; if scribe already downloaded it, Shepherdr reuses that copy. It loads into memory while you speak the first time after each launch. Your voice is kept in memory only while recording and never leaves the Mac. Shepherdr asks for microphone access the first time you dictate.

## Sessions on hold

When one session has to wait for others, such as a planner that launched subagents, choose **Wait For** in its context menu and tick the sessions it waits for. The session shows an hourglass in the queue instead of its state: blue while any of them is still working or needs you, green once they have all finished.

Opening a session on hold shows a panel above its terminal with the sessions it waits for and their state. Click one to open it, **×** to stop waiting for it, **+** to add more, or **RESUME** to take the session off hold. Sessions that others are waiting for list them under **WAITED ON BY**. Holds are saved on this Mac with your priorities and only contain session identifiers. Closing a session from Shepherdr removes its holds.

The interface uses the bundled Fira Code. **Settings → General → Terminal font** chooses the font and size for the terminal and prompt editor from the monospaced families installed on this Mac.

For remote terminals, Shepherdr invokes the remote installed Herdr CLI through `/usr/bin/ssh` using the saved profile's target and session. Host keys must already be trusted and authentication must work without a prompt. It uses the host's `herdr` on PATH, then checks `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin` and `~/.cargo/bin`. Connection or compatibility failures appear in the work area and leave the rest of the app usable.

