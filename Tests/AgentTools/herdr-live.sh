#!/bin/sh
# Runs the agent tools' command line against a real Herdr, in a server of its own: a scratch
# home, so it never touches your sessions. Catches changes in what Herdr answers, which the fake
# herdr of test.sh can't.
#   sh Tests/AgentTools/herdr-live.sh
# Needs herdr on PATH. Starts no agents: it spawns shells.

set -u
command -v herdr >/dev/null 2>&1 || { echo "herdr is not installed: skipping the live test"; exit 0; }
here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
tools="$here/../../Sources/ShepherdrCore/Resources/AgentTools"
# Herdr's socket lives in the home folder, and socket paths must be short: hence /tmp.
home=$(mktemp -d /tmp/shepherdr-live.XXXXXX)
failures=0

h() { env -u HERDR_SESSION -u HERDR_SOCKET_PATH -u HERDR_PANE_ID -u HERDR_TAB_ID -u HERDR_WORKSPACE_ID -u HERDR_ENV \
    HOME="$home" herdr "$@"; }
cleanup() {
    h server stop >/dev/null 2>&1
    rm -rf "$home"
}
trap cleanup EXIT
problem() {
    printf 'FAIL: %s\n' "$1"
    failures=$((failures + 1))
}
# Waits up to 30 seconds for a file.
wait_for() {
    tries=0
    while [ ! -e "$1" ] && [ "$tries" -lt 60 ]; do sleep 0.5; tries=$((tries + 1)); done
    [ -e "$1" ]
}

mkdir -p "$home/.shepherdr" "$home/work"
cp -R "$tools/bin" "$tools/skills" "$tools/VERSION" "$home/.shepherdr/"
printf '# shepherdr machines 1 rev 000000000000 2026-10-15T10:15:02Z\nlive\there\t-\n' >"$home/.shepherdr/machines"
# A plain shell keeps the panes quiet and fast.
printf 'PS1="$ "\n' >"$home/.profile"
SHELL=/bin/sh h server >"$home/server.log" 2>&1 &
wait_for "$home/.config/herdr/herdr.sock" || { cat "$home/server.log"; echo "FAIL: the server didn't start"; exit 1; }

caller=$(h workspace create --cwd "$home/work" --label caller --no-focus | grep -o '"pane_id":"[^"]*"' | head -n 1 | cut -d'"' -f4)
[ -n "$caller" ] || { echo "FAIL: no workspace"; exit 1; }
cli="$home/.shepherdr/bin/shepherdr"

# Spawning from a pane: a new workspace, a letter, and the caller's doorbell.
h pane run "$caller" "$cli spawn --shell --name child > $home/spawn.txt 2>&1; echo \$? > $home/spawn.done" >/dev/null
wait_for "$home/spawn.done" || problem "spawn never finished"
[ "$(cat "$home/spawn.done" 2>/dev/null)" = 0 ] || problem "spawn failed: $(cat "$home/spawn.txt")"
grep -q "Started a shell, child, on live" "$home/spawn.txt" || problem "unexpected spawn output: $(cat "$home/spawn.txt")"
# Letter IDs are times and hex digits: listing them is safe, and sorts them oldest first.
# shellcheck disable=SC2012
letter=$(ls "$home/.shepherdr/outbox" | head -n 1)
[ -n "$letter" ] || problem "spawn left no letter"
json=$(cat "$home/.shepherdr/outbox/$letter/letter.json" 2>/dev/null)
case $json in *'"kind":"spawned"'*'"child":{"machine":"here","pane":"w'*'"terminal":"'*) ;; *) problem "unexpected letter: $json" ;; esac
snapshot=$(h api snapshot)
case $snapshot in *"\"shepherdr-mail\":\"$letter\""*) ;; *) problem "the doorbell didn't ring on the caller's pane" ;; esac
case $snapshot in *'"label":"child"'*) ;; *) problem "no workspace named child" ;; esac
caller_terminal=$(h pane current --pane "$caller" | grep -o '"terminal_id":"[^"]*"' | cut -d'"' -f4)
case $json in *"\"from\":{\"pane\":\"$caller\",\"terminal\":\"$caller_terminal\"}"*) ;; *) problem "the letter doesn't name its sender: $json" ;; esac

# Splitting the caller's pane.
h pane run "$caller" "$cli spawn --shell --split right > $home/split.txt 2>&1; echo \$? > $home/split.done" >/dev/null
wait_for "$home/split.done" || problem "split never finished"
[ "$(cat "$home/split.done" 2>/dev/null)" = 0 ] || problem "split failed: $(cat "$home/split.txt")"

# A second letter rings the doorbell again.
h pane run "$caller" "$cli notify 'live test' > $home/notify.txt 2>&1; echo \$? > $home/notify.done" >/dev/null
wait_for "$home/notify.done" || problem "notify never finished"
# shellcheck disable=SC2012
newest=$(ls "$home/.shepherdr/outbox" | sort | tail -n 1)
case $(h api snapshot) in *"\"shepherdr-mail\":\"$newest\""*) ;; *) problem "the doorbell didn't ring again" ;; esac

# Folders where sessions work.
h pane run "$caller" "$cli folders > $home/folders.txt 2>&1; echo \$? > $home/folders.done" >/dev/null
wait_for "$home/folders.done" || problem "folders never finished"
grep -q "$home/work" "$home/folders.txt" 2>/dev/null || grep -q "shepherdr-live" "$home/folders.txt" || problem "folders didn't list the work folder: $(cat "$home/folders.txt")"

if [ "$failures" -eq 0 ]; then echo "herdr live test passed ($(herdr --version))"; else echo "$failures failed"; fi
[ "$failures" -eq 0 ]
