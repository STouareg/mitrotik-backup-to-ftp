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

# --- Build filenames ---
:local dateStr [/system clock get date];
:local baseName ($routerIp . "_" . $dateStr);
:local exportFile ($baseName . ".rsc");

:log info message=("Daily backup starting for: " . $baseName);

# =============================================================================
# STEP 1 - Check free disk space (minimum 2MB)
# =============================================================================

:local freeSpace [/system resource get free-hdd-space];
:if ($freeSpace < 524288) do={
  :local msg ("[Backup ERROR] " . $routerIp . " - Not enough disk space. Free: " . $freeSpace . " bytes.");
  :log error message=$msg;
  :do {
    /tool fetch url=("https://api.telegram.org/bot" . $tgtoken . "/sendMessage") \
      http-method=post http-data=("chat_id=" . $tgchatid . "&text=" . $msg) output=none;
  } on-error={ :log warning message="Failed to send Telegram notification."; };
  :error "not-enough-space";
};

# =============================================================================
# STEP 2 - Export config and compare with last known hash
# =============================================================================

/export compact file=$baseName;
:delay 5s;

# Validate export file was created
:if ([:len [/file find name=$exportFile]] = 0) do={
  :local msg ("[Backup ERROR] " . $routerIp . " - Export file not found after /export: " . $exportFile);
  :log error message=$msg;
  :do {
    /tool fetch url=("https://api.telegram.org/bot" . $tgtoken . "/sendMessage") \
      http-method=post http-data=("chat_id=" . $tgchatid . "&text=" . $msg) output=none;
  } on-error={ :log warning message="Failed to send Telegram notification."; };
  :error "export-file-missing";
};

# Strip the first line (contains timestamp) before comparing
:local rawConfig [/file get $exportFile contents];
:local currentConfig [:pick $rawConfig ([:find $rawConfig "\n"] + 1) [:len $rawConfig]];

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
# STEP 3 - Upload .rsc to SFTP with retry (3 attempts, 60s delay)
# =============================================================================

:log info message=("Uploading: " . $exportFile);
:local uploadOk false;
:local attempt 1;
:while ($attempt <= 3) do={
  :do {
    /tool fetch \
      address=$ftphost \
      src-path=$exportFile \
      user=$ftpuser \
      mode=sftp \
      password=$ftppassword \
      dst-path=($ftppath . $exportFile) \
      upload=yes;
    :set uploadOk true;
    :set attempt 4;
  } on-error={
    :log warning message=("Upload attempt " . $attempt . "/3 failed for: " . $exportFile);
    :if ($attempt < 3) do={ :delay 60s; };
    :set attempt ($attempt + 1);
  };
};

# =============================================================================
# STEP 4 - Save hash and clean up (only if upload succeeded)
# =============================================================================

:if ($uploadOk) do={
  /system script set "last-config-hash" source=$currentConfig;
  /file remove $exportFile;
  :log info message=("Daily backup complete: " . $exportFile . " - local file removed.");
} else={
  :local msg ("[Backup ERROR] " . $routerIp . " - Failed to upload after 3 attempts: " . $exportFile);
  :log error message=$msg;
  :do {
    /tool fetch url=("https://api.telegram.org/bot" . $tgtoken . "/sendMessage") \
      http-method=post http-data=("chat_id=" . $tgchatid . "&text=" . $msg) output=none;
  } on-error={ :log warning message="Failed to send Telegram notification."; };
  :log warning message="Local file preserved for manual recovery.";
};
