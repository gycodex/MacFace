#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

release=$PWD/build/local-install
version=$(plutil -extract CFBundleShortVersionString raw "$release/MacFace.app/Contents/Info.plist")
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/scripts/components" build/packages
for item in MacFace.app MacFaceAgent.app MacFaceProbe.bundle install-macface.sh prepare-lock-rule.sh; do
    ditto "$release/$item" "$stage/scripts/components/$item"
done

resources="$stage/scripts/components/MacFace.app/Contents/Resources/OpenSource"
mkdir -p "$resources"
cp LICENSE THIRD_PARTY.md Licenses/*.txt "$resources/"
codesign --force --sign - --options runtime --entitlements Sources/AgentEntitlements.plist \
    "$stage/scripts/components/MacFace.app"
for bundle in "$stage/scripts/components/"*.app "$stage/scripts/components/"*.bundle; do
    codesign --verify --deep --strict "$bundle"
done

cat > "$stage/scripts/postinstall" <<'POSTINSTALL'
#!/bin/bash
set -euo pipefail
if [[ "${3:-}" != / || "$(uname -m)" != arm64 || "$(sw_vers -productVersion | cut -d . -f 1)" != 27 ]]; then
    echo "MacFace supports installation on the active Apple silicon macOS 27 volume only." >&2
    exit 1
fi
consoleUser=$(/usr/bin/stat -f %Su /dev/console)
if [[ -z "$consoleUser" || "$consoleUser" == root || "$consoleUser" == loginwindow ]]; then
    echo "Sign in to the macOS desktop before installing MacFace." >&2
    exit 1
fi
components="$(cd "$(dirname "$0")/components" && pwd)"
exec /bin/bash "$components/install-macface.sh" install "$components" "$consoleUser"
POSTINSTALL
chmod 755 "$stage/scripts/postinstall"
package="$PWD/build/packages/MacFace-$version-arm64-unsigned.pkg"
pkgbuild --identifier com.macface.installer --version "$version" \
    --nopayload --scripts "$stage/scripts" "$package"
(
    cd build/packages
    shasum -a 256 "${package##*/}" > "${package##*/}.sha256"
)
