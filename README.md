# MikroTik Smart Backup via SFTP

Automated MikroTik configuration backup to an SFTP server with **change detection** — a daily `.rsc` backup is performed only when the configuration has actually changed. Weekly `.backup` runs unconditionally.

## What the scripts do

### `daily-backup.rsc` (runs every night)
- Checks free disk space before starting (minimum 512 KB).
- Exports the current config and compares it with the previously saved state.
- If changes are detected — uploads the `.rsc` file to SFTP.
- If no changes — skips the upload silently.
- Deletes the local file **only after a successful upload**.
- Retries failed uploads up to **3 times** with a **60-second delay** between attempts.
- Sends a **Telegram notification** on any error.

### `weekly-backup.rsc` (runs once a week)
- Checks free disk space before starting (minimum 300 KB).
- Creates a full binary `.backup` file unconditionally.
- Uploads it to SFTP.
- Retries failed uploads up to **3 times** with a **60-second delay** between attempts.
- Sends a **Telegram notification** on any error.
- Deletes the local file **only after a successful upload**.

### Filename format

```
<router-ip>_YYYY-MM-DD.rsc                        ← daily
<router-ip>_YYYY-MM-DD_<ros-version>.backup        ← weekly
```

Example:
```
192.168.88.1_2026-05-23.rsc
192.168.88.1_2026-05-23_7.22.2.backup
```

---

## Repository structure

```
├── daily-backup.rsc            # Daily script — .rsc export with change detection
├── weekly-backup.rsc           # Weekly script — full binary .backup
├── credentials.example.rsc     # Credentials template (no real values)
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
    :global routerIp "192.168.88.1";
    :global ftphost "192.168.88.3";
    :global ftpuser "mikrotik_backup";
    :global ftppassword "yourpassword";
    :global ftppath "/Backups/Mikrotik/192.168.88.1/";
    :global tgtoken "123456789:AABBCCDDEEFFaabbccddeeff-1234567890";
    :global tgchatid "987654321";
  }
```

> The remote directory (`ftppath`) must already exist on the SFTP server — the script will not create it automatically.

> Variables are named `ftp*` for historical reasons but the script uses **SFTP** (`mode=sftp`).

#### How to get Telegram credentials
1. **`tgtoken`** — create a bot via [@BotFather](https://t.me/BotFather) and copy the token.
2. **`tgchatid`** — send any message to your bot, then open:
   `https://api.telegram.org/bot<tgtoken>/getUpdates`
   and copy the `id` field from the `chat` object.

### 2. Add the config hash tracking script

Used by `daily-backup.rsc` to detect configuration changes between runs:

```routeros
/system script add \
  name="last-config-hash" \
  source="" \
  comment="DO NOT EDIT - used by daily-backup"
```

> This script will be created automatically on the first run if it does not exist. Creating it manually beforehand is recommended.

### 3. Add the main backup scripts

```routeros
/system script add name="daily-backup"  source=[/file get daily-backup.rsc contents]
/system script add name="weekly-backup" source=[/file get weekly-backup.rsc contents]
```

Or paste the contents manually via Winbox: **System → Scripts → Add**.

### 4. Schedule the scripts

```routeros
/system scheduler add \
  name="daily-backup" \
  start-time=03:00:00 \
  interval=1d \
  on-event="/system script run daily-backup" \
  comment="Daily .rsc backup to SFTP"

/system scheduler add \
  name="weekly-backup" \
  start-time=02:00:00 \
  interval=7d \
  on-event="/system script run weekly-backup" \
  comment="Weekly .backup to SFTP"
```

> Set the weekly scheduler's `start-date` to the desired weekday if needed.

---

## Verification

Run scripts manually:

```routeros
/system script run daily-backup
/system script run weekly-backup
```

View the logs:

```routeros
/log print where topics~"info|error"
```

Expected log messages:

| Situation | Log message |
|---|---|
| Changes detected, backup running | `Config change detected. Proceeding with daily backup.` |
| No changes | `No config changes detected. Daily backup skipped.` |
| Upload retry | `Upload attempt 2/3 failed for: <filename>` |
| Upload failed after all retries | `Failed to upload after 3 attempts: <filename>` |
| Not enough disk space | `Not enough disk space. Free: <N> bytes.` |

> Default thresholds are 512 KB (daily) and 300 KB (weekly) — tuned for routers with small flash storage (e.g. hAP ac²). Adjust if your router has more space available.
| File missing after save | `Backup file not found after /system backup save: <filename>` |
| Completed successfully | `Daily backup complete: <filename> - local file removed.` |
| Completed successfully | `Weekly backup complete: <filename> - local file removed.` |

---

## Security

RouterOS has no built-in secrets manager. Recommended practices:

- **Separate `credentials` script** — passwords and tokens in one place, isolated from the main logic.
- **Restrict access** — SSH/Winbox only for admin accounts, ideally from specific IPs.
- **Isolated network** — place the SFTP server on a dedicated management VLAN if possible.
- **Never commit `credentials.rsc`** — only `credentials.example.rsc` belongs in the repository (enforced via `.gitignore`).

---

## Compatibility

Tested on RouterOS **7.x**.  
RouterOS 7.x returns the date already in `YYYY-MM-DD` format. On RouterOS **6.x** the date format is `mon/dd/yyyy` — additional parsing would be required.
