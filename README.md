# FleetOS Downloads Janitor

Your Turo trip-earnings exports pile up in `~/Downloads` forever. This deletes them for you, quietly, every 15 minutes, for the rest of time.

If you use the FleetOS Chrome extension to pull Turo earnings into FleetOS, it downloads a CSV every time it runs — several a day, ~400 KB each. They are useless once FleetOS has imported them, but nothing ever cleans them up. After a couple of months you have hundreds of files and hundreds of megabytes of the exact same export.

Install this once. You will never see them again.

```
trip_earnings_export_20260915 (8).csv
trip_earnings_export_20260915 (7).csv
trip_earnings_export_20260915 (6).csv
trip_earnings_export_20260915 (5).csv     ← 234 of these, 83 MB
trip_earnings_export_20260915 (4).csv
...
```

**macOS only.** Requires nothing but a Mac — no Homebrew, no Python, no Claude subscription, no FleetOS account.

---

## Install

```bash
git clone https://github.com/nickj-11/fleetos-downloads-janitor.git
cd fleetos-downloads-janitor
./install.sh
```

(No `git`? [Download the ZIP](https://github.com/nickj-11/fleetos-downloads-janitor/archive/refs/heads/main.zip), unzip it, then drag the folder into Terminal after typing `cd ` and run `./install.sh`.)

The installer will open System Settings and ask you to do **one thing, once**:

> **System Settings → Privacy & Security → Full Disk Access → `+` →**
> Cmd-Shift-G → `~/Applications` → pick **FleetOS Downloads Janitor** → switch it **ON**

That is the whole setup. macOS does not let *any* background task touch your Downloads or Trash folder until you say so — there is no way around it, for any tool. This is that one permission.

Confirm it is working:

```bash
tail -5 ~/Library/Logs/fleetos-downloads-janitor.log
```

You want to see a line like `swept /Users/you/Downloads -- trashed 234 file(s) (83 MB), 0 failure(s)`. If it says *No permission to read* instead, the switch above is not on yet.

Then delete the folder you cloned. The janitor does not need it.

---

## What it actually does

Every 15 minutes it looks in `~/Downloads` for files named `trip_earnings_export_*.csv` that are **more than 2 hours old**, and moves them to the Trash.

That is all it does. Specifically, it will **not**:

- touch any file that does not match that exact name pattern
- look in any folder other than `~/Downloads`, or in any subfolder
- touch a file downloaded in the last 2 hours, so an import that is still running is never disturbed
- `rm` anything — everything goes to the **Trash**, where you can drag it back out for as long as you like

It refuses to start if the pattern is empty, contains a `/`, or is a bare `*`. And if macOS is blocking it, it stops and says so in the log — it will never quietly report success on a folder it could not read.

## Changing it

Edit `~/.config/fleetos-downloads-janitor/config`:

```bash
FDJ_WATCH_DIR="$HOME/Downloads"                # folder to sweep
FDJ_PATTERN="trip_earnings_export_*.csv"       # filename glob, no slashes
FDJ_MIN_AGE_MINUTES=120                        # grace period before trashing
```

Apply your changes:

```bash
launchctl kickstart -k gui/$UID/com.fleetos.downloads-janitor
```

Want it to clean up something else entirely — Wheelbase exports, bank statements, screenshots? Change `FDJ_PATTERN`. It is not Turo-specific; Turo is just what it ships pointed at.

## Handy commands

```bash
# Sweep right now instead of waiting
launchctl kickstart -k gui/$UID/com.fleetos.downloads-janitor

# See what it would trash, without trashing anything
"$HOME/Applications/FleetOS Downloads Janitor.app/Contents/MacOS/janitor" --dry-run

# Read the log
tail -20 ~/Library/Logs/fleetos-downloads-janitor.log

# Is it loaded?
launchctl print gui/$UID/com.fleetos.downloads-janitor | grep -E 'state|last exit'
```

## Uninstall

```bash
./uninstall.sh
```

Removes the app and the scheduled job. Your files, your Trash, and your config are left alone. You can also remove the leftover entry from Full Disk Access afterwards.

## FAQ

**Will this delete a file before FleetOS imports it?**
No. Nothing is touched until it has sat there for 2 hours, and the import happens seconds after the download. Raise `FDJ_MIN_AGE_MINUTES` if you want a bigger cushion.

**Where do the files go?**
The Trash. They stay there until you empty it, or for 30 days if you have "Remove items from Trash after 30 days" turned on.

**Why does it need Full Disk Access?**
Because `~/Downloads` and `~/.Trash` are protected folders on macOS, and a scheduled background job has no other way to reach them. It only ever reads the one folder you point it at.

**Does it phone home / need an account?**
No. It is about 150 lines of shell script. Read it: [`bin/janitor.sh`](bin/janitor.sh).

## License

MIT — see [LICENSE](LICENSE).
