#!/bin/zsh
# Baut build/BeamerFix.dmg mit Installationsfenster (App links, Pfeil, Programme-Ordner rechts).
# Aufruf: dmg/make-dmg.sh <App-Pfad> <Ausgabe.dmg> [Signatur-ID]
# Wird von build.sh release aufgerufen. Signieren/Notarisieren der DMG übernimmt build.sh.
set -e
APP=$1; OUT=$2; SIGN_ID=$3
NAME=BeamerFix
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
STAGE=$WORK/stage

[[ -f $HERE/background.tiff ]] || swift "$HERE/make-background.swift" "$HERE/background.tiff"

mkdir -p $STAGE/.background
cp -R "$APP" $STAGE/
ln -s /Applications $STAGE/Programme          # Finder zeigt den Symlink mit Programme-Icon
cp $HERE/background.tiff $STAGE/.background/background.tiff

# Beschreibbares Image erzeugen und mounten
hdiutil create -quiet -srcfolder $STAGE -volname $NAME -fs HFS+ -format UDRW -ov $WORK/rw.dmg
LINE=$(hdiutil attach -readwrite -noverify -noautoopen $WORK/rw.dmg 2>/dev/null | grep Apple_HFS)
DEV=${LINE%%[[:space:]]*}
MNT=$(print -r -- "$LINE" | awk -F'\t' '{print $NF}')
[[ -d $MNT ]] || { echo "✗ Mount fehlgeschlagen"; exit 1; }

# Fenster-Layout per Finder setzen (600×400 Inhalt, Icons 128 pt)
VOL=$(basename "$MNT")
osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    set w to container window
    set current view of w to icon view
    set toolbar visible of w to false
    set statusbar visible of w to false
    set bounds of w to {200, 120, 800, 548}
    set o to icon view options of w
    set arrangement of o to not arranged
    set icon size of o to 128
    set text size of o to 13
    set background picture of o to file ".background:background.tiff"
    set position of item "$NAME.app" of w to {150, 180}
    set position of item "Programme" of w to {450, 180}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

# Volume-Icon: .VolumeIcon.icns + „Custom Icon“-Flag (0x0400 in FinderInfo) am Volume-Root
# (erst nach dem Finder-Schritt, sonst entfernt Finder die Datei wieder)
cp $HERE/../icon/AppIcon.icns "$MNT/.VolumeIcon.icns"
xattr -wx com.apple.FinderInfo "0000000000000000040000000000000000000000000000000000000000000000" "$MNT"

sync
rm -rf "$MNT/.fseventsd" 2>/dev/null || true
hdiutil detach -quiet "$DEV" || { sleep 2; hdiutil detach -force -quiet "$DEV"; }

# Komprimiert und schreibgeschützt
rm -f "$OUT"
hdiutil convert -quiet $WORK/rw.dmg -format UDZO -imagekey zlib-level=9 -o "$OUT"
rm -rf $WORK

[[ -n $SIGN_ID ]] && codesign --force --timestamp --sign "$SIGN_ID" "$OUT"
echo "✓ $OUT"
