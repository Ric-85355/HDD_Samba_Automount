#!/bin/bash

# Путь к блочному устройству (можно заменить на UUID при необходимости)
DEVICE="/dev/sdc1"

# Точка монтирования
MOUNT_POINT="/mnt/hotswap"

# Файл-фрагмент конфигурации Samba
SMB_FRAGMENT="/etc/samba/hotswap_auto.conf"

# Пользователь от имени которого будет работать Samba
FORCE_USER="nobody"
FORCE_GROUP="nogroup"

# Лог
LOG_FILE="/var/log/hotswap.log"

echo "----- $(date) START -----" >> "$LOG_FILE"

# Проверка наличия устройства
if [ ! -b "$DEVICE" ]; then
    echo "[hotswap] ❌ Устройство $DEVICE не найдено" >> "$LOG_FILE"
    
    # Очищаем конфигурацию Samba или создаем пустую
    echo "# Hotswap device not found - section disabled" > "$SMB_FRAGMENT"
    echo "[hotswap] 🧹 Конфигурация Samba очищена (устройство не найдено)" >> "$LOG_FILE"
    
    # Размонтируем точку, если она была смонтирована ранее
    if mountpoint -q "$MOUNT_POINT"; then
        umount "$MOUNT_POINT" 2>/dev/null
        echo "[hotswap] 📤 Размонтирован $MOUNT_POINT" >> "$LOG_FILE"
    fi
    
    # Перезагрузка smbd для применения изменений
    systemctl reload smbd
    echo "[hotswap] 🔄 smbd перезагружен (устройство отсутствует)" >> "$LOG_FILE"
    
    exit 0  # Изменил на 0, так как это нормальная ситуация
fi

# Определение типа ФС
FS_TYPE=$(blkid -o value -s TYPE "$DEVICE")
echo "[hotswap] Найдено устройство $DEVICE с файловой системой: $FS_TYPE" >> "$LOG_FILE"

# Создание точки монтирования
mkdir -p "$MOUNT_POINT"

# На всякий случай размонтируем, если уже смонтировано
umount "$MOUNT_POINT" 2>/dev/null

# Монтирование с учётом ФС
if [ "$FS_TYPE" = "ntfs" ]; then
    echo "[hotswap] Попытка монтирования NTFS через ntfs-3g" >> "$LOG_FILE"
    
    # Проверим, доступен ли user_allow_other
    if grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
        FUSE_OPTS="uid=65534,gid=65534,umask=000,allow_other"
    else
        FUSE_OPTS="uid=65534,gid=65534,umask=000"
        echo "[hotswap] ⚠️ user_allow_other не включен в /etc/fuse.conf" >> "$LOG_FILE"
    fi
    
    ntfs-3g -o "$FUSE_OPTS" "$DEVICE" "$MOUNT_POINT" >> "$LOG_FILE" 2>&1
    MOUNT_RESULT=$?
else
    echo "[hotswap] Монтирование Linux ФС ($FS_TYPE)" >> "$LOG_FILE"
    mount -o uid=65534,gid=65534 "$DEVICE" "$MOUNT_POINT" >> "$LOG_FILE" 2>&1
    MOUNT_RESULT=$?
fi

# Проверка результата монтирования
if [ $MOUNT_RESULT -eq 0 ] && mountpoint -q "$MOUNT_POINT"; then
    echo "[hotswap] ✅ Смонтировано успешно в $MOUNT_POINT" >> "$LOG_FILE"
    
    # Проверим содержимое для диагностики
    FILE_COUNT=$(ls -1 "$MOUNT_POINT" 2>/dev/null | wc -l)
    echo "[hotswap] 📁 Найдено файлов/папок: $FILE_COUNT" >> "$LOG_FILE"

    # Запись Samba-конфигурации
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

    echo "[hotswap] ✅ Конфигурация Samba записана в $SMB_FRAGMENT" >> "$LOG_FILE"

    # Перезагрузка smbd
    systemctl reload smbd
    echo "[hotswap] 🔄 smbd перезагружен" >> "$LOG_FILE"
else
    echo "[hotswap] ❌ Ошибка монтирования $DEVICE (код: $MOUNT_RESULT)" >> "$LOG_FILE"
    
    # Очищаем конфигурацию Samba при ошибке монтирования
    echo "# Hotswap device mount failed - section disabled" > "$SMB_FRAGMENT"
    systemctl reload smbd
    echo "[hotswap] 🧹 Конфигурация Samba очищена (ошибка монтирования)" >> "$LOG_FILE"
    
    exit 2
fi
