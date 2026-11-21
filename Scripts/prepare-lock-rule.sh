#!/bin/bash
set -euo pipefail

input=$1
output=$2
plist=/usr/libexec/PlistBuddy
native=use-login-window-ui
macface=com.macface.face-unlock

if [[ "$("$plist" -c 'Print :class' "$input" 2>/dev/null)" != rule ||
      "$("$plist" -c 'Print :k-of-n' "$input" 2>/dev/null)" != 1 ]]; then
    echo "MacFace requires a one-of-many system screen-unlock rule." >&2
    exit 1
fi

position=
index=0
while entry=$("$plist" -c "Print :rule:$index" "$input" 2>/dev/null); do
    if [[ "$entry" == "$macface" ]]; then
        echo "MacFace is already present in the screen-unlock rule." >&2
        exit 1
    fi
    if [[ "$entry" == "$native" ]]; then
        [[ -z "$position" ]] || exit 1
        position=$((index + 1))
    fi
    index=$((index + 1))
done
if [[ -z "$position" ]]; then
    echo "MacFace requires the original macOS lock-screen authentication mechanism." >&2
    exit 1
fi
cp "$input" "$output"
"$plist" -c "Add :rule:$position string $macface" "$output"
