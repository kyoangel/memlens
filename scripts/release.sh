#!/usr/bin/env bash
# Builds a Developer ID-signed, notarized, stapled DMG:
#   scripts/release.sh <version>            e.g. scripts/release.sh 0.1.0
# Env:
#   MEMLENS_SIGN_IDENTITY   codesign identity (default: the only "Developer ID Application" one)
#   MEMLENS_NOTARY_PROFILE  notarytool keychain profile (default: memlens-notary)
#   MEMLENS_SKIP_NOTARIZE=1 skip notarization/stapling/Gatekeeper checks (pipeline test only;
#                           the result is NOT distributable). Allows MEMLENS_SIGN_IDENTITY=-.
# One-time setup: see README "Releasing".
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib/assemble.sh

die() { echo "error: $*" >&2; exit 1; }

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: scripts/release.sh <major.minor.patch>"

SKIP_NOTARIZE="${MEMLENS_SKIP_NOTARIZE:-0}"
PROFILE="${MEMLENS_NOTARY_PROFILE:-memlens-notary}"
DMG="build/MemLens-${VERSION}.dmg"
PARTIAL="build/.partial-MemLens-${VERSION}.dmg"
ZIP="build/MemLens-${VERSION}-notarize.zip"
STAGE=""

cleanup() {
  [[ -n "$STAGE" ]] && rm -rf "$STAGE"
  [[ -n "$ZIP" ]] && rm -f "$ZIP"
  [[ -n "$PARTIAL" ]] && rm -f "$PARTIAL"
  return 0
}
trap cleanup EXIT

resolve_identity() {
  if [[ -n "${MEMLENS_SIGN_IDENTITY:-}" ]]; then
    echo "$MEMLENS_SIGN_IDENTITY"; return
  fi
  local found
  found="$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | tr -d '"' || true)"
  local count
  count="$(printf '%s' "$found" | grep -c . || true)"
  [[ "$count" -eq 1 ]] || die "expected exactly one 'Developer ID Application' identity, found $count (set MEMLENS_SIGN_IDENTITY)"
  echo "$found"
}

IDENTITY="$(resolve_identity)"
if [[ "$IDENTITY" == "-" && "$SKIP_NOTARIZE" != "1" ]]; then
  die "ad-hoc identity '-' is only allowed with MEMLENS_SKIP_NOTARIZE=1"
fi
if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  preflight_err="$(xcrun notarytool history --keychain-profile "$PROFILE" 2>&1 >/dev/null)" \
    || die "notary profile '$PROFILE' not usable: ${preflight_err}
run: xcrun notarytool store-credentials $PROFILE --apple-id <id> --team-id <TEAMID>"
fi

# sign <path> [runtime]  -- pass "runtime" to enable the hardened runtime (app only, not the DMG)
sign() {
  local target="$1" hardened="${2:-}"
  if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$target"
    return
  fi
  local opts=(--force --timestamp --sign "$IDENTITY")
  [[ "$hardened" == "runtime" ]] && opts+=(--options runtime)
  codesign "${opts[@]}" "$target"
}

notarize() {
  local file="$1"
  echo "==> Notarizing $file (this can take a few minutes)"
  local out rc
  out="$(xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait 2>&1)" && rc=0 || rc=$?
  echo "$out"
  local status
  status="$(grep 'status:' <<<"$out" | tail -n1 || true)"
  if [[ "$rc" -ne 0 || ! "$status" =~ status:\ Accepted[[:space:]]*$ ]]; then
    local id
    id="$(grep -m1 -Eo 'id: [0-9a-fA-F-]+' <<<"$out" | cut -d' ' -f2 || true)"
    die "notarization failed (exit $rc); inspect: xcrun notarytool log ${id:-<id>} --keychain-profile $PROFILE"
  fi
}

echo "==> Testing"
swift test

echo "==> Assembling $APP ($VERSION)"
assemble_app "$VERSION"

ARCHS="$(lipo -archs "$APP/Contents/MacOS/MemLens")"
[[ "$ARCHS" == "arm64" ]] || die "expected an arm64-only executable, got: $ARCHS"

echo "==> Signing app with: $IDENTITY"
sign "$APP" runtime
codesign --verify --deep --strict --verbose=2 "$APP"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  rm -f "$ZIP"
  xcrun stapler staple "$APP"
fi

echo "==> Building $DMG"
rm -f "$DMG" "$DMG.sha256" "$PARTIAL"
STAGE="$(mktemp -d)"
ditto "$APP" "$STAGE/MemLens.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname MemLens -srcfolder "$STAGE" -ov -format UDZO "$PARTIAL" >/dev/null
sign "$PARTIAL"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  notarize "$PARTIAL"
  xcrun stapler staple "$PARTIAL"

  echo "==> Verifying with Gatekeeper"
  spctl -a -vvv -t exec "$APP"
  spctl -a -vvv -t open --context context:primary-signature "$PARTIAL"
  xcrun stapler validate "$APP"
  xcrun stapler validate "$PARTIAL"
else
  echo "WARNING: MEMLENS_SKIP_NOTARIZE=1 — $DMG is NOT notarized and NOT distributable."
fi

mv "$PARTIAL" "$DMG"
(cd build && shasum -a 256 "MemLens-${VERSION}.dmg") | tee "$DMG.sha256"
echo "Done: $DMG"
