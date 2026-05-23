# =============================================================================
# MikroTik Daily Backup Script — .rsc only
# Exports config and uploads to SFTP only if config has changed.
# Filename format: <router-ip>_YYYY-MM-DD.rsc
#
# Dependencies:
#   - "credentials" script must exist (sets global variables)
#   - "last-config-hash" script is used as persistent storage for the last hash
# =============================================================================

# --- Load credentials ---
/system script run credentials;

# --- Helper: send Telegram notification on error ---
# Usage: $sendTelegram message="..."
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
# Returns true if upload succeeded, false otherwise
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
:local baseName ($routerIp . "_" . $dateStr);
:local exportFile ($baseName . ".rsc");

:log info message=("Daily backup starting for: " . $baseName);

# =============================================================================
# STEP 1 - Check free disk space (minimum 2MB)
# =============================================================================

:local freeSpace [/system resource get free-hdd-space];
:if ($freeSpace < 2097152) do={
  :local msg ("[\U0001F534 Backup ERROR] " . $routerIp . " - Not enough disk space. Free: " . $freeSpace . " bytes.");
  :log error message=$msg;
  $sendTelegram $msg;
  :error "not-enough-space";
};

# =============================================================================
# STEP 2 - Export config and compare with last known hash
# =============================================================================

/export compact file=$baseName;
:delay 5s;

# Validate export file was created
:if ([:len [/file find name=$exportFile]] = 0) do={
  :local msg ("[\U0001F534 Backup ERROR] " . $routerIp . " - Export file not found after /export: " . $exportFile);
  :log error message=$msg;
  $sendTelegram $msg;
  :error "export-file-missing";
};

:local currentConfig [/file get $exportFile contents];

# Read last saved hash
:local lastHash "";
:do {
  :set lastHash [/system script get "last-config-hash" source];
} on-error={
  :log info message="No previous hash found. Creating last-config-hash script.";
  /system script add name="last-config-hash" source="" comment="DO NOT EDIT - used by daily-backup to track config changes";
};

:if ($currentConfig = $lastHash) do={
  :log info message="No config changes detected. Daily backup skipped.";
  /file remove $exportFile;
  :error "no-changes";
};

:log info message="Config change detected. Proceeding with daily backup.";

# =============================================================================
# STEP 3 - Upload .rsc to SFTP with retry
# =============================================================================

:log info message=("Uploading: " . $exportFile);
:local uploadOk [$uploadWithRetry $exportFile $ftphost $ftpuser $ftppassword ($ftppath . $exportFile)];

# =============================================================================
# STEP 4 - Save hash and clean up (only if upload succeeded)
# =============================================================================

:if ($uploadOk) do={
  /system script set "last-config-hash" source=$currentConfig;
  /file remove $exportFile;
  :log info message=("Daily backup complete: " . $exportFile . " - local file removed.");
} else={
  :local msg ("[\U0001F534 Backup ERROR] " . $routerIp . " - Failed to upload after 3 attempts: " . $exportFile);
  :log error message=$msg;
  $sendTelegram $msg;
  :log warning message="Local file preserved for manual recovery.";
};
