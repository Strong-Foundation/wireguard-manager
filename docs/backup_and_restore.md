# WireGuard Manager Backup Guide

This guide outlines the process for backing up WireGuard Manager, ensuring that you can transfer the application and its configurations seamlessly between systems.

## Essential Backup Files

For a successful backup, the critical file to include is:

- **Configuration File:** `/etc/wireguard/wg0.conf` contains all the necessary settings for WireGuard Manager to function correctly.

## Backup Storage

The backup is packaged as a compressed ZIP archive, located at:

- **Location:** `/var/backups/wireguard-manager.zip`

You can easily access and transfer this file to facilitate the backup process.

## Secure Password Management

The backup's access password is securely stored in a hidden file within the user's home directory:

- **Password File:** `${HOME}/.wireguard-manager`

This method ensures the password's security, keeping it separate from the backup archive.

## Restoration Process

To restore WireGuard Manager from the backup:

1. Locate the backup archive: `/var/backups/wireguard-manager.zip`
2. Transfer and extract this file to a suitable location on the target system.

Following these steps will restore WireGuard Manager to its previous state, with all configurations intact.