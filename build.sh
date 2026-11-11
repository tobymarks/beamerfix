#!/bin/zsh
# Baut build/BeamerFix.app (Universal: Apple Silicon + Intel, ad-hoc signiert)
# und das Kommandozeilen-Tool build/beamerfix.
#   ./build.sh            nur bauen (ad-hoc signiert, nur für diesen Mac)
#   ./build.sh install    bauen und nach /Applications kopieren
#   ./build.sh release    mit Developer ID signieren, notarisieren, stapeln → build/BeamerFix.dmg
#   ./build.sh release install
#
# Release braucht: ein „Developer ID Application“-Zertifikat im Schlüsselbund und ein
# notarytool-Profil (einmalig):
#   xcrun notarytool store-credentials beamerfix-notary --key AuthKey_XXX.p8 --key-id XXX --issuer <UUID>
# Überschreibbar per Umgebung: SIGN_ID, NOTARY_PROFILE
set -e
RELEASE=0; INSTALL=0
for a in "$@"; do [[ $a == release ]] && RELEASE=1; [[ $a == install ]] && INSTALL=1; done
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
  <key>CFBundleShortVersionString</key><string>1.3</string>
  <key>CFBundleVersion</key><string>4</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>BeamerFix</string>
</dict></plist>
PLIST

if (( RELEASE )); then
  SIGN_ID=${SIGN_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}
  NOTARY_PROFILE=${NOTARY_PROFILE:-beamerfix-notary}
  [[ -n $SIGN_ID ]] || { echo "✗ Kein 'Developer ID Application'-Zertifikat gefunden"; exit 1; }
  echo "→ Signiere mit: $SIGN_ID"
  # Hardened Runtime + sicherer Zeitstempel sind Pflicht für die Notarisierung
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" build/beamerfix
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" $APP
  codesign --verify --strict --deep $APP

  echo "→ Notarisiere (dauert meist 1–5 Minuten) …"
  ditto -c -k --keepParent $APP build/notarize.zip
  xcrun notarytool submit build/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple $APP
  rm build/notarize.zip

  spctl --assess --type execute -v $APP

  # Installations-DMG (Drag & Drop in Programme), ebenfalls signiert + notarisiert
  echo "→ Baue DMG …"
  dmg/make-dmg.sh $APP build/BeamerFix.dmg "$SIGN_ID"
  xcrun notarytool submit build/BeamerFix.dmg --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple build/BeamerFix.dmg
  spctl --assess --type open --context context:primary-signature -v build/BeamerFix.dmg
  echo "✓ Notarisiert: build/BeamerFix.dmg"
else
  codesign --force --sign - $APP
  codesign --force --sign - build/beamerfix
  echo "✓ $APP und build/beamerfix gebaut (ad-hoc signiert)"
fi

if (( INSTALL )); then
  pkill -x BeamerFix 2>/dev/null || true
  rm -rf /Applications/BeamerFix.app
  cp -R $APP /Applications/
  touch /Applications/BeamerFix.app   # Finder/Dock-Icon-Cache auffrischen
  echo "✓ nach /Applications installiert"
fi
