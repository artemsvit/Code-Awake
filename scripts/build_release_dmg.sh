#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Code Awake.xcodeproj"
SCHEME="Code Awake"
TEAM_ID="YOURTEAMID"
CERT_SHA="CODE_AWAKE_CERT_SIGN_IDENTITY"
CERT_NAME="Developer ID Application"
NOTARY_PROFILE="YourNotaryProfile"
VERSION="1.0"

APP="$HOME/Library/Developer/Xcode/DerivedData/Code_Awake-fvnakmvxainmqdguqjpjnnilwaxm/Build/Products/Release/Code Awake.app"
ENTITLEMENTS="$ROOT/Code Awake/CodeAwakeRelease.entitlements"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-stage"
RW_DMG="$DIST/Code Awake $VERSION-rw.dmg"
FINAL_DMG="$DIST/Code Awake $VERSION.dmg"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

echo "==> Building Release"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  clean build \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$CERT_NAME" \
  CODE_SIGN_STYLE=Manual

echo "==> Re-signing app with Developer ID timestamp"
/usr/bin/codesign \
  --force \
  --deep \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$CERT_SHA" \
  "$APP"

echo "==> Preparing DMG staging folder"
while hdiutil info | grep -q '/Volumes/Code Awake'; do
  dev="$(hdiutil info | awk '/\/Volumes\/Code Awake/ {print $1; exit}')"
  hdiutil detach "$dev" || hdiutil detach "$dev" -force || true
  sleep 1
done

rm -rf "$STAGE" "$RW_DMG" "$FINAL_DMG"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/Code Awake.app"
ln -s /Applications "$STAGE/Applications"

python3 - <<PY
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

out = Path("$STAGE/.background/background.png")
W, H = 760, 440
img = Image.new("RGB", (W, H), (24, 17, 24))

for y in range(H):
    for x in range(W):
        t = (x / W * 0.35) + (y / H * 0.65)
        r = int(20 + (43 - 20) * t)
        g = int(17 + (22 - 17) * t)
        b = int(22 + (40 - 22) * t)
        img.putpixel((x, y), (r, g, b))

d = ImageDraw.Draw(img, "RGBA")
for cx, cy, rad, col in [
    (690, 25, 180, (251, 200, 148, 34)),
    (70, 430, 150, (213, 126, 235, 45)),
]:
    for i in range(3):
        d.ellipse((cx-rad+i*42, cy-rad+i*42, cx+rad-i*42, cy+rad-i*42), fill=col)

def font(size):
    for path in ["/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Supplemental/Arial.ttf"]:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()

d.text((46, 44), "Code Awake", fill=(255, 255, 255, 238), font=font(30))
d.text((46, 84), "Drag Code Awake into Applications", fill=(255, 255, 255, 178), font=font(17))
d.line((350, 246, 420, 246), fill=(246, 174, 178, 230), width=4)
d.polygon([(420, 236), (446, 246), (420, 256)], fill=(246, 174, 178, 230))

img.save(out)
PY

echo "==> Creating writable DMG"
hdiutil create -volname "Code Awake" -srcfolder "$STAGE" -ov -format UDRW "$RW_DMG"

mount_output="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen)"
mount_point="$(echo "$mount_output" | awk '/\/Volumes\/Code Awake/ {print substr($0, index($0, "/Volumes/")); exit}')"
volume_name="$(basename "$mount_point")"

echo "==> Applying Finder layout"
osascript <<OSA
set volumeName to "$volume_name"
tell application "Finder"
  tell disk volumeName
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 860, 540}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 96
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "Code Awake.app" of container window to {255, 250}
    set position of item "Applications" of container window to {535, 250}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

sync
hdiutil detach "$mount_point"

echo "==> Compressing and signing DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG"
rm -f "$RW_DMG"
/usr/bin/codesign --force --timestamp --sign "$CERT_SHA" "$FINAL_DMG"

echo "==> Notarizing DMG"
xcrun notarytool submit "$FINAL_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$FINAL_DMG"
xcrun stapler validate "$FINAL_DMG"

echo "==> Verifying release"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --verify --verbose=2 "$FINAL_DMG"
hdiutil verify "$FINAL_DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$FINAL_DMG"

mount_output="$(hdiutil attach "$FINAL_DMG" -readonly -noverify -noautoopen)"
mount_point="$(echo "$mount_output" | awk '/\/Volumes\/Code Awake/ {print substr($0, index($0, "/Volumes/")); exit}')"
spctl --assess --type execute --verbose=4 "$mount_point/Code Awake.app"
codesign --verify --deep --strict --verbose=2 "$mount_point/Code Awake.app"
hdiutil detach "$mount_point"

echo "==> Done: $FINAL_DMG"
