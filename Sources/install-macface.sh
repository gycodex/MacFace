#!/bin/bash
set -euo pipefail

security=/usr/bin/security
plist=/usr/libexec/PlistBuddy
lock=system.login.screensaver
right=com.macface.face-unlock
preferences=/Library/Preferences/com.apple.loginwindow
apphome="/Library/Application Support/MacFace"
agent=/Library/LaunchAgents/com.macface.agent.plist
bundle=/Library/Security/SecurityAgentPlugins/MacFaceProbe.bundle
settings=/Applications/MacFace.app

restore() {
    local uid="$1" temp status=0
    temp=$(/usr/bin/mktemp)
    "$security" authorizationdb read "$lock" > "$temp" || { rm -f "$temp"; return 1; }
    local index=0
    while entry=$("$plist" -c "Print :rule:$index" "$temp" 2>/dev/null); do
        if [[ "$entry" == "$right" ]]; then
            "$plist" -c "Delete :rule:$index" "$temp"
            "$security" authorizationdb write "$lock" < "$temp" ||
                { rm -f "$temp"; return 1; }
            break
        fi
        ((index += 1))
    done
    rm -f "$temp"
    if [[ -f "$apphome/set-unlock-mode" ]] &&
       [[ "$(/usr/bin/defaults read "$preferences" screenUnlockMode 2>/dev/null)" == 2 ]]; then
        /usr/bin/defaults delete "$preferences" screenUnlockMode || status=1
    fi
    if "$security" authorizationdb read "$right" >/dev/null 2>&1; then
        "$security" authorizationdb remove "$right" || status=1
    fi
    /bin/launchctl bootout "gui/$uid/com.macface.agent" 2>/dev/null || true
    /usr/bin/pkill -u "$uid" -x MacFaceAgent 2>/dev/null || true
    local socket="/tmp/com.macface.agent.$uid.sock"
    if [[ -S "$socket" && "$(stat -f %u "$socket")" == "$uid" ]]; then
        rm -f "$socket"
    fi
    rm -f "$agent"
    if [[ -f "$apphome/installed-settings" ]] &&
        [[ "$("$plist" -c 'Print :CFBundleIdentifier' "$settings/Contents/Info.plist" 2>/dev/null)" == com.macface.settings ]]; then
        rm -rf "$settings"
    fi
    rm -rf "$bundle" "$apphome"
    return "$status"
}

[[ "$(id -u)" == 0 ]] || { echo "Administrator authorization required"; exit 1; }
if [[ "${1:-}" == remove ]]; then
    [[ -f "$apphome/installed-uid" ]] || { echo "MacFace installation not found"; exit 1; }
    restore "$(cat "$apphome/installed-uid")"
    exit
fi

if [[ "${1:-}" != install || "$#" != 3 ]]; then
    echo "Usage: install-macface.sh install <release-directory> <console-user>" >&2
    exit 1
fi
source=$2
targetUser=$3
uid=$(id -u "$targetUser")
[[ "$(stat -f %u /dev/console)" == "$uid" && "$uid" -ge 500 ]] || exit 1
socket="/tmp/com.macface.agent.$uid.sock"
service="gui/$uid/com.macface.agent"

owned_bundle() {
    local path=$1 identifier=$2
    if [[ ! -e "$path" && ! -L "$path" ]]; then return 0; fi
    [[ -d "$path" && ! -L "$path" && "$(stat -f %u "$path")" == 0 &&
       "$("$plist" -c 'Print :CFBundleIdentifier' "$path/Contents/Info.plist" 2>/dev/null)" == "$identifier" ]]
}

if ! owned_bundle "$settings" com.macface.settings ||
   ! owned_bundle "$bundle" com.macface.authorization-probe; then
    echo "An existing app or authorization bundle does not belong to MacFace." >&2
    exit 1
fi
if [[ -e "$apphome" || -L "$apphome" ]]; then
    [[ -d "$apphome" && ! -L "$apphome" && "$(stat -f %u "$apphome")" == 0 &&
       "$(cat "$apphome/installed-uid")" == "$uid" ]] ||
       { echo "Existing MacFace installation does not belong to the current user." >&2; exit 1; }
fi
if [[ -e "$agent" || -L "$agent" ]]; then
    [[ -f "$agent" && ! -L "$agent" && "$(stat -f %u "$agent")" == 0 &&
       "$("$plist" -c 'Print :Label' "$agent" 2>/dev/null)" == com.macface.agent &&
       "$("$plist" -c 'Print :ProgramArguments:0' "$agent" 2>/dev/null)" == "$apphome/start-agent.sh" ]] ||
       { echo "Existing launch agent does not belong to MacFace." >&2; exit 1; }
fi
if [[ -e "$socket" || -L "$socket" ]]; then
    [[ -S "$socket" && ! -L "$socket" && "$(stat -f %u "$socket")" == "$uid" ]] ||
       { echo "MacFace socket path is in use." >&2; exit 1; }
fi
if /usr/bin/defaults read "$preferences" screenUnlockMode >/dev/null 2>&1; then
    echo "A custom macOS lock-screen preference is already configured." >&2
    exit 1
fi

work=$(/usr/bin/mktemp -d)
trap 'rm -rf "$work"' EXIT
original="$work/original.plist"
baseRule="$work/base.plist"
candidate="$work/candidate.plist"
"$security" authorizationdb read "$lock" > "$original"
cp "$original" "$baseRule"
hadRight=0
if "$security" authorizationdb read "$right" > "$work/right.plist" 2>/dev/null; then
    hadRight=1
    case "$("$plist" -c 'Print :mechanisms:0' "$work/right.plist")" in
        MacFaceProbe:verify,privileged|MacFaceProbe:verify-empty,privileged) ;;
        *) echo "Existing MacFace authorization right is not recognized." >&2; exit 1 ;;
    esac
    if "$plist" -c 'Print :mechanisms:1' "$work/right.plist" >/dev/null 2>&1; then exit 1; fi
fi
index=0
while entry=$("$plist" -c "Print :rule:$index" "$baseRule" 2>/dev/null); do
    if [[ "$entry" == "$right" ]]; then
        "$plist" -c "Delete :rule:$index" "$baseRule"
        break
    fi
    index=$((index + 1))
done
/bin/bash "$source/prepare-lock-rule.sh" "$baseRule" "$candidate"

wasRunning=0
if /bin/launchctl print "$service" >/dev/null 2>&1; then wasRunning=1; fi
rightWritten=0
lockWritten=0
newFiles=0
rollback() {
    local result=$? restored=1
    trap - EXIT
    if ((lockWritten)); then "$security" authorizationdb write "$lock" < "$original" || restored=0; fi
    if ((rightWritten)); then
        if ((hadRight)); then
            "$security" authorizationdb write "$right" < "$work/right.plist" || restored=0
        else
            "$security" authorizationdb remove "$right" || restored=0
        fi
    fi
    if ((newFiles)); then
        /bin/launchctl bootout "$service" 2>/dev/null || true
        rm -rf "$apphome" "$agent" "$bundle" "$settings"
    fi
    for path in "$apphome" "$agent" "$bundle" "$settings"; do
        backup="$work/${path##*/}"
        if [[ -e "$backup" ]]; then mv "$backup" "$path" || restored=0; fi
    done
    if ((wasRunning)) && [[ -f "$agent" ]]; then
        if ! /bin/launchctl print "$service" >/dev/null 2>&1; then
            /bin/launchctl bootstrap "gui/$uid" "$agent" || restored=0
        fi
    fi
    if ((restored)); then
        rm -rf "$work"
    else
        echo "MacFace could not fully restore the previous installation. Backup: $work" >&2
        result=1
    fi
    exit "$result"
}
trap rollback EXIT
trap 'exit 1' HUP INT TERM

if ((wasRunning)); then
    /bin/launchctl bootout "$service"
fi
if [[ -S "$socket" ]]; then rm -f "$socket"; fi
for path in "$apphome" "$agent" "$bundle" "$settings"; do
    if [[ -e "$path" ]]; then mv "$path" "$work/${path##*/}"; fi
done
newFiles=1

/usr/bin/install -d -m 755 -o root -g wheel "$apphome"
/usr/bin/install -m 600 -o root -g wheel "$baseRule" "$apphome/original-lock.plist"
oldEnrollment="$work/MacFace/enrollment-$uid.bin"
if [[ -f "$oldEnrollment" && ! -L "$oldEnrollment" && "$(stat -f '%u:%z' "$oldEnrollment")" == 0:512 ]]; then
    /usr/bin/ditto "$oldEnrollment" "$apphome/enrollment-$uid.bin"
fi
printf '%s\n' "$uid" > "$apphome/installed-uid"
/usr/bin/install -m 755 -o root -g wheel "$0" "$apphome/install-macface.sh"
/usr/bin/ditto "$source/MacFaceAgent.app" "$apphome/MacFaceAgent.app"
/usr/bin/ditto "$source/MacFaceProbe.bundle" "$bundle"
/usr/sbin/chown -R root:wheel "$apphome/MacFaceAgent.app" "$bundle"
/bin/chmod -R go-w "$apphome/MacFaceAgent.app" "$bundle"
/usr/bin/codesign --verify --strict "$apphome/MacFaceAgent.app"
/usr/bin/codesign --verify --strict "$bundle"
touch "$apphome/installed-settings"
/usr/bin/ditto "$source/MacFace.app" "$settings"
/usr/sbin/chown -R root:wheel "$settings"
/bin/chmod -R go-w "$settings"
/usr/bin/codesign --verify --deep --strict "$settings"

cat > "$apphome/start-agent.sh" <<'START'
#!/bin/bash
set -euo pipefail
base="/Library/Application Support/MacFace"
uid=$(/usr/bin/id -u)
[[ "$uid" == "$(/bin/cat "$base/installed-uid")" ]] || exit 0
socket="/tmp/com.macface.agent.$uid.sock"
if [[ -S "$socket" && "$(/usr/bin/stat -f %u "$socket")" == "$uid" ]] &&
    ! /usr/bin/pgrep -u "$uid" -x MacFaceAgent >/dev/null; then
    /bin/rm -f "$socket"
fi
exec "$base/MacFaceAgent.app/Contents/MacOS/MacFaceAgent"
START
/bin/chmod 755 "$apphome/start-agent.sh"

cat > "$agent" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.macface.agent</string>
<key>ProgramArguments</key><array><string>/Library/Application Support/MacFace/start-agent.sh</string></array>
<key>RunAtLoad</key><true/>
<key>LimitLoadToSessionType</key><string>Aqua</string>
</dict></plist>
PLIST
/bin/chmod 644 "$agent"
/bin/launchctl bootstrap "gui/$uid" "$agent"
rightWritten=1
cat <<'PLIST' | "$security" authorizationdb write "$right"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>class</key><string>evaluate-mechanisms</string>
<key>mechanisms</key><array><string>MacFaceProbe:verify-empty,privileged</string></array>
<key>shared</key><false/>
<key>tries</key><integer>1</integer>
</dict></plist>
PLIST
"$security" authorizationdb read "$lock" > "$work/current.plist"
cmp -s "$original" "$work/current.plist" || { echo "Screen-unlock rule changed during installation"; exit 1; }
lockWritten=1
"$security" authorizationdb write "$lock" < "$candidate"
"$security" authorizationdb read "$lock" > "$work/current.plist"
cmp -s <(/usr/bin/plutil -extract rule json -o - "$candidate") \
       <(/usr/bin/plutil -extract rule json -o - "$work/current.plist")
rm -rf "$work"
trap - EXIT HUP INT TERM
if [[ -f "$apphome/enrollment-$uid.bin" ]]; then
    echo "MacFace updated. Existing enrollment preserved."
else
    echo "MacFace installed. Open MacFace and enroll your face."
fi
