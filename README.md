# backup-tm

A lightweight incremental backup for macOS using `rsync`, controlled from a menu bar icon powered by SwiftBar.

## Features

- **Single in-place backup** — each run updates one full backup directory with `rsync --delete`
- **Automatic daily schedule** — runs at a configured time via a LaunchAgent (no cron, survives sleep)
- **Menu bar control** — a TM icon lets you start/stop backups and check status at a glance
- **Encrypted drive support** — automatically unlocks APFS-encrypted drives via macOS Keychain
- **Partial backup detection** — if rsync encounters transfer errors the backup is flagged as partial, not successful
- **Legacy snapshot migration** — old timestamped snapshot layouts are migrated to `current/` and cleaned up automatically
- **Software manifests** — saves lists of App Store apps, Homebrew formulae/casks, and system info with each backup

## Requirements

- macOS 13 (Ventura) or later
- An external drive (encrypted or unencrypted)
- [Homebrew](https://brew.sh) (installed automatically if missing)
- [SwiftBar](https://github.com/swiftbar/SwiftBar) (installed automatically)

## Install

```bash
git clone https://github.com/aborroy/backup-tm.git
cd backup-tm
chmod +x install.sh
./install.sh
```

The installer prompts for your configuration, then:

1. Writes `~/.config/backup-tm/config` with your settings
2. Installs Homebrew if missing
3. Installs SwiftBar if missing
4. Copies `backup.sh`, `backup-stop.sh`, and `BackupRunner.app` to `~/scripts/`
5. Installs the SwiftBar plugin for the menu bar icon
6. Registers the LaunchAgent to run the backup on your chosen daily schedule
7. Registers a LaunchAgent to start SwiftBar automatically at login
8. Launches SwiftBar

## Uninstall

```bash
./uninstall.sh
```

## Configuration

All settings live in `~/.config/backup-tm/config`. The installer creates this file interactively. To reconfigure, edit it directly and re-run `install.sh`.

| Variable | Default | Description |
|---|---|---|
| `VOLUME_NAME` | `BackupDisk` | Name of the external drive (mounted at `/Volumes/<name>`) |
| `DISK_IDENTIFIER` | _(empty)_ | Disk identifier for APFS-encrypted drives (e.g. `disk2s1`). Leave empty for unencrypted drives or manual mount. Find it with `diskutil list`. |
| `SCHEDULE_HOUR` | `14` | Hour for the daily backup (24-hour clock) |
| `SCHEDULE_MINUTE` | `0` | Minute for the daily backup |

### Encrypted drives

If `DISK_IDENTIFIER` is set, the backup script unlocks the drive automatically before each run using a passphrase stored in the macOS Keychain. To store the passphrase:

```bash
security add-generic-password -s backup-tm -a "<VOLUME_NAME>" -w
```

The installer offers to do this for you during setup.

## Backup layout

```
/Volumes/<VOLUME_NAME>/Backup/<hostname>/
├── current/
│   ├── manifests/
│   │   ├── appstore.txt
│   │   ├── applications.txt
│   │   ├── brew-formulae.txt
│   │   ├── brew-casks.txt
│   │   └── system.txt
│   └── ... (rsync mirror of home directory)
└── latest -> current/   ← compatibility symlink
```

## Menu bar usage

Click the **TM** icon in the menu bar to:

- See the last backup date and status (green = success, orange = partial or disk offline, red = never)
- **Run Backup Now** — trigger an immediate backup via `BackupRunner.app`
- **Stop Backup** — stop a running backup mid-run
- **Open Log** — view the detailed log at `~/Library/Logs/backup.log`
- **Reveal Backup Folder** — open the backup folder in Finder

## File structure

```
backup-tm/
├── BackupRunner.app                                   # app wrapper used for scheduled/manual launches
├── backup.sh                                          # main rsync backup script
├── backup-stop.sh                                     # scoped stop helper (used by SwiftBar action)
├── config.example                                     # configuration template
├── swiftbar-plugin/
│   └── backup.30s.sh                                  # SwiftBar menu bar plugin (refreshes every 30s)
├── launchagent/
│   ├── org.aborroy.backup-tm.backup.plist             # LaunchAgent for daily scheduling
│   └── org.aborroy.backup-tm.swiftbar-autostart.plist # LaunchAgent to open SwiftBar at login
├── validate.sh                                        # syntax and lint checks
├── install.sh                                         # automated installer
└── uninstall.sh                                       # automated uninstaller
```

## License

MIT
