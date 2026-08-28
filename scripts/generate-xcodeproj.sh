#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
    print -u2 "xcodegen is required to regenerate GitGatto.xcodeproj."
    exit 1
fi

xcodegen generate --spec project.yml
