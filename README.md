# HDD_Samba_Automount
Automatic mounting of archive HDD in slot and connecting it to Samba

The server has a slot for quick HDD installation (drive tray).
The idea is to make the server check on startup if there's an HDD in the tray and, if there is, automatically mount it and share it via Samba.
The solution includes several components.

### 1. Directory where it mounts
```
   sudo mkdir /mnt/hotswap
   sudo chown -R nobody:nogroup /mnt/hotswap
   sudo chmod 777 /mnt/hotswap
```

### 2. Main script 
Place in `/usr/local/bin/`, using the name `check-hotswap.sh` (see files)  
Check that the DEVICE variable at the beginning of the script points to the next drive in /dev/sdX1

### 3. Add `include` to `/etc/samba/smb.conf`
   ```include = /etc/samba/hotswap_auto.conf```  
Connecting dynamically generated configuration when disk is present (see below)

### 4. Check for ntfs-3g availability
`sudo apt install ntfs-3g`

### 5. Dynamically generated configuration when disk is present
Creates a simple empty file, it gets filled by the main script
   ```
   sudo touch /etc/samba/hotswap_auto.conf
   sudo chmod 644 /etc/samba/hotswap_auto.conf
```

### 6. Creating systemd service
Location and filename `/etc/systemd/system/hotswap-check.service`
See files for content.
After creating the service file, restart the systemd daemon:
```
sudo systemctl daemon-reload
sudo systemctl enable hotswap-check.service
```

### 7. Check allow_all option
Check that the `user_allow_other` option is uncommented in `/etc/fuse.conf`   

## Result
If everything is done correctly - after starting the server with a disk inserted in the tray, it should mount and be available via Samba in the hotswap resource
