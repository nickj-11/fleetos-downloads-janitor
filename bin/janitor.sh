#!/bin/bash
#
# FleetOS Downloads Janitor
# Moves stale Turo trip-earnings CSV exports out of ~/Downloads and into the Trash.
#
# Safe by design:
#   - Only ever touches the ONE folder it is pointed at (default ~/Downloads), non-recursive.
#   - Only touches files matching an explicit filename pattern.
#   - Only touches files older than a grace period, so an in-flight import is never disturbed.
#   - Moves to the Trash (recoverable) -- never rm.
#   - Refuses to run, loudly, if macOS has not granted it access. It never reports
#     success on a folder it could not actually read.
#
set -uo pipefail

CONFIG_FILE="${FDJ_CONFIG:-$HOME/.config/fleetos-downloads-janitor/config}"
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

WATCH_DIR="${FDJ_WATCH_DIR:-$HOME/Downloads}"
PATTERN="${FDJ_PATTERN:-trip_earnings_export_*.csv}"
MIN_AGE_MINUTES="${FDJ_MIN_AGE_MINUTES:-120}"
TRASH_DIR="${FDJ_TRASH_DIR:-$HOME/.Trash}"
LOG_FILE="${FDJ_LOG_FILE:-$HOME/Library/Logs/fleetos-downloads-janitor.log}"
LOG_MAX_BYTES="${FDJ_LOG_MAX_BYTES:-1048576}"
DRY_RUN="${FDJ_DRY_RUN:-0}"

# Where this script lives, so permission errors can name the exact app to approve.
SELF="$0"
case "$SELF" in
  */*.app/Contents/MacOS/*) APP_PATH="${SELF%%.app/Contents/MacOS/*}.app" ;;
  *)                        APP_PATH="the FleetOS Downloads Janitor app" ;;
esac

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h)
      cat <<USAGE
Usage: janitor [--dry-run]

Moves files matching a pattern out of a watch folder into the Trash once they
are older than a grace period.

Current settings (edit $CONFIG_FILE):
  FDJ_WATCH_DIR        $WATCH_DIR
  FDJ_PATTERN          $PATTERN
  FDJ_MIN_AGE_MINUTES  $MIN_AGE_MINUTES
  FDJ_TRASH_DIR        $TRASH_DIR
  FDJ_LOG_FILE         $LOG_FILE
USAGE
      exit 0 ;;
    *) echo "Unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

# Rotate the log before writing so it can never grow without bound.
if [ -f "$LOG_FILE" ]; then
  size=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
  [ "$size" -gt "$LOG_MAX_BYTES" ] && mv -f "$LOG_FILE" "$LOG_FILE.1"
fi

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"; }
die() { log "ABORT: $1"; echo "$1" >&2; exit "${2:-1}"; }

# --- Guardrails -------------------------------------------------------------
case "$PATTERN" in
  */*|*..*|'*'|'')
    die "Refusing unsafe pattern: '$PATTERN' (must be a filename glob, no slashes, not bare '*')" ;;
esac

[ -d "$WATCH_DIR" ] || die "Watch folder does not exist: $WATCH_DIR"

# --- Permission preflight ---------------------------------------------------
# macOS protects ~/Downloads and ~/.Trash. Without Full Disk Access every
# read returns "Operation not permitted" -- which, if swallowed, looks exactly
# like an empty folder. Check explicitly so a permission problem can never
# masquerade as "nothing to do".
if ! /bin/ls "$WATCH_DIR" >/dev/null 2>&1; then
  die "No permission to read $WATCH_DIR.
     macOS is blocking this. Grant Full Disk Access to:
       $APP_PATH
     System Settings > Privacy & Security > Full Disk Access > +" 78
fi

if [ ! -d "$TRASH_DIR" ]; then
  mkdir -p "$TRASH_DIR" 2>/dev/null || die "Cannot create trash folder: $TRASH_DIR" 78
fi

probe="$TRASH_DIR/.fleetos-janitor-write-test.$$"
if ! (: > "$probe") 2>/dev/null; then
  die "No permission to write to $TRASH_DIR.
     macOS is blocking this. Grant Full Disk Access to:
       $APP_PATH
     System Settings > Privacy & Security > Full Disk Access > +" 78
fi
rm -f "$probe"

# --- Sweep ------------------------------------------------------------------
moved=0
failed=0
bytes=0

while IFS= read -r file; do
  [ -f "$file" ] || continue
  base=$(basename "$file")
  dest="$TRASH_DIR/$base"

  # Never clobber something already sitting in the Trash.
  if [ -e "$dest" ]; then
    stem="${base%.*}"
    ext="${base##*.}"
    dest="$TRASH_DIR/${stem} $(date '+%Y-%m-%d %H.%M.%S').${ext}"
  fi

  size=$(stat -f%z "$file" 2>/dev/null || echo 0)

  if [ "$DRY_RUN" = "1" ]; then
    log "DRY-RUN would trash: $base"
    moved=$((moved + 1)); bytes=$((bytes + size))
    continue
  fi

  if mv -f "$file" "$dest" 2>>"$LOG_FILE"; then
    moved=$((moved + 1)); bytes=$((bytes + size))
  else
    failed=$((failed + 1)); log "FAILED to trash: $base"
  fi
done < <(find "$WATCH_DIR" -maxdepth 1 -type f -name "$PATTERN" -mmin "+$MIN_AGE_MINUTES" 2>/dev/null)

mb=$(( bytes / 1048576 ))
suffix=""; [ "$DRY_RUN" = "1" ] && suffix=" [dry run]"

if [ "$moved" -gt 0 ] || [ "$failed" -gt 0 ]; then
  log "swept $WATCH_DIR -- trashed $moved file(s) (${mb} MB), $failed failure(s)$suffix"
  echo "Trashed $moved file(s) (${mb} MB)$suffix"
else
  log "swept $WATCH_DIR -- nothing to do"
  echo "Nothing to do."
fi

[ "$failed" -gt 0 ] && exit 1
exit 0
