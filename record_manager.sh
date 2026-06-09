#!/bin/bash

set -e

DEVICE_ID=$(cat /VIDEOS/device_info.txt)

BASE=/VIDEOS/recordings

VIDEO_DIR=$BASE/video
IMU_DIR=$BASE/imu
LOCK_DIR=$BASE/locks

mkdir -p "$VIDEO_DIR"
mkdir -p "$IMU_DIR"
mkdir -p "$LOCK_DIR"

SEQUENCE_FILE=/VIDEOS/recordings/record_sequence

if [ ! -f "$SEQUENCE_FILE" ]; then
    echo 0 > "$SEQUENCE_FILE"
fi

VIDEO_PID=""
IMU_PID=""
VIDEO_LOCK=""
IMU_LOCK=""

cleanup() {

    echo "Stopping recorder..."

    if [ -n "$VIDEO_PID" ]; then
        kill -SIGINT "$VIDEO_PID" 2>/dev/null || true
        wait "$VIDEO_PID" 2>/dev/null || true
    fi

    if [ -n "$IMU_PID" ]; then
        kill -SIGTERM "$IMU_PID" 2>/dev/null || true
        wait "$IMU_PID" 2>/dev/null || true
    fi

    sync

    [ -n "$VIDEO_LOCK" ] && rm -f "$VIDEO_LOCK"
    [ -n "$IMU_LOCK" ] && rm -f "$IMU_LOCK"

    exit 0
}

trap cleanup SIGTERM SIGINT

while true
do

    if ! mountpoint -q /VIDEOS
    then
        logger "VIDEOS partition not mounted"
        sleep 10
        continue
    fi

    FREE=$(df /VIDEOS --output=avail | tail -1)

    if [ "$FREE" -lt 1048576 ]
    then
        logger "Less than 1GB remaining"
        sleep 60
        continue
    fi

    SEQ=$(cat "$SEQUENCE_FILE")
    SEQ=$((SEQ+1))
    echo "$SEQ" > "$SEQUENCE_FILE"

    TS=$(date +%Y%m%d_%H%M%S)

    NAME="${DEVICE_ID}_${TS}_$(printf "%04d" $SEQ)"

    VIDEO_FILE="$VIDEO_DIR/${NAME}.mp4"
    IMU_FILE="$IMU_DIR/${NAME}.csv"

    VIDEO_LOCK="$LOCK_DIR/${NAME}.video.lock"
    IMU_LOCK="$LOCK_DIR/${NAME}.imu.lock"

    touch "$VIDEO_LOCK"
    touch "$IMU_LOCK"

    /usr/local/bin/imu_recorder.py "$IMU_FILE" &
    IMU_PID=$!

    rpicam-vid \
        -t 1800000 \
        --width 1920 \
        --height 1080 \
        --framerate 30 \
        --codec libav \
        --profile high \
        --level 4.2 \
        --bitrate 8000000 \
        --awb auto \
        --denoise cdn_off \
        --sharpness 1.2 \
        --contrast 1.1 \
        --saturation 1.15 \
        -o "$VIDEO_FILE" &

    VIDEO_PID=$!

    wait "$VIDEO_PID"

    kill -TERM "$IMU_PID" 2>/dev/null || true
    wait "$IMU_PID" 2>/dev/null || true

    sync

    rm -f "$VIDEO_LOCK"
    rm -f "$IMU_LOCK"

    VIDEO_PID=""
    IMU_PID=""
    VIDEO_LOCK=""
    IMU_LOCK=""

done
