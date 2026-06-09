#!/bin/bash

set -e

CONFIG_FILE="/boot/firmware/config.txt"

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
    else
        echo "WARNING: ${key} not found in $CONFIG_FILE — add ${line} manually if needed"
    fi
}

add_dtoverlay_in_all_section() {
    local overlay="$1"

    if grep -qF "$overlay" "$CONFIG_FILE"; then
        return
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
}

echo "=== Updating packages ==="
apt update

echo "=== Installing dependencies ==="
apt install -y python3-smbus
apt install -y i2c-tools
apt install -y exfat-fuse
apt install -y exfatprogs

echo "=== Installing Arducam Pi variety camera driver ==="
PIVARIETY_SCRIPT="/tmp/install_pivariety_pkgs.sh"
wget -O "$PIVARIETY_SCRIPT" https://github.com/ArduCAM/Arducam-Pivariety-V4L2-Driver/releases/download/install_script/install_pivariety_pkgs.sh
chmod +x "$PIVARIETY_SCRIPT"
"$PIVARIETY_SCRIPT" -p libcamera_dev
"$PIVARIETY_SCRIPT" -p libcamera_apps

echo "=== Configuring camera in $CONFIG_FILE ==="
set_existing_config_value "camera_auto_detect" "0"
add_dtoverlay_in_all_section "dtoverlay=arducam-pivariety"

echo "=== Enabling I2C bus 3 overlay ==="
if ! grep -q "dtoverlay=i2c-gpio,bus=3,i2c_gpio_sda=23,i2c_gpio_scl=24" "$CONFIG_FILE"; then
    echo "" >> "$CONFIG_FILE"
    echo "# MPU6050 software I2C bus" >> "$CONFIG_FILE"
    echo "dtoverlay=i2c-gpio,bus=3,i2c_gpio_sda=23,i2c_gpio_scl=24" >> "$CONFIG_FILE"
fi

echo "=== Creating directories ==="
mkdir -p /VIDEOS
mkdir -p /VIDEOS/recordings/video
mkdir -p /VIDEOS/recordings/imu
mkdir -p /VIDEOS/recordings/locks

if [ ! -f /VIDEOS/device_info.txt ]; then
    DEVICE_ID="${DEVICE_ID:-$(get_device_id)}"
    echo "$DEVICE_ID" > /VIDEOS/device_info.txt
    echo "Device ID set to: $DEVICE_ID"
fi

echo "=== Installing recorder scripts ==="
cp imu_recorder.py /usr/local/bin/imu_recorder.py
cp record_manager.sh /usr/local/bin/record_manager.sh
cp start_recording.sh /usr/local/bin/start_recording.sh
cp stop_recording.sh /usr/local/bin/stop_recording.sh
cp safe_shutdown.sh /usr/local/bin/safe_shutdown.sh

chmod +x /usr/local/bin/imu_recorder.py
chmod +x /usr/local/bin/record_manager.sh
chmod +x /usr/local/bin/start_recording.sh
chmod +x /usr/local/bin/stop_recording.sh
chmod +x /usr/local/bin/safe_shutdown.sh

echo "=== Creating systemd service ==="
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

systemctl daemon-reload

echo "=== Enabling service ==="
systemctl enable record.service

echo ""
echo "=== Installing PiSugar power manager (interactive) ==="
echo "When prompted, select PiSugar 3."
PI_SUGAR_DIR="/tmp/pisugar-install"
mkdir -p "$PI_SUGAR_DIR"
wget -O "$PI_SUGAR_DIR/pisugar-power-manager.sh" https://cdn.pisugar.com/release/pisugar-power-manager.sh
set +e
bash "$PI_SUGAR_DIR/pisugar-power-manager.sh" -c release
PISUGAR_EXIT=$?
set -e
if [ "$PISUGAR_EXIT" -ne 0 ]; then
    echo "WARNING: PiSugar install exited with status $PISUGAR_EXIT — re-run manually (see commands below)"
fi

echo ""
echo "======================================="
echo "Setup complete."
echo ""
echo "sudo reboot"
echo ""
echo "/usr/local/bin/start_recording.sh"
echo "/usr/local/bin/stop_recording.sh"
echo "/usr/local/bin/safe_shutdown.sh"
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
