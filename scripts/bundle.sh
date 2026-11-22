#!/usr/bin/env bash
# Fast dev build: assembles build/MemLens.app and signs it ad-hoc.
# For a distributable, signed and notarized DMG use scripts/release.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/assemble.sh

VERSION="${MEMLENS_VERSION:-0.1.0}"
assemble_app "$VERSION"

codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"
echo "Built $APP"
