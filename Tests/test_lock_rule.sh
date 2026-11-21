#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
directory=$(mktemp -d)
trap 'rm -rf "$directory"' EXIT

prepare() {
    local rules="$1" count="${2:-1}"
    printf '{"class":"rule","k-of-n":%s,"rule":%s}' "$count" "$rules" > "$directory/input"
    plutil -convert xml1 "$directory/input"
    bash Scripts/prepare-lock-rule.sh "$directory/input" "$directory/output"
}

prepare '["use-login-window-ui"]'
[[ "$(plutil -extract rule json -o - "$directory/output")" == \
   '["com.macface.face-unlock","use-login-window-ui"]' ]]
[[ "$(plutil -extract rule json -o - "$directory/input")" == '["use-login-window-ui"]' ]]
prepare '["example.remote","use-login-window-ui","example.fallback"]'
[[ "$(plutil -extract rule json -o - "$directory/output")" == \
   '["example.remote","com.macface.face-unlock","use-login-window-ui","example.fallback"]' ]]
if prepare '["example.other"]' 2>/dev/null ||
   prepare '["use-login-window-ui","com.macface.face-unlock"]' 2>/dev/null ||
   prepare '["use-login-window-ui","use-login-window-ui"]' 2>/dev/null ||
   prepare '["use-login-window-ui","example.other"]' 2 2>/dev/null; then
    echo "Unsupported policy was accepted" >&2
    exit 1
fi
echo "PASS: stock and existing screen-lock policies preserved; unsupported and duplicate rules refused"
