#!/bin/bash

CONFIG_FILE="/boot/firmware/config.txt"
CHECKLIST=()

check_pass() {
    CHECKLIST+=("[OK]   $1")
}

check_fail() {
    CHECKLIST+=("[FAIL] $1")
}

run_step() {
    local label="$1"
    shift

    echo ""
    echo "=== $label ==="
    if "$@"; then
        check_pass "$label"
        return 0
    else
        check_fail "$label"
        return 1
    fi
}

get_device_id() {
    local serial
    serial=$(awk '/Serial/ {print $3}' /proc/cpuinfo 2>/dev/null)
    if [ -z "$serial" ]; then
        serial=$(tr -d '\0' < /sys/firmware/devicetree/base/serial-number 2>/dev/null || true)
    fi
    if [ -n "$serial" ]; then
        echo "TRCPI0W$(echo "${serial: -6}" | tr '[:lower:]' '[:upper:]')"
    else
        echo "TRCPI0WUNKNOWN"
    fi
}

set_existing_config_value() {
    local key="$1"
    local value="$2"
    local line="${key}=${value}"

    if grep -q "^${key}=" "$CONFIG_FILE"; then
        sed -i "s/^${key}=.*/${line}/" "$CONFIG_FILE"
        echo "Updated existing ${line} in $CONFIG_FILE"
        return 0
    fi

    echo "WARNING: ${key} not found in $CONFIG_FILE — add ${line} manually if needed"
    return 1
}

add_dtoverlay_in_all_section() {
    local overlay="$1"

    if grep -qF "$overlay" "$CONFIG_FILE"; then
        return 0
    fi

    if grep -q '^\[all\]' "$CONFIG_FILE"; then
        sed -i "/^\[all\]/a ${overlay}" "$CONFIG_FILE"
    else
        {
            echo ""
            echo "[all]"
            echo "$overlay"
        } >> "$CONFIG_FILE"
    fi

    grep -qF "$overlay" "$CONFIG_FILE"
}

install_dependencies() {
    apt install -y python3-smbus &&
    apt install -y i2c-tools &&
    apt install -y exfat-fuse &&
    apt install -y exfatprogs
}

install_arducam_libcamera_dev() {
    local script="/tmp/install_pivariety_pkgs.sh"
    wget -O "$script" https://github.com/ArduCAM/Arducam-Pivariety-V4L2-Driver/releases/download/install_script/install_pivariety_pkgs.sh &&
    chmod +x "$script" &&
    "$script" -p libcamera_dev
}

install_arducam_libcamera_apps() {
    local script="/tmp/install_pivariety_pkgs.sh"
    [ -x "$script" ] || {
        wget -O "$script" https://github.com/ArduCAM/Arducam-Pivariety-V4L2-Driver/releases/download/install_script/install_pivariety_pkgs.sh &&
        chmod +x "$script"
    }
    "$script" -p libcamera_apps
}

enable_i2c_bus3_overlay() {
    local overlay="dtoverlay=i2c-gpio,bus=3,i2c_gpio_sda=23,i2c_gpio_scl=24"

    if ! grep -qF "$overlay" "$CONFIG_FILE"; then
        {
            echo ""
            echo "# MPU6050 software I2C bus"
            echo "$overlay"
        } >> "$CONFIG_FILE"
    fi

    grep -qF "$overlay" "$CONFIG_FILE"
}

create_video_directories() {
    mkdir -p /VIDEOS/recordings/video &&
    mkdir -p /VIDEOS/recordings/imu &&
    mkdir -p /VIDEOS/recordings/locks &&
    [ -d /VIDEOS/recordings/video ] &&
    [ -d /VIDEOS/recordings/imu ] &&
    [ -d /VIDEOS/recordings/locks ]
}

setup_device_id() {
    if [ -f /VIDEOS/device_info.txt ] && [ -s /VIDEOS/device_info.txt ]; then
        echo "Device ID already set: $(cat /VIDEOS/device_info.txt)"
        return 0
    fi

    local device_id="${DEVICE_ID:-$(get_device_id)}"
    echo "$device_id" > /VIDEOS/device_info.txt
    echo "Device ID set to: $device_id"
    [ -s /VIDEOS/device_info.txt ]
}

install_recorder_scripts() {
    cp imu_recorder.py /usr/local/bin/imu_recorder.py &&
    cp record_manager.sh /usr/local/bin/record_manager.sh &&
    cp start_recording.sh /usr/local/bin/start_recording.sh &&
    cp stop_recording.sh /usr/local/bin/stop_recording.sh &&
    cp safe_shutdown.sh /usr/local/bin/safe_shutdown.sh &&
    chmod +x /usr/local/bin/imu_recorder.py &&
    chmod +x /usr/local/bin/record_manager.sh &&
    chmod +x /usr/local/bin/start_recording.sh &&
    chmod +x /usr/local/bin/stop_recording.sh &&
    chmod +x /usr/local/bin/safe_shutdown.sh &&
    [ -x /usr/local/bin/record_manager.sh ]
}

create_record_service() {
    cat >/etc/systemd/system/record.service <<'EOF'
[Unit]
Description=Video and IMU Recorder
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/record_manager.sh

KillSignal=SIGINT
TimeoutStopSec=30

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload &&
    [ -f /etc/systemd/system/record.service ]
}

enable_record_service() {
    systemctl enable record.service &&
    systemctl is-enabled --quiet record.service
}

install_pisugar() {
    local dir="/tmp/pisugar-install"
    mkdir -p "$dir" &&
    wget -O "$dir/pisugar-power-manager.sh" https://cdn.pisugar.com/release/pisugar-power-manager.sh &&
    bash "$dir/pisugar-power-manager.sh" -c release
}

print_checklist() {
    echo ""
    echo "Setup checklist:"
    for item in "${CHECKLIST[@]}"; do
        echo "$item"
    done
}

run_step "Update packages" apt update
run_step "Install dependencies" install_dependencies
run_step "Arducam libcamera_dev" install_arducam_libcamera_dev
run_step "Arducam libcamera_apps" install_arducam_libcamera_apps
run_step "Set camera_auto_detect=0" set_existing_config_value "camera_auto_detect" "0"
run_step "Add dtoverlay=arducam-pivariety" add_dtoverlay_in_all_section "dtoverlay=arducam-pivariety"
run_step "Enable I2C bus 3 overlay" enable_i2c_bus3_overlay
run_step "Create /VIDEOS directories" create_video_directories
run_step "Set device ID" setup_device_id
run_step "Install recorder scripts" install_recorder_scripts
run_step "Create record.service" create_record_service
run_step "Enable record.service" enable_record_service

echo ""
echo "=== Installing PiSugar power manager (interactive) ==="
echo "When prompted, select PiSugar 3."
if install_pisugar; then
    check_pass "PiSugar power manager"
else
    check_fail "PiSugar power manager"
fi

echo ""
echo "======================================="
echo "Setup complete."
print_checklist
echo ""
echo "sudo reboot"
echo ""
echo "sudo /usr/local/bin/start_recording.sh"
echo "sudo /usr/local/bin/stop_recording.sh"
echo "sudo /usr/local/bin/safe_shutdown.sh"
echo ""
echo "sudo systemctl start record.service"
echo "sudo systemctl stop record.service"
echo "sudo systemctl status record.service"
echo ""
echo "i2cdetect -y 3"
echo "rpicam-hello --list-cameras"
echo ""
echo "wget -O /tmp/pisugar-power-manager.sh https://cdn.pisugar.com/release/pisugar-power-manager.sh"
echo "bash /tmp/pisugar-power-manager.sh -c release"
echo "======================================="
