#!/bin/zsh
# Builds Zendish.app and Zendish.dmg in dist/. The app is ad-hoc signed, not notarised.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Zendish
binary="$(swift build -c release --show-bin-path)/Zendish"

app=dist/Zendish.app
rm -rf dist
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/Zendish"
cp assets/Info.plist "$app/Contents/Info.plist"
cp assets/Zendish.icns "$app/Contents/Resources/Zendish.icns"
codesign --force --sign - --timestamp=none "$app"

staging="$(mktemp -d)"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname Zendish -srcfolder "$staging" -ov -format UDZO dist/Zendish.dmg
rm -rf "$staging"
echo "Built $app and dist/Zendish.dmg"
