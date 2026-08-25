#!/bin/bash
# Assemble Kibitz.app from the SwiftPM build.
#
# There is deliberately no .xcodeproj: distribution is a Homebrew formula that
# builds from source with `swift build`, so SwiftPM has to be the source of truth.
set -euo pipefail

cd "$(dirname "$0")/.."
[ -d /Applications/Xcode.app ] && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

VERSION="${VERSION:-0.1.0}"
APP="${1:-build/Kibitz.app}"

swift build -c release --product KibitzApp
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/KibitzApp" "$APP/Contents/MacOS/kibitz"

# Resources only. A .bundle inside Contents/MacOS is treated by codesign as a
# code subcomponent, and a SwiftPM resource bundle has no Info.plist, so signing
# fails with "bundle format unrecognized". BundledPrompt looks in
# Contents/Resources, which is where it belongs anyway.
for bundle in "$BIN"/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>kibitz</string>
    <key>CFBundleDisplayName</key><string>kibitz</string>
    <key>CFBundleIdentifier</key><string>com.knapiontek.kibitz</string>
    <key>CFBundleExecutable</key><string>kibitz</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <!-- Menu bar agent: no dock icon, no main window. -->
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT</string>
</dict>
</plist>
PLIST

# Signing matters more than it looks: macOS ties the Accessibility grant to the
# binary's signature, so an ad-hoc signature that changes every build makes the
# permission evaporate. A stable Apple Development identity keeps it.
# Any stable identity will do. A self-signed "Code Signing" certificate from
# Keychain Access works as well as an Apple Development one for keeping the
# Accessibility permission alive; it just cannot be distributed to others.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"' || true)
fi
# Without -v, so a self-signed root still counts. Such a certificate reports
# CSSMERR_TP_NOT_TRUSTED, which only means it is not a distribution identity.
# codesign accepts it, and that is all the Accessibility permission needs.
if [ -z "$IDENTITY" ]; then
    # Match the SHA-1 only: the line may end with "(CSSMERR_TP_NOT_TRUSTED)".
    IDENTITY=$(security find-identity -p codesigning 2>/dev/null \
        | grep -oE '[0-9A-F]{40}' | head -1 || true)
fi

if [ -n "$IDENTITY" ]; then
    # No --options runtime: the hardened runtime is a notarisation requirement,
    # and it makes codesign reject a self-signed identity.
    codesign --force --deep --sign "$IDENTITY" "$APP"
    echo "signed with: $IDENTITY"
else
    codesign --force --deep --sign - "$APP"
    echo "WARNING: signed ad-hoc. macOS will revoke the Accessibility permission"
    echo "         on every rebuild. Create a free Apple Development certificate"
    echo "         in Xcode (Settings > Accounts > Manage Certificates > +)."
fi

echo "built: $APP"
