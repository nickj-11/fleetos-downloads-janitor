#!/bin/bash
#
# Installs the FleetOS Downloads Janitor.
# Run this once, grant one permission, then never think about it again.
#
set -euo pipefail

LABEL="com.fleetos.downloads-janitor"
APP_NAME="FleetOS Downloads Janitor"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Prefer /Applications: it is where macOS expects applications to live, and it is
# where any permissions UI will point you if you ever need to find this app by
# hand. Fall back to ~/Applications when /Applications is not writable.
if [ -w /Applications ]; then
  APP_PARENT="/Applications"
else
  APP_PARENT="$HOME/Applications"
fi
APP="$APP_PARENT/$APP_NAME.app"
CONFIG_DIR="$HOME/.config/fleetos-downloads-janitor"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_FILE="$HOME/Library/Logs/fleetos-downloads-janitor.log"
INTERVAL_SECONDS="${FDJ_INTERVAL_SECONDS:-900}"   # sweep every 15 minutes

echo "==> Installing $APP_NAME"

# 1. Build the app bundle.
#    macOS attaches file-access permission to APPLICATIONS, identified by their
#    compiled executable -- so a shell script cannot hold a permission even when
#    it sits inside a .app (the OS sees /bin/bash, which can never be granted
#    anything). osacompile produces a real Mach-O executable that can, and it
#    ships on every Mac, so there is nothing for you to install.

# Clear out a copy left by an earlier install in the other Applications folder,
# so there is never more than one and you cannot approve the wrong one.
for stale_parent in "/Applications" "$HOME/Applications"; do
  [ "$stale_parent" = "$APP_PARENT" ] && continue
  if [ -d "$stale_parent/$APP_NAME.app" ]; then
    rm -rf "$stale_parent/$APP_NAME.app"
    echo "    cleaned  -> removed old copy at $stale_parent/$APP_NAME.app"
  fi
done

rm -rf "$APP"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

cat > "$BUILD_DIR/wrapper.applescript" <<'APPLESCRIPT'
on run
	set appPath to POSIX path of (path to me)
	set theScript to quoted form of (appPath & "Contents/Resources/janitor.sh")
	try
		do shell script theScript
	on error errMsg
		-- Record the failure in the log rather than showing a dialog: this runs
		-- unattended, and a modal alert nobody is there to dismiss helps no one.
		try
			do shell script "printf '%s  APPLET ERROR: %s\\n' \"$(date '+%Y-%m-%d %H:%M:%S')\" " & ¬
				quoted form of errMsg & " >> \"$HOME/Library/Logs/fleetos-downloads-janitor.log\""
		end try
	end try
end run
APPLESCRIPT

osacompile -o "$APP" "$BUILD_DIR/wrapper.applescript"

mkdir -p "$APP/Contents/Resources"
cp "$SRC_DIR/bin/janitor.sh"  "$APP/Contents/Resources/janitor.sh"
cp "$SRC_DIR/bin/launcher.sh" "$APP/Contents/Resources/launcher.sh"
chmod +x "$APP/Contents/Resources/janitor.sh" "$APP/Contents/Resources/launcher.sh"

PB=/usr/libexec/PlistBuddy
IP="$APP/Contents/Info.plist"
$PB -c "Set :CFBundleIdentifier $LABEL"          "$IP" 2>/dev/null || $PB -c "Add :CFBundleIdentifier string $LABEL"          "$IP"
$PB -c "Set :CFBundleName $APP_NAME"             "$IP" 2>/dev/null || $PB -c "Add :CFBundleName string $APP_NAME"             "$IP"
$PB -c "Set :CFBundleShortVersionString 1.1.0"   "$IP" 2>/dev/null || $PB -c "Add :CFBundleShortVersionString string 1.1.0"   "$IP"
$PB -c "Add :LSUIElement bool true"              "$IP" 2>/dev/null || true

# Sign last: editing Info.plist invalidates any earlier signature.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 \
  && echo "    app     -> $APP (signed)" \
  || echo "    app     -> $APP (unsigned -- re-approve access if you move it)"

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
        <string>/bin/bash</string>
        <string>$APP/Contents/Resources/launcher.sh</string>
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

# 4. Trigger the permission prompt now, while you are sitting here.
#    macOS asks once, on first access. If that first access happened later from
#    the background schedule with nobody at the keyboard, the prompt could be
#    missed and the denial remembered -- so we provoke it deliberately, now.
cat <<'BANNER'

-------------------------------------------------------------------
  macOS is about to ask, once, whether this app may access your
  Downloads folder.

  Click  "Allow"  (or "OK").

  That is the entire setup. There is nothing to configure in
  System Settings.
-------------------------------------------------------------------

BANNER

# Remember where the log ends NOW, so a line left over from an earlier install
# can never be mistaken for proof that this one works.
before=$(grep -cE '^[0-9]{4}-' "$LOG_FILE" 2>/dev/null || echo 0)

# Run exactly what launchd will run, so this verifies the real path rather
# than an approximation of it.
/bin/bash "$APP/Contents/Resources/launcher.sh" >/dev/null 2>&1 &

# 5. Verify it actually worked, rather than assuming.
printf "Waiting for the permission decision"
ok=0
for _ in $(seq 1 45); do
  printf "."
  sleep 1
  now=$(grep -cE '^[0-9]{4}-' "$LOG_FILE" 2>/dev/null || echo 0)
  [ "$now" -gt "$before" ] || continue          # nothing new yet -- keep waiting
  last=$(grep -E '^[0-9]{4}-' "$LOG_FILE" | tail -1)
  case "$last" in
    *swept*) ok=1; break ;;
    *ABORT*) break ;;                            # a fresh, definite failure
  esac
done
echo ""
echo ""

if [ "$ok" = "1" ]; then
  cat <<DONE
==> Working. It sweeps every $((INTERVAL_SECONDS / 60)) minutes from now on, forever.

    $(grep -E '^[0-9]{4}-' "$LOG_FILE" | tail -1)

    Check on it:  tail -5 "$LOG_FILE"
    Sweep now:    launchctl kickstart -k gui/\$UID/$LABEL
    Uninstall:    "$SRC_DIR/uninstall.sh"

You can delete this folder now -- the janitor does not need it.
DONE
else
  cat <<NOTYET
==> Not confirmed yet.

    If you did not see a prompt, or you clicked "Don't Allow", turn access on by hand:
      System Settings > Privacy & Security > Files and Folders
        > $APP_NAME > Downloads Folder  (switch ON)

    Then re-check with:
      launchctl kickstart -k gui/\$UID/$LABEL && sleep 3 && tail -3 "$LOG_FILE"

    The log will tell you exactly what it is blocked on:
      tail -5 "$LOG_FILE"
NOTYET
fi
