#!/bin/bash
#
# Removes the FleetOS Downloads Janitor completely.
# Nothing in your Downloads or Trash is touched.
#
set -uo pipefail

LABEL="com.fleetos.downloads-janitor"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_NAME="FleetOS Downloads Janitor.app"

echo "==> Uninstalling FleetOS Downloads Janitor"
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
rm -f  "$PLIST" && echo "    removed $PLIST"
for parent in "/Applications" "$HOME/Applications"; do
  if [ -d "$parent/$APP_NAME" ]; then
    rm -rf "$parent/$APP_NAME" && echo "    removed $parent/$APP_NAME"
  fi
done

cat <<DONE

==> Done.
    Kept (delete by hand if you want them gone):
      ~/.config/fleetos-downloads-janitor/
      ~/Library/Logs/fleetos-downloads-janitor.log
    macOS drops the folder permission along with the app; there is no
    leftover entry for you to clean up.
DONE
