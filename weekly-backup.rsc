# =============================================================================
# MikroTik Weekly Backup Script — .backup only (binary)
# Creates a full binary backup and uploads to SFTP unconditionally.
# Filename format: <router-ip>_YYYY-MM-DD_<ros-version>.backup
#
# Dependencies:
#   - "credentials" script must exist (sets global variables)
# =============================================================================

# --- Load credentials ---
/system script run credentials;

# --- Helper: send Telegram notification on error ---
:local sendTelegram do={
  :do {
    /tool fetch \
      url=("https://api.telegram.org/bot" . $tgtoken . "/sendMessage") \
      http-method=post \
      http-data=("chat_id=" . $tgchatid . "&text=" . $1) \
      output=none;
  } on-error={
    :log warning message="Failed to send Telegram notification.";
  };
}

# --- Helper: upload with retry (3 attempts, 60s delay) ---
:local uploadWithRetry do={
  :local attempts 3;
  :local success false;
  :local attempt 1;
  :while ($attempt <= $attempts) do={
    :do {
      /tool fetch \
        address=$2 \
        src-path=$1 \
        user=$3 \
        mode=sftp \
        password=$4 \
        dst-path=$5 \
        upload=yes;
      :set success true;
      :set attempt ($attempts + 1);
    } on-error={
      :log warning message=("Upload attempt " . $attempt . "/" . $attempts . " failed for: " . $1);
      :if ($attempt < $attempts) do={
        :delay 60s;
      };
      :set attempt ($attempt + 1);
    };
  };
  :return $success;
}

# --- Build filenames ---
:local dateStr [/system clock get date];
:local rosVer [:pick [/system resource get version] 0 [:find [/system resource get version] " "]];
:local baseName ($routerIp . "_" . $dateStr);
:local backupFile ($baseName . "_" . $rosVer . ".backup");

:log info message=("Weekly backup starting for: " . $baseName);

# =============================================================================
# STEP 1 - Check free disk space (minimum 10MB for binary backup)
# =============================================================================

:local freeSpace [/system resource get free-hdd-space];
:if ($freeSpace < 10485760) do={
  :local msg ("[\U0001F534 Backup ERROR] " . $routerIp . " - Not enough disk space. Free: " . $freeSpace . " bytes.");
  :log error message=$msg;
  $sendTelegram $msg;
  :error "not-enough-space";
};

# =============================================================================
# STEP 2 - Save full binary backup
# =============================================================================

/system backup save name=$backupFile;
:delay 10s;

# Validate backup file was created
:if ([:len [/file find name=$backupFile]] = 0) do={
  :local msg ("[\U0001F534 Backup ERROR] " . $routerIp . " - Backup file not found after /system backup save: " . $backupFile);
  :log error message=$msg;
  $sendTelegram $msg;
  :error "backup-file-missing";
};

:log info message=("Backup file created: " . $backupFile);

# =============================================================================
# STEP 3 - Upload .backup to SFTP with retry
# =============================================================================

:log info message=("Uploading: " . $backupFile);
:local uploadOk [$uploadWithRetry $backupFile $ftphost $ftpuser $ftppassword ($ftppath . $backupFile)];

# =============================================================================
# STEP 4 - Clean up local file (only if upload succeeded)
# =============================================================================

:if ($uploadOk) do={
  /file remove $backupFile;
  :log info message=("Weekly backup complete: " . $backupFile . " - local file removed.");
} else={
  :local msg ("[\U0001F534 Backup ERROR] " . $routerIp . " - Failed to upload after 3 attempts: " . $backupFile);
  :log error message=$msg;
  $sendTelegram $msg;
  :log warning message="Local file preserved for manual recovery.";
};
