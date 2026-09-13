#!/bin/bash

# Файл состояния, чтобы не перезаписывать конфиги вхолостую
STATE_FILE="/tmp/gpu_power_state"

# Пути к проверке питания
is_plugged() {
    for p in /sys/class/power_supply/AC*/online /sys/class/power_supply/ADP*/online; do
        if [ -f "$p" ] && [ "$(cat "$p")" -eq 1 ]; then
            return 0
        fi
    done
    return 1
}

# Получаем текущего активного пользователя X11 (для динамического уведомления)
TARGET_USER=$(who | grep -E '\(:0|\:0.0\)' | awk '{print $1}' | head -n 1)
[ -z "$TARGET_USER" ] && TARGET_USER="papafly"

if is_plugged; then
    # Проверяем, не включен ли уже режим сети
    [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "ac" ] && exit 0
    echo "ac" > "$STATE_FILE"

    # 1. Задаем переменные для новых сессий
    cat << 'EOF' > /etc/profile.d/nvidia-offload.sh
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export DRI_PRIME=1
EOF
    chmod 644 /etc/profile.d/nvidia-offload.sh

    # 2. Отправляем уведомление на рабочий стол
    su "$TARGET_USER" -c "DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $TARGET_USER)/bus notify-send -i nvidia 'Режим питания: Сеть' 'NVIDIA активирована для новых процессов'" 2>/dev/null

else
    # Проверяем, не включен ли уже режим батареи
    [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "battery" ] && exit 0
    echo "battery" > "$STATE_FILE"

    # 1. Удаляем конфиг при работе от батареи
    rm -f /etc/profile.d/nvidia-offload.sh

    # 2. Отправляем уведомление
    su "$TARGET_USER" -c "DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u $TARGET_USER)/bus notify-send -i battery 'Режим питания: Батарея' 'Переход на встройку. Экономия энергии'" 2>/dev/null
fi
