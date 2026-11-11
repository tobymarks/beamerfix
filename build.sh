#!/bin/zsh
# Baut build/BeamerFix.app (Universal: Apple Silicon + Intel, ad-hoc signiert)
# und das Kommandozeilen-Tool build/beamerfix.
#   ./build.sh            nur bauen
#   ./build.sh install    bauen und nach /Applications kopieren
set -e
cd "$(dirname "$0")"
APP=build/BeamerFix.app
TMP=$(mktemp -d)

rm -rf build && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
[[ -f icon/AppIcon.icns ]] || swift icon/make-icon.swift icon/AppIcon.icns
cp icon/AppIcon.icns $APP/Contents/Resources/

for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos13 Sources/main.swift    -o $TMP/app_$arch
  swiftc -O -target $arch-apple-macos13 cli/beamerfix.swift   -o $TMP/cli_$arch
done
lipo -create $TMP/app_arm64 $TMP/app_x86_64 -output $APP/Contents/MacOS/BeamerFix
lipo -create $TMP/cli_arm64 $TMP/cli_x86_64 -output build/beamerfix
rm -rf $TMP

cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>BeamerFix</string>
  <key>CFBundleDisplayName</key><string>BeamerFix</string>
  <key>CFBundleIdentifier</key><string>de.tobymarks.beamerfix</string>
  <key>CFBundleExecutable</key><string>BeamerFix</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>BeamerFix</string>
</dict></plist>
PLIST

codesign --force --sign - $APP
codesign --force --sign - build/beamerfix
echo "✓ $APP und build/beamerfix gebaut"

if [[ "$1" == "install" ]]; then
  pkill -x BeamerFix 2>/dev/null || true
  rm -rf /Applications/BeamerFix.app
  cp -R $APP /Applications/
  touch /Applications/BeamerFix.app   # Finder/Dock-Icon-Cache auffrischen
  echo "✓ nach /Applications installiert"
fi
