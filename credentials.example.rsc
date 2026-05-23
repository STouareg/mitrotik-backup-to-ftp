# =============================================================================
# MikroTik Backup - Credentials Script
# =============================================================================
# INSTRUCTIONS:
#   1. Copy this file and add it to RouterOS scripts with the name "credentials".
#   2. Fill in your actual values below.
#   3. Add the script via Winbox: System -> Scripts -> Add, or via terminal:
#      /system script add name="credentials" source=[/file get credentials.rsc contents]
#   4. Restrict access: ensure only admin users can view and edit scripts.
#
# SECURITY NOTE:
#   RouterOS has no built-in secrets manager. To protect these values:
#   - Limit Winbox/SSH access to trusted admin accounts only.
#   - Do NOT export this script externally or include it in shared backups.
#   - Consider placing the FTP server on an isolated management VLAN.
# =============================================================================

# FTP server IP or hostname
:global ftphost "0.0.0.0";

# FTP username
:global ftpuser "your_ftp_username";

# FTP password
:global ftppassword "your_ftp_password";

# Destination path on FTP server (must end with /)
:global ftppath "/Backups/Mikrotik_backups/";
