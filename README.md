# Bonsai

Bonsai is a Mac menu-bar app that shows where your disk space goes when you work with many git worktrees, and removes what is safe to remove, by hand or automatically. Before it removes anything it checks for work that would be lost, and refuses if it finds any. It comes with a command-line tool, `clean-claude`, that does the same things from a terminal.

It looks at:

- **Git worktrees**: every worktree of every repo under your scan folders (default `~/Documents/GitHub`), including the ones Claude's desktop app and Cursor create. It shows each one's size, how long it has been idle, and whether it can be removed.
- **Dependencies and build output** inside those worktrees: `node_modules`, `dist`, `.build` and similar folders that a package manager or compiler can bring back.
- **Xcode DerivedData** left behind by projects that no longer exist.
- **Docker Desktop**: where its disk space goes, and `docker system prune -f`.
- **iOS Simulators**: their size, and `xcrun simctl delete unavailable`.
- **Claude's own data** (transcripts, Claude Code versions, the desktop app's storage): sizes only. Bonsai never changes it.

<!-- Screenshots: put the images in docs/ and link them here, for example ![Worktrees](docs/worktrees.png) -->

## Install

Bonsai needs macOS 14 or newer, on Intel or Apple silicon.

1. Download `Bonsai-<version>.dmg` from [Releases](https://github.com/brauliovc1/clean-claude/releases).
2. Open it and drag Bonsai to Applications.
3. Open Bonsai. It lives in the menu bar: click its icon, then **Open Bonsai**.

The app is not signed with an Apple Developer ID, so macOS blocks it the first time. After the block message, open **System Settings > Privacy & Security**, scroll down to the message about Bonsai, click **Open Anyway**, and confirm. (On macOS 14 you can instead Control-click the app and choose Open.) If that doesn't work, remove the download mark in Terminal:

```bash
xattr -dr com.apple.quarantine "/Applications/Bonsai.app"
```

Each release also has `clean-claude-<version>-macos.zip` (the command-line tool; unzip it and put `clean-claude` on your `PATH`; if macOS blocks it, run `xattr -d com.apple.quarantine clean-claude`) and `SHA256SUMS`. To check a download, run `shasum -a 256 -c SHA256SUMS` in the folder that has the files.

## Build from source

You need macOS 14 or newer and Xcode 16 or newer (Swift 6).

```bash
git clone https://github.com/brauliovc1/clean-claude.git
cd clean-claude
make install
```

This builds Bonsai, signs it ad hoc, puts `Bonsai.app` in `/Applications` and the `clean-claude` command in `~/.local/bin`. It needs no `sudo`. If `~/.local/bin` is not on your `PATH`, `make install` prints the line to add. It refuses to run while Bonsai is running from `/Applications`: quit it first. A build you make yourself doesn't get the "Open Anyway" block.

Other targets: `make app` builds `build/Bonsai.app` without installing, `make test` runs the tests, and `make dist` builds the release files (the `.dmg`, the command-line zip and `SHA256SUMS`, for Intel and Apple silicon) in `dist/`.

## Command line

```
clean-claude scan                  List worktrees: repo, branch, kind, size, idle days, and whether each can be removed
clean-claude remove <path>...      Remove worktrees the safe way (git worktree remove, never --force)
clean-claude restore <id>          Put a removed worktree back from its kept branch
clean-claude prune                 Clear git's records of worktrees whose folders are gone
clean-claude light-clean <path>    Delete a worktree's node_modules, dist, .build and similar folders
clean-claude derived-data          List Xcode DerivedData folders; delete the orphaned ones
clean-claude docker                Show Docker Desktop's disk use; run docker system prune -f
clean-claude simulators            Show Simulator disk use; delete unavailable devices
clean-claude claude-usage          Show how much space Claude's data takes (read-only)
clean-claude auto                  Print what auto mode would remove, notify about and skip
clean-claude log                   Show every cleanup done so far
clean-claude settings              Show the settings (read-only)
```

**Every command that deletes or changes something is a dry run unless you add `--yes`.** Without it, the command prints what it would do and why, and changes nothing.

```bash
clean-claude scan --status safe                      # worktrees you can remove by hand
clean-claude remove ~/Documents/GitHub/app-feature   # dry run: the verdict and its reasons
clean-claude remove ~/Documents/GitHub/app-feature --yes
```

`--root <folder>` picks the folders to scan (repeatable). `clean-claude <command> --help` has the details.

## What it deletes, and what it never deletes

Bonsai deletes only what you confirm (or, in auto mode, what passes every check below), and it checks again right before each delete. If anything changed since you confirmed, that item is refused. Every cleanup is written to a log (`clean-claude log`, or **Recently removed** in the app).

### Removing a worktree

A worktree is always removed with `git worktree remove`: never `--force`, never `rm -rf`. **The branch is always kept**, so the commits stay.

| If the worktree... | By hand | Auto mode |
|---|---|---|
| is the repo's main checkout | never | never |
| has no folder any more | offers `git worktree prune` for git's stale record (refused if the drive may just be unplugged, or if a commit would be lost) | never |
| is locked (`git worktree lock`) | blocked | blocked |
| has a running program inside (a terminal, an editor) | blocked, names the program | blocked |
| has uncommitted or untracked files | blocked | blocked |
| has edits git hides (`assume-unchanged`, `skip-worktree`) | blocked | blocked |
| is in the middle of a rebase, merge, cherry-pick, revert or bisect | blocked | blocked |
| has another worktree inside it, or another git checkout (even inside `node_modules` or `.venv`) that holds work of yours | blocked | blocked |
| has submodules | blocked | blocked |
| has commits that are on no remote | on a branch: allowed, with a note (the kept branch holds them); detached HEAD: blocked | blocked |
| has commits that only its own history holds (detached HEAD, no branch or tag) | blocked | blocked |
| has a stash made on its branch | allowed, with a note (stashes belong to the repo and stay) | blocked |
| has ignored files that are not build output (a `.env`, say) | allowed, and the files are listed in the confirmation | blocked, and reported |
| belongs to a Claude session | allowed, with a warning (below) | skipped, unless you turn it on |
| was used less than 30 days ago (you can change this) | allowed | skipped |
| has a last-used date that can't be worked out | allowed | skipped |

Clones that hold nothing of yours (SwiftPM and Xcode package checkouts) don't block removal. A repo with no remote at all never qualifies for auto mode, because every commit in it is "on no remote".

The warning for a Claude session reads: "This worktree belongs to a Claude session. Removing it deletes the session's folder, so that session can't continue where it left off. The branch is kept."

**Idle** means the newest of: the last commit, git's own activity in the worktree, the last file change outside dependency and build folders, and the last Claude conversation for that folder.

### Light clean (by hand only)

Light clean deletes dependency and build-output folders from one worktree, from this list and nothing else: `node_modules`, `.next`, `.nuxt`, `.svelte-kit`, `.turbo`, `.parcel-cache`, `.angular`, `coverage`, `dist`, `dist-test`, `build`, `.build`, `.dart_tool`, `Pods`, `.gradle`, `__pycache__`, `.pytest_cache`, `.mypy_cache`, `.ruff_cache`, `.venv`, `venv`, `target`, `DerivedData`, `.expo`.

A folder is deleted only if git ignores it and tracks nothing in it, it is a real folder (not a link), nothing in it shows up in `git status`, it holds no checkout with work in it, and no program has its working folder anywhere in the worktree. Deleted folders can't be restored; install or build again to get them back. Auto mode never does this.

### DerivedData, Docker, Simulators

- **DerivedData:** deletes a folder only when its `info.plist` names a project that no longer exists. Projects that still exist are listed but never deleted, and so are folders without an `info.plist`. A project on a drive that isn't plugged in doesn't count as gone.
- **Docker:** only while Docker Desktop is running, and only `docker system prune -f` (stopped containers, unused networks, dangling images and build cache; no `-a`, no `--volumes`). Docker Desktop may not shrink its disk file right away, so the space you get back can show as close to zero.
- **Simulators:** only `xcrun simctl delete unavailable`.

### What it never touches

- Claude's data: `~/.claude` and `~/Library/Application Support/Claude`. Bonsai has no code that deletes there. To free that space, use Claude > Settings > This computer > Storage.
- Branches.
- A repo's main checkout. Light clean can empty its dependency folders if you ask; nothing else in it is touched.
- A worktree while a program has its working folder inside it.

### Restore

A removed worktree can be put back from its kept branch with **Restore** in Recently removed (or `clean-claude restore <id>`). Restore makes the worktree again from that branch: the files git tracks come back. Ignored files (a `.env`, say) and dependencies do not; reinstall those yourself.

## Auto mode

Auto mode is **off** until you turn it on. When you do, it only reports for the first 7 days: it shows what it would remove and removes nothing. After that it runs once a day and removes whole worktrees that have been idle 30 days or more and pass every check in the table. It keeps their branches. Worktrees that hold work of yours only get a notification.

It skips Claude's worktrees unless you turn that on in Settings, and it never runs light clean. It runs **only while Bonsai is running**, so keep it running (launch at login does that); if the app is not running, nothing is deleted.

## Known limits

- Sizes are estimates. APFS lets files share disk blocks, so the space you really get back is measured from the disk afterwards and can be lower.
- Time Machine's local snapshots can hold deleted data until they expire.
- The first scan of `~/Documents` makes macOS ask once whether Bonsai may access files in your Documents folder.
- The app is unsigned (see Install). Building from source avoids the "Open Anyway" step.
- How Claude names its conversation folders is not documented. When a name doesn't match what Bonsai expects, that signal is skipped, and a worktree you have only talked to Claude about can look idle.
- Only Docker Desktop is supported, not OrbStack or colima.
- If a `docker system prune` is interrupted (you quit the app or press Ctrl-C while it runs), it is not written to the log.
- Right before deleting a folder, Bonsai checks it is a real folder and not a link. If that folder is swapped for a link to somewhere else *while* a large folder is being deleted, the rest of that delete can follow the link. Nothing in Bonsai does this; it takes another program changing files at that exact moment.
- If git's record spells a parent folder in a different case than the disk does (macOS treats `Src` and `src` as one folder), an unedited tracked file inside a cleaned folder can be deleted. `git restore <file>` brings it back.

## Privacy

Bonsai makes no network connections of its own and has no telemetry. It runs `git`, `du`, `lsof`, `defaults`, `xcode-select`, `xcrun` and `docker` on your Mac.

Apart from the cleanups described above, it writes only in `~/Library/Application Support/clean-claude/`: `settings.json` (your settings), `removals.jsonl` (the log of every cleanup) and `sizes.json` (a size cache). Everything else it does is reading: your scan folders, DerivedData, and the Docker, Simulator and Claude data folders it measures.

## Uninstall

Quit Bonsai, then:

```bash
rm -r "/Applications/Bonsai.app"
rm "$HOME/.local/bin/clean-claude"
rm -r "$HOME/Library/Application Support/clean-claude"
```

That removes the app, the command, and the settings, log and size cache. If you turned on launch at login, also remove Bonsai under System Settings > General > Login Items.

## License

[MIT](LICENSE)
