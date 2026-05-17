#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITHUB_REPO="${GITHUB_REPO:-artemsvit/Code-Awake}"
VERSION="$(awk -F ' = ' '/MARKETING_VERSION = / {gsub(/;/, "", $2); print $2; exit}' "$ROOT/Code Awake.xcodeproj/project.pbxproj")"
BUILD="$(awk -F ' = ' '/CURRENT_PROJECT_VERSION = / {gsub(/;/, "", $2); print $2; exit}' "$ROOT/Code Awake.xcodeproj/project.pbxproj")"
TAG="${RELEASE_TAG:-v$VERSION-build-$BUILD}"
RELEASE_DIR="$ROOT/dist/github-release"
DMG="$RELEASE_DIR/Code-Awake-$VERSION.dmg"
APPCAST="$RELEASE_DIR/appcast.xml"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required. Install it with: brew install gh" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated yet. Run: gh auth login" >&2
  exit 1
fi

if [[ ! -f "$DMG" || ! -f "$APPCAST" ]]; then
  echo "Release assets are missing. Run: ./scripts/build_release_dmg.sh" >&2
  exit 1
fi

if ! gh repo view "$GITHUB_REPO" >/dev/null 2>&1; then
  echo "GitHub repo not found: $GITHUB_REPO" >&2
  echo "Run: ./scripts/setup_github_repo.sh" >&2
  exit 1
fi

notes="Code Awake $VERSION build $BUILD.

Signed and notarized macOS release with Sparkle appcast."

if gh release view "$TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG" "$APPCAST" --repo "$GITHUB_REPO" --clobber
  gh release edit "$TAG" --repo "$GITHUB_REPO" --title "Code Awake $VERSION ($BUILD)" --notes "$notes" --latest
else
  gh release create "$TAG" "$DMG" "$APPCAST" \
    --repo "$GITHUB_REPO" \
    --title "Code Awake $VERSION ($BUILD)" \
    --notes "$notes" \
    --latest
fi

echo "Published GitHub release:"
echo "https://github.com/$GITHUB_REPO/releases/tag/$TAG"
echo
echo "Sparkle feed URL:"
echo "https://github.com/$GITHUB_REPO/releases/latest/download/appcast.xml"
