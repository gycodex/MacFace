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
for path in "$apphome" "$agent" "$bundle" "$settings" "/tmp/com.macface.agent.$uid.sock"; do
    [[ ! -e "$path" && ! -L "$path" ]] || { echo "Path already exists: $path"; exit 1; }
done
if "$security" authorizationdb read "$right" >/dev/null 2>&1 ||
   /usr/bin/defaults read "$preferences" screenUnlockMode >/dev/null 2>&1; then
    echo "An authorization rule or lock screen preference is already configured"
    exit 1
fi
work=$(/usr/bin/mktemp -d)
trap 'rm -rf "$work"' EXIT
original="$work/original.plist"
candidate="$work/candidate.plist"
"$security" authorizationdb read "$lock" > "$original"
/bin/bash "$source/prepare-lock-rule.sh" "$original" "$candidate"

rollback() {
    local result=$?
    trap - EXIT
    restore "$uid" || result=1
    rm -rf "$work"
    exit "$result"
}
trap rollback EXIT
trap 'exit 1' HUP INT TERM

/usr/bin/install -d -m 755 -o root -g wheel "$apphome"
/usr/bin/install -m 600 -o root -g wheel "$original" "$apphome/original-lock.plist"
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
cat <<'PLIST' | "$security" authorizationdb write "$right"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>class</key><string>evaluate-mechanisms</string>
<key>mechanisms</key><array><string>MacFaceProbe:verify,privileged</string></array>
<key>shared</key><false/>
<key>tries</key><integer>1</integer>
</dict></plist>
PLIST
# Keep the native password check ahead of MacFace.
"$security" authorizationdb read "$lock" > "$work/current.plist"
cmp -s "$original" "$work/current.plist" || { echo "Screen-unlock rule changed during installation"; exit 1; }
"$security" authorizationdb write "$lock" < "$candidate"
"$security" authorizationdb read "$lock" > "$work/current.plist"
cmp -s <(/usr/bin/plutil -extract rule json -o - "$candidate") \
       <(/usr/bin/plutil -extract rule json -o - "$work/current.plist")
rm -rf "$work"
trap - EXIT HUP INT TERM
echo "MacFace installed. Open MacFace and enroll your face."
