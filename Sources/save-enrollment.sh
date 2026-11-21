#!/bin/bash
set -euo pipefail

base="/Library/Application Support/MacFace"
input=$1
uid=$2
[[ "$(id -u)" == 0 && "$uid" =~ ^[0-9]+$ && "$uid" == "$(cat "$base/installed-uid")" &&
   "$uid" == "$(stat -f %u /dev/console)" ]]
account=$(id -un "$uid")
template="$base/enrollment-$uid.bin"
service="gui/$uid/com.macface.agent"
socket="/tmp/com.macface.agent.$uid.sock"
if [[ "$input" == --remove ]]; then
    /bin/launchctl bootout "$service" >/dev/null 2>&1 || true
    if [[ -S "$socket" && "$(stat -f %u "$socket")" == "$uid" ]]; then
        /bin/rm -f "$socket"
    fi
    /bin/rm -f "$template"
    exit 0
fi
[[ -f "$input" && ! -L "$input" && "$(stat -f '%u:%z' "$input")" == "$uid:512" ]]
staged=$(mktemp "$base/enrollment-new.XXXXXX")
backup=$(mktemp "$base/enrollment-backup.XXXXXX")
launchAgent=/Library/LaunchAgents/com.macface.agent.plist
hadTemplate=0
replaced=0
stopped=0

restart() {
    /bin/launchctl bootout "$service" >/dev/null 2>&1 || true
    if [[ -S "$socket" && "$(stat -f %u "$socket")" == "$uid" ]]; then
        /bin/rm -f "$socket"
    fi
    /bin/launchctl bootstrap "gui/$uid" "$launchAgent"
}

cleanup() {
    status=$?
    trap - EXIT
    if (( status != 0 && replaced )); then
        if (( hadTemplate )); then
            /bin/mv -f "$backup" "$template"
        else
            /bin/rm -f "$template"
        fi
    fi
    if (( status != 0 && stopped )); then
        restart || true
    fi
    /bin/rm -f "$staged" "$backup"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if [[ -f "$template" ]]; then
    /usr/bin/ditto "$template" "$backup"
    hadTemplate=1
fi
/usr/bin/sudo -u "$account" /usr/bin/head -c 513 "$input" > "$staged"
[[ "$(stat -f %z "$staged")" == 512 ]]
/bin/chmod +a "user:$account allow read" "$staged"

# Stop the worker before swapping the protected template.
stopped=1
/bin/launchctl bootout "$service" >/dev/null 2>&1 || true
/bin/mv -f "$staged" "$template"
replaced=1
restart
for attempt in {1..30}; do
    if [[ -S "$socket" ]]; then exit 0; fi
    /bin/sleep 1
done
echo "MacFace could not reload the enrollment" >&2
exit 1
