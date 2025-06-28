#!/bin/bash
# Path to block device (can be replaced with UUID if needed)
DEVICE="/dev/sdc1"
# Mount point
MOUNT_POINT="/mnt/hotswap"
# Samba configuration fragment file
SMB_FRAGMENT="/etc/samba/hotswap_auto.conf"
# User under which Samba will operate
FORCE_USER="nobody"
FORCE_GROUP="nogroup"
# Log
LOG_FILE="/var/log/hotswap.log"

echo "----- $(date) START -----" >> "$LOG_FILE"

# Check device presence
if [ ! -b "$DEVICE" ]; then
    echo "[hotswap] ❌ Device $DEVICE not found" >> "$LOG_FILE"
    
    # Clear Samba configuration or create empty one
    echo "# Hotswap device not found - section disabled" > "$SMB_FRAGMENT"
    echo "[hotswap] 🧹 Samba configuration cleared (device not found)" >> "$LOG_FILE"
    
    # Unmount the point if it was mounted previously
    if mountpoint -q "$MOUNT_POINT"; then
        umount "$MOUNT_POINT" 2>/dev/null
        echo "[hotswap] 📤 Unmounted $MOUNT_POINT" >> "$LOG_FILE"
    fi
    
    # Reload smbd to apply changes
    systemctl reload smbd
    echo "[hotswap] 🔄 smbd reloaded (device absent)" >> "$LOG_FILE"
    
    exit 0  # Changed to 0 as this is a normal situation
fi

# File system type detection
FS_TYPE=$(blkid -o value -s TYPE "$DEVICE")
echo "[hotswap] Found device $DEVICE with filesystem: $FS_TYPE" >> "$LOG_FILE"

# Create mount point
mkdir -p "$MOUNT_POINT"

# Just in case, unmount if already mounted
umount "$MOUNT_POINT" 2>/dev/null

# Mount considering filesystem type
if [ "$FS_TYPE" = "ntfs" ]; then
    echo "[hotswap] Attempting NTFS mount via ntfs-3g" >> "$LOG_FILE"
    
    # Check if user_allow_other is available
    if grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
        FUSE_OPTS="uid=65534,gid=65534,umask=000,allow_other"
    else
        FUSE_OPTS="uid=65534,gid=65534,umask=000"
        echo "[hotswap] ⚠️ user_allow_other not enabled in /etc/fuse.conf" >> "$LOG_FILE"
    fi
    
    ntfs-3g -o "$FUSE_OPTS" "$DEVICE" "$MOUNT_POINT" >> "$LOG_FILE" 2>&1
    MOUNT_RESULT=$?
else
    echo "[hotswap] Mounting Linux FS ($FS_TYPE)" >> "$LOG_FILE"
    mount -o uid=65534,gid=65534 "$DEVICE" "$MOUNT_POINT" >> "$LOG_FILE" 2>&1
    MOUNT_RESULT=$?
fi

# Check mount result
if [ $MOUNT_RESULT -eq 0 ] && mountpoint -q "$MOUNT_POINT"; then
    echo "[hotswap] ✅ Successfully mounted at $MOUNT_POINT" >> "$LOG_FILE"
    
    # Check contents for diagnostics
    FILE_COUNT=$(ls -1 "$MOUNT_POINT" 2>/dev/null | wc -l)
    echo "[hotswap] 📁 Files/folders found: $FILE_COUNT" >> "$LOG_FILE"

    # Write Samba configuration
    cat > "$SMB_FRAGMENT" <<EOF
[hotswap]
   path = $MOUNT_POINT
   browseable = yes
   read only = no
   guest ok = yes
   force user = $FORCE_USER
   force group = $FORCE_GROUP
   create mask = 0664
   directory mask = 0775
EOF

    echo "[hotswap] ✅ Samba configuration written to $SMB_FRAGMENT" >> "$LOG_FILE"

    # Reload smbd
    systemctl reload smbd
    echo "[hotswap] 🔄 smbd reloaded" >> "$LOG_FILE"
else
    echo "[hotswap] ❌ Mount error for $DEVICE (code: $MOUNT_RESULT)" >> "$LOG_FILE"
    
    # Clear Samba configuration on mount error
    echo "# Hotswap device mount failed - section disabled" > "$SMB_FRAGMENT"
    systemctl reload smbd
    echo "[hotswap] 🧹 Samba configuration cleared (mount error)" >> "$LOG_FILE"
    
    exit 2
fi
