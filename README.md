# MikroTik Smart Backup via FTP

Automated MikroTik configuration backup to an FTP server with **change detection** — a backup is performed only when the configuration has actually changed.

## What the script does

- Exports the current config and compares it with the previously saved state.
- If changes are detected — creates a `.backup` (binary) and `.rsc` (text export) file.
- Uploads both files to the SFTP server.
- Deletes local files **only after a successful upload**.
- If an upload fails — preserves local files and writes an error to the log.

### Filename format

```
<router-ip>_YYYY-MM-DD_<ros-version>.backup
<router-ip>_YYYY-MM-DD.rsc
```

Example: `10.11.97.1_2026-05-23_7.22.2.backup`

---

## Repository structure

```
├── backup.rsc                  # Main backup script
├── credentials.example.rsc     # Example credentials template (no real values)
└── README.md
```

---

## Installation

### 1. Add the credentials script

Copy `credentials.example.rsc`, fill in your values, and add it to RouterOS as a script named **`credentials`**:

```routeros
/system script add \
  name="credentials" \
  source={
    :global routerIp "10.11.97.1";
    :global ftphost "10.11.97.3";
    :global ftpuser "mikrotik_backup";
    :global ftppassword "yourpassword";
    :global ftppath "/Backups/Mikrotik_backups/";
  }
```

> Variables are named `ftp*` for historical reasons but the script uses **SFTP** (`mode=sftp`).

### 2. Add the config hash tracking script

This script is used to detect configuration changes between runs:

```routeros
/system script add \
  name="last-config-hash" \
  source="" \
  comment="DO NOT EDIT - used by smart-backup"
```

> This script will be created automatically on the first run if it does not exist. Creating it manually beforehand is recommended.

### 3. Add the main backup script

```routeros
/system script add \
  name="smart-backup" \
  source=[/file get backup.rsc contents]
```

Or paste the contents of `backup.rsc` manually via Winbox: **System → Scripts → Add**.

### 4. Schedule the script (every night at 03:00)

```routeros
/system scheduler add \
  name="nightly-backup" \
  start-time=03:00:00 \
  interval=1d \
  on-event="/system script run smart-backup" \
  comment="Nightly config backup to FTP"
```

---

## Verification

Run the script manually:

```routeros
/system script run smart-backup
```

View the logs:

```routeros
/log print where topics~"info|error"
```

Expected log messages:

| Situation | Log message |
|---|---|
| Changes detected, backup running | `Config change detected. Proceeding with backup.` |
| No changes | `No config changes detected. Backup skipped.` |
| Upload failed | `Failed to upload: <filename>` |
| Completed successfully | `Backup complete: <filename> - local files removed.` |

---

## Security

RouterOS has no built-in secrets manager. Recommended practices:

- **Separate `credentials` script** — passwords in one place, isolated from the main logic.
- **Restrict access** — SSH/Winbox only for admin accounts, ideally from specific IPs.
- **Isolated network** — place the FTP server on a dedicated management VLAN if possible.
- **Never commit `credentials.rsc`** — only `credentials.example.rsc` belongs in the repository (enforced via `.gitignore`).

---

## Compatibility

Tested on RouterOS **7.x**.  
RouterOS 7.x returns the date already in `YYYY-MM-DD` format. On RouterOS **6.x** the date format is `mon/dd/yyyy` — additional parsing would be required.
