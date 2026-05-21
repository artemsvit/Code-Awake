#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # Local release signing settings. This file is ignored by git.
  source "$ROOT/.env"
  set +a
fi

PROJECT="$ROOT/Code Awake.xcodeproj"
SCHEME="Code Awake"
TEAM_ID="${CODE_AWAKE_TEAM_ID:?Set CODE_AWAKE_TEAM_ID to your Apple Developer Team ID.}"
CERT_SIGN_IDENTITY="${CODE_AWAKE_CERT_SIGN_IDENTITY:?Set CODE_AWAKE_CERT_SIGN_IDENTITY to your Developer ID signing identity name or SHA-1 fingerprint.}"
NOTARY_PROFILE="${CODE_AWAKE_NOTARY_PROFILE:?Set CODE_AWAKE_NOTARY_PROFILE to your notarytool keychain profile name.}"
SPARKLE_ACCOUNT="${CODE_AWAKE_SPARKLE_ACCOUNT:-CodeAwake}"
GITHUB_REPO="${GITHUB_REPO:-artemsvit/Code-Awake}"
GITHUB_RELEASE_URL_PREFIX="https://github.com/$GITHUB_REPO/releases/latest/download/"
LANDING_SITE_URL="https://codeawake.artsvit.com/index.html"

VERSION="$(awk -F ' = ' '/MARKETING_VERSION = / {gsub(/;/, "", $2); print $2; exit}' "$ROOT/Code Awake.xcodeproj/project.pbxproj")"
ENTITLEMENTS="$ROOT/Code Awake/CodeAwakeRelease.entitlements"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-stage"
RW_DMG="$DIST/Code Awake $VERSION-rw.dmg"
FINAL_DMG="$DIST/Code Awake $VERSION.dmg"
LANDING_APP_DIR="$ROOT/landing/app"
LANDING_DMG="$LANDING_APP_DIR/Code Awake $VERSION.dmg"
GITHUB_RELEASE_DIR="$DIST/github-release"
GITHUB_DMG_NAME="Code-Awake-$VERSION.dmg"
GITHUB_RELEASE_DMG="$GITHUB_RELEASE_DIR/$GITHUB_DMG_NAME"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

current_build="$(awk -F ' = ' '/CURRENT_PROJECT_VERSION = / {gsub(/;/, "", $2); print $2; exit}' "$ROOT/Code Awake.xcodeproj/project.pbxproj")"
next_build="$((current_build + 1))"

echo "==> Bumping build number: $current_build -> $next_build"
python3 - <<PY
from pathlib import Path
import re

project = Path("$ROOT/Code Awake.xcodeproj/project.pbxproj")
text = project.read_text()
text = re.sub(r"CURRENT_PROJECT_VERSION = \\d+;", "CURRENT_PROJECT_VERSION = $next_build;", text)
project.write_text(text)
PY

echo "==> Building Release"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  clean build \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$CERT_SIGN_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  ONLY_ACTIVE_ARCH=NO

build_settings="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -destination "generic/platform=macOS" -showBuildSettings DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="$CERT_SIGN_IDENTITY" CODE_SIGN_STYLE=Manual ONLY_ACTIVE_ARCH=NO)"
built_products_dir="$(printf "%s\\n" "$build_settings" | awk -F ' = ' '/BUILT_PRODUCTS_DIR = / {print $2; exit}')"
APP="$built_products_dir/Code Awake.app"

echo "==> Re-signing Sparkle helpers and app with Developer ID timestamp"
sparkle_framework="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle_framework" ]]; then
  while IFS= read -r code_item; do
    /usr/bin/codesign \
      --force \
      --options runtime \
      --timestamp \
      --preserve-metadata=identifier,entitlements \
      --sign "$CERT_SIGN_IDENTITY" \
      "$code_item"
  done < <(find "$sparkle_framework" -depth \( -name "*.xpc" -o -name "*.app" -o -name "*.framework" \) -print)

  while IFS= read -r executable_item; do
    if /usr/bin/codesign -dv "$executable_item" >/dev/null 2>&1; then
      /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp \
        --preserve-metadata=identifier,entitlements \
        --sign "$CERT_SIGN_IDENTITY" \
        "$executable_item"
    fi
  done < <(find "$sparkle_framework" -type f -perm -111 -print)
fi

/usr/bin/codesign \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$CERT_SIGN_IDENTITY" \
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
/usr/bin/codesign --force --timestamp --sign "$CERT_SIGN_IDENTITY" "$FINAL_DMG"

echo "==> Notarizing DMG"
xcrun notarytool submit "$FINAL_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$FINAL_DMG"
xcrun stapler validate "$FINAL_DMG"

echo "==> Preparing GitHub Release assets and Sparkle appcast"
mkdir -p "$LANDING_APP_DIR"
rm -rf "$GITHUB_RELEASE_DIR"
mkdir -p "$GITHUB_RELEASE_DIR"
cp "$FINAL_DMG" "$LANDING_DMG"
cp "$FINAL_DMG" "$GITHUB_RELEASE_DMG"

sparkle_bin="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" -print -quit)"
if [[ -z "$sparkle_bin" ]]; then
  echo "Sparkle generate_appcast tool was not found. Run xcodebuild -resolvePackageDependencies first." >&2
  exit 1
fi
sparkle_tools_dir="$(dirname "$sparkle_bin")"
sparkle_key_file="$(mktemp -t codeawake-sparkle-key)"
trap 'rm -f "$sparkle_key_file"' EXIT
rm -f "$sparkle_key_file"

"$sparkle_tools_dir/generate_keys" --account "$SPARKLE_ACCOUNT" -x "$sparkle_key_file" >/dev/null

rm -f "$GITHUB_RELEASE_DIR/appcast.xml" "$LANDING_APP_DIR/appcast.xml"

"$sparkle_bin" \
  --ed-key-file "$sparkle_key_file" \
  --download-url-prefix "$GITHUB_RELEASE_URL_PREFIX" \
  --maximum-versions 1 \
  --link "$LANDING_SITE_URL" \
  "$GITHUB_RELEASE_DIR"

cp "$GITHUB_RELEASE_DIR/appcast.xml" "$LANDING_APP_DIR/appcast.xml"

python3 - <<PY
from pathlib import Path
from urllib.parse import quote
import re

landing = Path("$ROOT/landing/index.html")
download_href = "https://github.com/$GITHUB_REPO/releases/latest/download/" + quote("$GITHUB_DMG_NAME")
text = landing.read_text()
text = re.sub(r'href="(?:app/|https://github\\.com/)[^"]+\\.dmg"', f'href="{download_href}"', text)
landing.write_text(text)
PY

echo "==> Verifying release"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --verify --verbose=2 "$FINAL_DMG"
hdiutil verify "$FINAL_DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$FINAL_DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$LANDING_DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$GITHUB_RELEASE_DMG"

mount_output="$(hdiutil attach "$FINAL_DMG" -readonly -noverify -noautoopen)"
mount_point="$(echo "$mount_output" | awk '/\/Volumes\/Code Awake/ {print substr($0, index($0, "/Volumes/")); exit}')"
spctl --assess --type execute --verbose=4 "$mount_point/Code Awake.app"
codesign --verify --deep --strict --verbose=2 "$mount_point/Code Awake.app"
hdiutil detach "$mount_point"

echo "==> Done: $FINAL_DMG"
