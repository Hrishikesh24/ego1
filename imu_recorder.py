#!/usr/bin/env python3

import csv
import time
import signal
import smbus
import sys

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

with open(outfile, "w", newline="") as f:
    writer = csv.writer(f)

    writer.writerow([
        "unix_time",
        "ax","ay","az",
        "gx","gy","gz"
    ])

    while running:

        ts = time.time()

        ax = read_word(0x3B)
        ay = read_word(0x3D)
        az = read_word(0x3F)

        gx = read_word(0x43)
        gy = read_word(0x45)
        gz = read_word(0x47)

        writer.writerow([
            ts,
            ax, ay, az,
            gx, gy, gz
        ])

        f.flush()

        time.sleep(0.02)
