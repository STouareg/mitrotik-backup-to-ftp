# =============================================================================
# MikroTik Smart Backup Script
# Uploads .backup and .rsc files to SFTP only if config has changed.
# Filename format: <router-ip>_YYYY-MM-DD_<ros-version>.backup
#                 <router-ip>_YYYY-MM-DD.rsc
# =============================================================================
# Dependencies:
#   - "credentials" script must exist and be run first (sets global variables)
#   - "last-config-hash" script is used as persistent storage for the last hash
# =============================================================================

# --- Load credentials from separate script ---
/system script run credentials;

# --- Build date string: YYYY-MM-DD ---
# RouterOS 7.x already returns the date in YYYY-MM-DD format
:local dateStr [/system clock get date];

# --- Get RouterOS version (e.g. "7.22.2") ---
:local rosVer [:pick [/system resource get version] 0 [:find [/system resource get version] " "]];

# --- Build filenames ---
# $routerIp is set in the credentials script
:local baseName ($routerIp . "_" . $dateStr);
:local backupFile ($baseName . "_" . $rosVer . ".backup");
:local exportFile ($baseName . ".rsc");

:log info message=("Smart backup starting for: " . $baseName);

# =============================================================================
# STEP 1 - Export current config and compare with last known hash
# =============================================================================

/export compact file=$baseName;
:delay 5s;

:local currentConfig [/file get ($baseName . ".rsc") contents];

# Read last saved hash (stored as the source of a helper script)
:local lastHash "";
:do {
  :set lastHash [/system script get "last-config-hash" source];
} on-error={
  # Script does not exist yet - first run
  :log info message="No previous hash found. Creating last-config-hash script.";
  /system script add name="last-config-hash" source="" comment="DO NOT EDIT - used by smart-backup to track config changes";
};

:if ($currentConfig = $lastHash) do={
  :log info message="No config changes detected. Backup skipped.";
  # Clean up the export file created for comparison
  /file remove ($baseName . ".rsc");
  :error "no-changes";
};

:log info message="Config change detected. Proceeding with backup.";

# =============================================================================
# STEP 2 - Save full binary backup
# =============================================================================

/system backup save name=$baseName;
:delay 5s;

# =============================================================================
# STEP 3 - Upload both files to FTP
# =============================================================================

:local uploadOk true;

# Upload .backup
:log info message=("Uploading: " . $backupFile);
:do {
  /tool fetch \
    address=$ftphost \
    src-path=$backupFile \
    user=$ftpuser \
    mode=sftp \
    password=$ftppassword \
    dst-path=($ftppath . $backupFile) \
    upload=yes;
  :delay 3s;
} on-error={
  :log error message=("Failed to upload: " . $backupFile);
  :set uploadOk false;
};

# Upload .rsc
:log info message=("Uploading: " . $exportFile);
:do {
  /tool fetch \
    address=$ftphost \
    src-path=$exportFile \
    user=$ftpuser \
    mode=sftp \
    password=$ftppassword \
    dst-path=($ftppath . $exportFile) \
    upload=yes;
  :delay 3s;
} on-error={
  :log error message=("Failed to upload: " . $exportFile);
  :set uploadOk false;
};

# =============================================================================
# STEP 4 - Save hash and clean up local files (only if upload succeeded)
# =============================================================================

:if ($uploadOk) do={
  # Save current config as new hash
  /system script set "last-config-hash" source=$currentConfig;

  # Remove local backup and export files
  :foreach i in=[/file find] do={
    :if ([:typeof [:find [/file get $i name] $baseName]] != "nil") do={
      /file remove $i;
    };
  };

  :log info message=("Backup complete: " . $baseName . " - local files removed.");
} else={
  :log error message="One or more uploads failed. Local files preserved for retry.";
};
