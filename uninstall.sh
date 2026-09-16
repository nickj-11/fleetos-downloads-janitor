#!/bin/bash
#
# Removes the FleetOS Downloads Janitor completely.
# Nothing in your Downloads or Trash is touched.
#
set -uo pipefail

LABEL="com.fleetos.downloads-janitor"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="$HOME/Applications/FleetOS Downloads Janitor.app"

echo "==> Uninstalling FleetOS Downloads Janitor"
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
rm -f  "$PLIST" && echo "    removed $PLIST"
rm -rf "$APP"   && echo "    removed $APP"

cat <<DONE

==> Done.
    Kept (delete by hand if you want them gone):
      ~/.config/fleetos-downloads-janitor/
      ~/Library/Logs/fleetos-downloads-janitor.log
    You may also want to remove the now-dead Full Disk Access entry in
    System Settings > Privacy & Security > Full Disk Access.
DONE
