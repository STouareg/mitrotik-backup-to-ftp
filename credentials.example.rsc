# =============================================================================
# MikroTik Backup — Credentials Template
# Copy this file, fill in real values, and add to RouterOS as a script
# named "credentials". DO NOT commit the filled version to git.
#
# /system script add name="credentials" source=[/file get credentials.rsc contents]
# =============================================================================

# Router's own IP (used in backup filenames)
:global routerIp "10.11.97.1";

# SFTP server
:global ftphost "10.11.97.3";
:global ftpuser "mikrotik_backup";
:global ftppassword "yourpassword";

# Remote path for this router's backups (must already exist on the server)
:global ftppath "/Backups/Mikrotik/10.11.97.1/";

# Telegram notifications (errors only)
# How to get these:
#   tgtoken  — create a bot via @BotFather, copy the token
#   tgchatid — send a message to your bot, then open:
#              https://api.telegram.org/bot<tgtoken>/getUpdates
#              and copy the "id" field from "chat"
:global tgtoken "123456789:AABBCCDDEEFFaabbccddeeff-1234567890";
:global tgchatid "987654321";
