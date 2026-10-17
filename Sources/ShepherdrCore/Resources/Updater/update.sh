#!/bin/sh
# Updates Shepherdr in place: downloads a release's ZIP, checks it, waits for the running app to
# quit, puts the new app where the old one was and opens it.
#
#   update.sh --app /Applications/Shepherdr.app --version 0.8.7 --team TEAMID \
#             --bundle-id com.theagilemonkeys.Shepherdr --zip URL --sums URL \
#             --status FILE [--pid PID] [--no-relaunch] [--check-only]
#
# Nothing is replaced unless the download matches the release's SHA256SUMS and the new app is
# validly signed by the same Apple team as the app that asked, has its bundle identifier and
# the version expected, and passes Gatekeeper. Shepherdr reads progress from standard output:
#
#   shepherdr-update downloading | verifying | ready | failed <why>
#
# On `ready` Shepherdr quits; from then on this script writes nothing there, waits for it to
# exit, swaps the apps and opens the new one. What happened goes to the status file, which
# Shepherdr reads when it opens again: `updated <version>` or `failed <why>`. When anything
# goes wrong after the old app was moved aside, it is put back and opened again.

set -u
umask 022

app='' version='' team='' bundle_id='' zip='' sums='' status='' pid='' relaunch=true check_only=false
work=''
announced=false

say() {
    $announced || printf 'shepherdr-update %s\n' "$*"
}

record() {
    [ -n "$status" ] && printf '%s\n' "$*" >"$status"
}

fail() {
    if $announced; then record "failed $*"; else say "failed $*"; fi
    exit 1
}

trap '[ -z "$work" ] || rm -rf "$work"' EXIT

while [ $# -gt 0 ]; do
    case $1 in
        --app) app=${2-}; shift 2 ;;
        --version) version=${2-}; shift 2 ;;
        --team) team=${2-}; shift 2 ;;
        --bundle-id) bundle_id=${2-}; shift 2 ;;
        --zip) zip=${2-}; shift 2 ;;
        --sums) sums=${2-}; shift 2 ;;
        --status) status=${2-}; shift 2 ;;
        --pid) pid=${2-}; shift 2 ;;
        --no-relaunch) relaunch=false; shift ;;
        --check-only) check_only=true; shift ;;
        *) fail "Unknown option $1." ;;
    esac
done

case $app in
    /*.app) ;;
    *) fail "The app to update must be an absolute path to a .app." ;;
esac
[ -d "$app" ] || fail "$app isn't there."
case $version in
    ''|*[!0123456789.]*) fail "Expected a version such as 0.8.7." ;;
esac
# An app without a team, such as a local build, has no identity an update could match.
case $team in
    ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789]*) fail "Only an app signed with a Developer ID can update itself." ;;
esac
[ -n "$bundle_id" ] || fail "The bundle identifier is missing."
case $zip in
    https://*|file://*) ;;
    *) fail "The download must come over HTTPS." ;;
esac
case $sums in
    https://*|file://*) ;;
    *) fail "The checksums must come over HTTPS." ;;
esac
case $pid in
    ''|*[!0123456789]*) [ -z "$pid" ] || fail "The process ID isn't a number." ;;
esac
folder=$(dirname -- "$app")
[ -w "$folder" ] || fail "Shepherdr can't write to $folder. Download the new version from GitHub instead."

work=$(mktemp -d "${TMPDIR:-/tmp}/shepherdr-update.XXXXXX") || fail "Couldn't make a temporary folder."

# MARK: Download and check

say downloading
name=${zip##*/}
curl -fsSL --retry 2 --connect-timeout 20 -o "$work/$name" -- "$zip" || fail "Couldn't download $name."
curl -fsSL --retry 2 --connect-timeout 20 -o "$work/SHA256SUMS" -- "$sums" || fail "Couldn't download the release's checksums."

say verifying
expected=$(awk -v name="$name" '$2 == name || $2 == "*" name { print $1; exit }' "$work/SHA256SUMS")
[ -n "$expected" ] || fail "The release's checksums don't list $name."
actual=$(shasum -a 256 "$work/$name" | awk '{ print $1 }')
[ "$actual" = "$expected" ] || fail "$name doesn't match the release's checksum."

mkdir "$work/unpacked" || fail "Couldn't make a temporary folder."
ditto -x -k "$work/$name" "$work/unpacked" || fail "Couldn't unpack $name."
new="$work/unpacked/${app##*/}"
[ -d "$new" ] || new="$work/unpacked/Shepherdr.app"
[ -d "$new" ] || fail "$name doesn't hold Shepherdr.app."

codesign --verify --deep --strict -- "$new" 2>/dev/null || fail "The new app's signature isn't valid."
signer=$(codesign -dv -- "$new" 2>&1 | sed -n 's/^TeamIdentifier=//p')
[ "$signer" = "$team" ] || fail "The new app isn't signed by the same team as this one."
info="$new/Contents/Info.plist"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info" 2>/dev/null)" = "$bundle_id" ] \
    || fail "The new app is a different app."
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info" 2>/dev/null)" = "$version" ] \
    || fail "The new app isn't version $version."
# Gatekeeper's verdict, unless assessments are turned off on this Mac.
if spctl --status 2>/dev/null | grep -q 'assessments enabled'; then
    spctl --assess --type execute -- "$new" 2>/dev/null || fail "Gatekeeper doesn't accept the new app."
fi

if $check_only; then
    say verified
    exit 0
fi

# MARK: Swap

say ready
# Shepherdr quits now, and the pipe it read goes with it.
announced=true
exec >/dev/null 2>&1
trap '' HUP PIPE

if [ -n "$pid" ]; then
    waited=0
    while kill -0 "$pid" 2>/dev/null; do
        [ "$waited" -ge 120 ] && fail "Shepherdr didn't quit, so it wasn't replaced."
        sleep 0.5
        waited=$((waited + 1))
    done
fi

previous="$work/previous.app"
mv -- "$app" "$previous" || fail "Couldn't move the old app aside."
if ! mv -- "$new" "$app"; then
    mv -- "$previous" "$app"
    record "failed Couldn't put the new app in place; the old one is back."
    $relaunch && open -- "$app"
    exit 1
fi
record "updated $version"
$relaunch && open -- "$app"
exit 0
