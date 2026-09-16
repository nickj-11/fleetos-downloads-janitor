#!/bin/bash
#
# What launchd actually runs.
#
# It starts the app's compiled executable and waits for it, so the real exit
# code reaches launchd. Two things it guards against:
#
#   - A first run can block on a macOS permission dialog. A blocked process
#     never exits, and while it lives it blocks every sweep after it -- the
#     files would quietly pile up again with the job still reported "running".
#     So there is a hard time limit.
#   - An instance wedged by an earlier run is cleared before starting a new one.
#
# This launcher touches no protected folder, so it needs no permission of its
# own. The app it starts is what holds the permission.
#
set -uo pipefail

APP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPLET="$APP/Contents/MacOS/applet"
TIMEOUT_SECONDS="${FDJ_TIMEOUT_SECONDS:-180}"

# Clear the applet AND any sweep it left behind: killing the applet does not
# kill the shell it spawned, and a stranded sweep holds the permission dialog
# open, which is what blocks everything after it.
for pid in $(pgrep -f "^$APPLET$" 2>/dev/null) \
           $(pgrep -f "^/bin/bash $APP/Contents/Resources/janitor.sh$" 2>/dev/null); do
  kill "$pid" 2>/dev/null || true
done

"$APPLET" &
child=$!

for _ in $(seq 1 "$TIMEOUT_SECONDS"); do
  kill -0 "$child" 2>/dev/null || break
  sleep 1
done

if kill -0 "$child" 2>/dev/null; then
  kill "$child" 2>/dev/null || true
  for pid in $(pgrep -f "^/bin/bash $APP/Contents/Resources/janitor.sh$" 2>/dev/null); do
    kill "$pid" 2>/dev/null || true
  done
  printf '%s  LAUNCHER: gave up after %ss (blocked, probably on a permission dialog)\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$TIMEOUT_SECONDS" \
    >> "${FDJ_LOG_FILE:-$HOME/Library/Logs/fleetos-downloads-janitor.log}"
  exit 75   # EX_TEMPFAIL
fi

wait "$child"
