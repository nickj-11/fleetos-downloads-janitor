#!/bin/bash
#
# Installs the FleetOS Downloads Janitor.
# Run this once, grant one permission, then never think about it again.
#
set -euo pipefail

LABEL="com.fleetos.downloads-janitor"
APP_NAME="FleetOS Downloads Janitor"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HOME/Applications/$APP_NAME.app"
CONFIG_DIR="$HOME/.config/fleetos-downloads-janitor"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_FILE="$HOME/Library/Logs/fleetos-downloads-janitor.log"
INTERVAL_SECONDS="${FDJ_INTERVAL_SECONDS:-900}"   # sweep every 15 minutes

echo "==> Installing $APP_NAME"

# 1. Build a tiny app bundle.
#    macOS grants file-access permission to APPLICATIONS, not to loose scripts --
#    so the janitor ships as an app so it has an identity to grant.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>        <string>$LABEL</string>
    <key>CFBundleExecutable</key>        <string>janitor</string>
    <key>CFBundleVersion</key>           <string>1.0.0</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>LSMinimumSystemVersion</key>    <string>11.0</string>
    <key>LSBackgroundOnly</key>          <true/>
    <key>LSUIElement</key>               <true/>
</dict>
</plist>
PLISTEOF

cp "$SRC_DIR/bin/janitor.sh" "$APP/Contents/MacOS/janitor"
chmod +x "$APP/Contents/MacOS/janitor"

# Ad-hoc sign so the permission you grant sticks to this app and survives updates.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 \
  && echo "    app     -> $APP (signed)" \
  || echo "    app     -> $APP (unsigned -- fine, but re-grant access if you move it)"

# 2. Write a config file only if one does not already exist (never clobber your edits).
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/config" ]; then
  cat > "$CONFIG_DIR/config" <<'CONFIG'
# FleetOS Downloads Janitor -- settings
# After editing, apply with:
#   launchctl kickstart -k gui/$UID/com.fleetos.downloads-janitor

# Folder to sweep (non-recursive).
FDJ_WATCH_DIR="$HOME/Downloads"

# Which files to sweep. Filename glob only -- no slashes, and never a bare "*".
FDJ_PATTERN="trip_earnings_export_*.csv"

# Grace period: a file is only trashed once it is older than this many minutes,
# so an import that is still running is never disturbed.
FDJ_MIN_AGE_MINUTES=120
CONFIG
  echo "    config  -> $CONFIG_DIR/config"
else
  echo "    config  -> $CONFIG_DIR/config (kept your existing one)"
fi

# 3. Write and load the launchd agent, pointed at the app's executable.
mkdir -p "$HOME/Library/LaunchAgents" "$(dirname "$LOG_FILE")"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/janitor</string>
    </array>
    <key>StartInterval</key>
    <integer>$INTERVAL_SECONDS</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
PLISTEOF
echo "    agent   -> $PLIST"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"
launchctl enable "gui/$UID/$LABEL" 2>/dev/null || true

# 4. The one manual step.
cat <<BANNER

-------------------------------------------------------------------
  ONE STEP LEFT -- and it is the only one, ever.

  macOS will not let any background job touch your Downloads or
  Trash folder until you say so. Give this app permission:

    1. System Settings > Privacy & Security > Full Disk Access
    2. Click "+"
    3. Press Cmd-Shift-G and paste:  ~/Applications
    4. Choose "$APP_NAME"
    5. Make sure its switch is ON

  Opening that settings pane for you now...
-------------------------------------------------------------------

BANNER

open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null || true
open "$HOME/Applications" 2>/dev/null || true

cat <<DONE
Once the switch is on, it sweeps every $((INTERVAL_SECONDS / 60)) minutes, forever.

  Check it worked:  tail -5 "$LOG_FILE"
  Sweep right now:  launchctl kickstart -k gui/\$UID/$LABEL
  Uninstall:        "$SRC_DIR/uninstall.sh"

You can delete this folder afterwards -- the janitor does not need it.
DONE
