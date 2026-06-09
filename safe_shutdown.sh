#!/bin/bash

echo "Stopping recorder..."

systemctl stop record.service

for i in {1..30}
do
    if ! systemctl is-active --quiet record.service
    then
        break
    fi
    sleep 1
done

sync

sleep 2

shutdown -h now
