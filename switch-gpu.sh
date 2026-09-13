#!/bin/bash

# Файл состояния, чтобы не перезаписывать конфиги вхолостую
STATE_FILE="/tmp/gpu_power_state"

# Проверка питания от сети
is_plugged() {
    for p in /sys/class/power_supply/AC*/online /sys/class/power_supply/ADP*/online; do
        if [ -f "$p" ] && [ "$(cat "$p")" -eq 1 ]; then
            return 0
        fi
    done
    return 1
}

# Динамический поиск активного пользователя графической сессии (Wayland / X11)
TARGET_USER=$(loginctl list-sessions 2>/dev/null | awk '{print $3}' | grep -v -E 'root|USER|^$' | head -n 1)
[ -z "$TARGET_USER" ] && TARGET_USER=$(who | awk '$2 ~ /:[0-9]/ {print $1}' | head -n 1)

# Функция отправки уведомления
send_notification() {
    local icon="$1"
    local title="$2"
    local body="$3"

    if [ -n "$TARGET_USER" ]; then
        local user_id
        user_id=$(id -u "$TARGET_USER" 2>/dev/null)
        if [ -n "$user_id" ]; then
            su "$TARGET_USER" -c "DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$user_id/bus notify-send -i '$icon' '$title' '$body'" 2>/dev/null
        fi
    fi
}

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

    # 2. Отправляем уведомление
    send_notification "nvidia" "Режим питания: Сеть" "NVIDIA активирована для новых процессов"

else
    # Проверяем, не включен ли уже режим батареи
    [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "battery" ] && exit 0
    echo "battery" > "$STATE_FILE"

    # 1. Удаляем конфиг при работе от батареи
    rm -f /etc/profile.d/nvidia-offload.sh

    # 2. Отправляем уведомление
    send_notification "battery" "Режим питания: Батарея" "Переход на встройку. Экономия энергии"
fi
