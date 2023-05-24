# Proxmox-Backup-Script


In older version of Proxmox VE doesn't have to `vzdump` work correctly.

My experience with v6.1.8 is failed backup because of -maxfiles parameter.

This script remove older backups and start backup by vzdump.

For more information how to work with this script you can use `proxmox-backup.sh help`.



# HOW TO USE PROXMOX-BACKUP #


proxmox-backup.sh <vmid> <max_backups> <storage> <compress_format> <email>

<vmid>: ID of virtual machine or container
<max_backups>: number of backups kept, older backups will be deleted 
<storage>: name of storage
<compress_format>: type of compression lzo/gz/zstd - optional (default=lzo)
<email>: email for notification - optional

Example: `proxmox-backup.sh 101 5 My-backup-storage zstd my.email@my-domain.com`
