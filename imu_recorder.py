#!/usr/bin/env python3

import csv
import socket
import time
import signal
import smbus
import sys

PISUGAR_SOCK = "/tmp/pisugar-server.sock"
BATTERY_READ_INTERVAL = 1.0

bus = smbus.SMBus(3)
ADDR = 0x68

bus.write_byte_data(ADDR, 0x6B, 0)

running = True

def stop(sig, frame):
    global running
    running = False

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

outfile = sys.argv[1]

def read_word(reg):
    h = bus.read_byte_data(ADDR, reg)
    l = bus.read_byte_data(ADDR, reg + 1)
    value = (h << 8) + l
    if value >= 0x8000:
        value -= 65536
    return value

def read_battery_pct():
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.5)
            sock.connect(PISUGAR_SOCK)
            sock.sendall(b"get battery\n")
            response = sock.recv(64).decode().strip()
    except OSError:
        return None

    if not response:
        return None

    if ":" in response:
        response = response.split(":", 1)[1].strip()

    try:
        return float(response)
    except ValueError:
        return None

with open(outfile, "w", newline="") as f:
    writer = csv.writer(f)

    writer.writerow([
        "unix_time",
        "ax", "ay", "az",
        "gx", "gy", "gz",
        "battery_pct",
    ])

    battery_pct = ""
    last_battery_read = 0.0

    while running:
        ts = time.time()

        if ts - last_battery_read >= BATTERY_READ_INTERVAL:
            level = read_battery_pct()
            if level is not None:
                battery_pct = level
            last_battery_read = ts

        ax = read_word(0x3B)
        ay = read_word(0x3D)
        az = read_word(0x3F)

        gx = read_word(0x43)
        gy = read_word(0x45)
        gz = read_word(0x47)

        writer.writerow([
            ts,
            ax, ay, az,
            gx, gy, gz,
            battery_pct,
        ])

        f.flush()

        time.sleep(0.02)
