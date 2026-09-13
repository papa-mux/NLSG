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

# 1. Поиск активного пользователя графической сессии (без loginctl/systemd)
get_target_user() {
    ps aux | grep -E '(Hyprland|sway|Xorg|waybar|i3|xfce4-session|wayland)' | \
    grep -v -E 'root|grep' | awk '{print $1}' | head -n 1
}

# 2. Универсальная отправка уведомлений (работает под SysVinit/OpenRC/systemd)
send_notification() {
    local icon="$1"
    local title="$2"
    local body="$3"

    local user
    user=$(get_target_user)
    [ -z "$user" ] && return 0

    # Находим PID любого процесса текущего пользователя в графике
    local user_pid
    user_pid=$(pgrep -u "$user" -n "Hyprland|waybar|sway|i3|Xorg|dbus-daemon|bash")

    if [ -n "$user_pid" ] && [ -r "/proc/$user_pid/environ" ]; then
        # Вытягиваем переменные окружения прямо из /proc процесса пользователя
        local dbus_addr
        dbus_addr=$(tr '\0' '\n' < "/proc/$user_pid/environ" | grep '^DBUS_SESSION_BUS_ADDRESS=' | cut -d= -f2-)
        local display_val
        display_val=$(tr '\0' '\n' < "/proc/$user_pid/environ" | grep '^DISPLAY=' | cut -d= -f2-)
        local wayland_val
        wayland_val=$(tr '\0' '\n' < "/proc/$user_pid/environ" | grep '^WAYLAND_DISPLAY=' | cut -d= -f2-)

        # Запускаем notify-send от имени пользователя с его переменными окружения
        su "$user" -c "
            export DBUS_SESSION_BUS_ADDRESS='${dbus_addr:-unix:path=/run/user/$(id -u "$user")/bus}'
            export DISPLAY='${display_val:-:0}'
            export WAYLAND_DISPLAY='${wayland_val:-wayland-0}'
            notify-send -i '$icon' '$title' '$body'
        " 2>/dev/null
    fi
}

if is_plugged; then
    # Проверяем, не включен ли уже режим сети
    [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "ac" ] && exit 0
    echo "ac" > "$STATE_FILE"

    # Создаем конфиг переключения на NVIDIA
    cat << 'EOF' > /etc/profile.d/nvidia-offload.sh
export __NV_PRIME_RENDER_OFFLOAD=1
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
export DRI_PRIME=1
EOF
    chmod 644 /etc/profile.d/nvidia-offload.sh

    send_notification "nvidia" "Режим питания: Сеть" "NVIDIA активирована для новых процессов"

else
    # Проверяем, не включен ли уже режим батареи
    [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "battery" ] && exit 0
    echo "battery" > "$STATE_FILE"

    # Удаляем конфиг при работе от батареи
    rm -f /etc/profile.d/nvidia-offload.sh

    send_notification "battery" "Режим питания: Батарея" "Переход на встройку. Экономия энергии"
fi
