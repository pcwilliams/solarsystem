#!/usr/bin/env bash
# run-macos.sh
# Build SolarSystem for macOS in Release mode, install into /Applications,
# and launch the installed copy. Any additional arguments are passed straight
# through to the app as ProcessInfo launch-args — same flags you'd use on iOS:
#
#   ./run-macos.sh
#   ./run-macos.sh -mission apollo11 -focus earth
#   ./run-macos.sh -focus jupiter -timeScale 5000 -showISS
#   ./run-macos.sh -frameLog
#
# If /Applications isn't writable by the current user (unusual on a personal
# Mac where the first account is in the `admin` group) the script falls back
# to ~/Applications automatically — no sudo prompt.

set -euo pipefail

cd "$(dirname "$0")"

SCHEME="SolarSystem"
CONFIG="Release"
PROJECT="$SCHEME.xcodeproj"

# ---------------------------------------------------------------------------
# 1. Terminate any running instance so the install `cp` and subsequent launch
#    don't trip over "the file is in use" / leave a stale window open.
# ---------------------------------------------------------------------------
pkill -f "Contents/MacOS/$SCHEME" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. Build the Release configuration for macOS. `| tail -6` surfaces just the
#    summary + final status line; the full transcript is visible with a plain
#    `xcodebuild` invocation if anything goes wrong.
# ---------------------------------------------------------------------------
echo "==> xcodebuild $SCHEME ($CONFIG, macOS)"
xcodebuild -project "$PROJECT" \
           -scheme "$SCHEME" \
           -configuration "$CONFIG" \
           -destination 'platform=macOS' \
           build 2>&1 | tail -6

# ---------------------------------------------------------------------------
# 3. Locate the built .app under DerivedData. Release builds land in
#    .../Build/Products/Release/ (vs Debug/). Using a glob lets the script
#    work across multiple Xcode-generated hash suffixes.
# ---------------------------------------------------------------------------
BUILT_APP=$(find "$HOME/Library/Developer/Xcode/DerivedData/$SCHEME"-*/Build/Products/$CONFIG/"$SCHEME.app" -maxdepth 0 2>/dev/null | head -1)
if [ -z "$BUILT_APP" ] || [ ! -d "$BUILT_APP" ]; then
    echo "error: built $CONFIG app not found under DerivedData" >&2
    echo "       tried: $HOME/Library/Developer/Xcode/DerivedData/$SCHEME-*/Build/Products/$CONFIG/$SCHEME.app" >&2
    exit 1
fi
echo "    built: $BUILT_APP"

# ---------------------------------------------------------------------------
# 4. Install into /Applications (or ~/Applications fallback).
#    `cp -R` preserves the .app bundle structure + signatures.
# ---------------------------------------------------------------------------
DEST="/Applications"
if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
    echo "    /Applications not writable; installing to $DEST"
fi

TARGET="$DEST/$SCHEME.app"
rm -rf "$TARGET"
cp -R "$BUILT_APP" "$TARGET"
echo "    installed: $TARGET"

# ---------------------------------------------------------------------------
# 5. Launch. `open -n` forces a fresh instance even if the installed copy is
#    already running; any remaining args after `--` are passed as launch-args
#    so flags like -mission / -frameLog / -focus behave identically to iOS.
# ---------------------------------------------------------------------------
echo "==> launching"
if [ $# -gt 0 ]; then
    open -n "$TARGET" --args "$@"
else
    open -n "$TARGET"
fi

echo "done."
