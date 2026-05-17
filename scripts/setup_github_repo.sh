#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITHUB_REPO="${GITHUB_REPO:-artemsvit/Code-Awake}"
REMOTE_NAME="${REMOTE_NAME:-github}"

cd "$ROOT"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required. Install it with: brew install gh" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "GitHub CLI is not authenticated yet. Run: gh auth login" >&2
  exit 1
fi

if ! gh repo view "$GITHUB_REPO" >/dev/null 2>&1; then
  gh repo create "$GITHUB_REPO" --public --description "macOS menu bar utility that keeps your Mac awake."
fi

if git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  git remote set-url "$REMOTE_NAME" "https://github.com/$GITHUB_REPO.git"
else
  git remote add "$REMOTE_NAME" "https://github.com/$GITHUB_REPO.git"
fi

echo "GitHub repo ready: https://github.com/$GITHUB_REPO"
echo "Remote '$REMOTE_NAME' -> https://github.com/$GITHUB_REPO.git"
