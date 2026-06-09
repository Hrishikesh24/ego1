#!/bin/bash

set -e

echo "=== Updating packages ==="
apt update

echo "=== Installing dependencies ==="
apt install -y python3-smbus 
apt install -y i2c-tools 
apt install -y exfat-fuse 
apt install -y exfatprogs

echo "=== Enabling I2C bus 3 overlay ==="

CONFIG_FILE="/boot/firmware/config.txt"

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
    echo "TRCPI0W000001" > /VIDEOS/device_info.txt
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
echo "======================================="
echo "Setup complete."
echo ""
echo "Before recording verify:"
echo ""
echo "1. /VIDEOS partition is mounted"
echo "2. MPU6050 appears on:"
echo "   i2cdetect -y 3"
echo "3. Camera works:"
echo "   rpicam-hello --list-cameras"
echo ""
echo "Reboot required for I2C bus 3 overlay."
echo "======================================="
