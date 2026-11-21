#!/bin/sh
# run.sh "<steps>" <last-shot-name>: run the screenshot tool once, wait for the
# last picture, and turn this run's PNGs into JPEGs for the README.
DEV="${SIMDEV:-iPad Pro 11-inch (M5)}"; OUT="$(cd "$(dirname "$0")/../.." && pwd)/docs/screenshots"
mkdir -p "$OUT"; rm -f "$OUT/$2.png"
SIMCTL_CHILD_JF_STEPS="$1" SIMCTL_CHILD_JF_OUT="$OUT" xcrun simctl launch --terminate-running-process "$DEV" org.jellyfin.atv3.shots >/dev/null
i=0; until [ -f "$OUT/$2.png" ] || [ $i -ge 90 ]; do sleep 1; i=$((i+1)); done
sleep 1
for f in "$OUT"/*.png; do [ -f "$f" ] || continue; sips -s format jpeg -s formatOptions 85 "$f" --out "${f%.png}.jpg" >/dev/null && rm "$f"; done
ls -l "$OUT/$2.jpg"
