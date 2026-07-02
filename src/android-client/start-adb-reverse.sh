#!/bin/bash
set -euo pipefail

if [[ -n "${ADB:-}" ]]; then
  ADB="$ADB"
elif command -v adb >/dev/null 2>&1; then
  ADB="$(command -v adb)"
else
  ADB="$HOME/Library/Android/sdk/platform-tools/adb"
fi
SERIAL="${1:-}"

if [[ -z "$SERIAL" ]]; then
  SERIAL="$("$ADB" devices | awk 'NR > 1 && $2 == "device" && $1 !~ /^emulator-/ { print $1; exit }')"
fi

if [[ -z "$SERIAL" ]]; then
  echo "No USB Android device found. Connect the tablet and allow USB debugging."
  "$ADB" devices
  exit 1
fi

echo "Using device: $SERIAL"
"$ADB" -s "$SERIAL" reverse tcp:19421 tcp:19421
"$ADB" -s "$SERIAL" reverse --list
