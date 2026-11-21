#!/bin/sh
# waitlog.sh <regex> [seconds]: wait for a NEW Apple TV syslog line matching
# <regex> (idevicesyslog replays old history first; lines stamped before this
# script started are skipped).  Prints the line; exit 1 on timeout.
pattern="$1"; secs="${2:-40}"
start=$(date +%H:%M:%S)
timeout "$secs" idevicesyslog 2>/dev/null | awk -v s="$start" -v p="$pattern" '
    $3 >= s && $0 ~ p { print; found = 1; exit }
    END { exit found ? 0 : 1 }'
