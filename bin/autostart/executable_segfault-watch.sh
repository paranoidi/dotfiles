#!/bin/bash
journalctl -f | grep --line-buffered -i segfault | \
while read line; do
    DISPLAY=:0 notify-send "Segfault detected!" "$line"
done
