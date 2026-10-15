# Compass

Build today's page: where my agent sessions stand, and what deserves my attention next.

## Gather

- Read `context/sessions.json`: every session in my Shepherdr queue, in my order, with its state, machine, folder, agent, pull requests and their checks.
- For sessions that need me, or that finished since the last run, read what they last said with `herdr agent read NAME` (for other machines, `~/.shepherdr/bin/shepherdr machines` says how to reach them).

## Build the page

- Headline: one line on how things stand.
- Needs you: blocked sessions first, with what each one is asking, and a button to open it.
- Finished: what each one delivered, with its pull request and whether its checks passed.
- In progress: one line each.
- Stale: sessions idle for more than a day, as candidates to close.
- Next: up to three actions. When one needs a new session, add a button that starts it.
- Leave the day strip empty: I haven't connected a calendar yet.

## Make it yours

End the page with a short card titled "Make it yours". Say that this page only looks at my sessions, and that I can change what it covers by asking you in the terminal beside it. Offer three `ask` buttons with ideas that fit what you saw today, such as connecting my calendar to fill the day strip, my mail or chat to triage what came in, or changing when the page updates.
