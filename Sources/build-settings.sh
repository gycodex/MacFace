#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app=build/MacFace.app
resources="$app/Contents/Resources"
helpers="$app/Contents/Helpers"
agentBuild="${MACFACE_AGENT_BUILD_DIR:-build/native/agent}"
mkdir -p "$resources" "$helpers" "$app/Contents/MacOS"
cp Sources/SettingsInfo.plist "$app/Contents/Info.plist"
xcrun swiftc -parse-as-library -warnings-as-errors -O Sources/MacFaceSettings.swift -o "$app/Contents/MacOS/MacFace"
cmake --build "$agentBuild" --target MacFaceEnroll
cp "$agentBuild/MacFaceEnroll" "$helpers/MacFaceEnroll"
cp build/models/{yunet,sface}.onnx Sources/save-enrollment.sh "$resources/"
codesign --force --sign - --options runtime "$helpers/MacFaceEnroll"

iconRoot=$(mktemp -d)
trap 'rm -rf "$iconRoot"' EXIT
iconSet="$iconRoot/MacFace.iconset"
mkdir "$iconSet"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/MacFace.png --out "$iconSet/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" Assets/MacFace.png --out "$iconSet/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconSet" -o "$resources/MacFace.icns"
codesign --force --sign - --options runtime --entitlements Sources/AgentEntitlements.plist "$app"
plutil -lint "$app/Contents/Info.plist"
codesign --verify --deep --strict "$app"
