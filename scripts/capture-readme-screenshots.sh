#!/bin/zsh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build
BIN="$(swift build --show-bin-path)/GitGatto"
SIZE="1416x878"

"$BIN" \
  --snapshot "$ROOT/docs/media/github-project.png" \
  --snapshot-size "$SIZE" \
  --section github \
  --repository "$ROOT" \
  -appearance light \
  -visualTheme softGlass

GITGATTO_WORKSPACE_PREVIEW=1 "$BIN" \
  --snapshot "$ROOT/docs/media/workspace.png" \
  --snapshot-size "$SIZE" \
  --section changes \
  -appearance light \
  -visualTheme softGlass

GITGATTO_WORKSPACE_PREVIEW=1 GITGATTO_RECOVERY_PREVIEW=1 "$BIN" \
  --snapshot "$ROOT/docs/media/recovery-center.png" \
  --snapshot-size "$SIZE" \
  --section recovery \
  -appearance light \
  -visualTheme softGlass

GITGATTO_WORKSPACE_PREVIEW=1 "$BIN" \
  --snapshot "$ROOT/docs/media/file-history-dark.png" \
  --snapshot-size "$SIZE" \
  --section timeMachine \
  -appearance dark \
  -visualTheme console

echo "Updated README screenshots in docs/media"
