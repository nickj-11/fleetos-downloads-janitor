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

macOS will ask **once** whether the app may look in your Downloads folder. Click **Allow**. That is the entire setup — there is nothing to configure in System Settings, and no Full Disk Access needed.

The installer then checks that a sweep actually ran and tells you either `==> Working` or exactly what is still wrong. It does not assume.

Confirm it is working:

```bash
tail -5 ~/Library/Logs/fleetos-downloads-janitor.log
```

You want to see a line like `swept /Users/you/Downloads -- trashed 234 file(s) (83 MB), 0 failure(s)`. If it says *No permission to read* instead, the prompt was missed or declined — the log says exactly how to fix it.

A scheduled sweep takes about half a minute (a background app launch is slow); a run you start yourself takes a second or two. Either way it is invisible — no window, no Dock icon.

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
"/Applications/FleetOS Downloads Janitor.app/Contents/Resources/janitor.sh" --dry-run

# Read the log
tail -20 ~/Library/Logs/fleetos-downloads-janitor.log

# Is it loaded?
launchctl print gui/$UID/com.fleetos.downloads-janitor | grep -E 'state|last exit'
```

## Uninstall

```bash
./uninstall.sh
```

Removes the app and the scheduled job. Your files, your Trash, and your config are left alone. macOS drops the permission with the app.

## FAQ

**Will this delete a file before FleetOS imports it?**
No. Nothing is touched until it has sat there for 2 hours, and the import happens seconds after the download. Raise `FDJ_MIN_AGE_MINUTES` if you want a bigger cushion.

**Where do the files go?**
The Trash. They stay there until you empty it, or for 30 days if you have "Remove items from Trash after 30 days" turned on.

**Why does it ask for permission at all?**
`~/Downloads` is a protected folder on macOS. Any tool that reads it needs your say-so — there is no way around that, for any tool. It asks for the Downloads folder only, not Full Disk Access.

**Why is it an app instead of just a script?**
Because macOS attaches permissions to *applications*, identified by their compiled executable. A shell script cannot hold a permission even inside a `.app` — the system sees `/bin/bash`, which can never be granted anything, so a plain scheduled script gets "Operation not permitted" forever with nothing you can click to fix it. The app is a thin wrapper (built on your machine by `osacompile`, which ships with macOS) that exists purely to have an identity you can approve.

**If I click "Don't Allow" by mistake?**
Turn it back on at System Settings → Privacy & Security → Files and Folders → FleetOS Downloads Janitor → Downloads Folder. The log will tell you that is what it is waiting on.

**Does it phone home / need an account?**
No. It is about 150 lines of shell script. Read it: [`bin/janitor.sh`](bin/janitor.sh).

## License

MIT — see [LICENSE](LICENSE).
