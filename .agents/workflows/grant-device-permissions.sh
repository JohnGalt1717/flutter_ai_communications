#!/usr/bin/env bash
# Agent-runnable. No prompts.
# Exit 0: host grant applied (Android or iOS simulator).
# Exit 2: physical iOS / unknown — human must tap Allow.
# Exit 1: device missing, package not installed, or grant failed.
set -euo pipefail

ANDROID_PACKAGE="${ANDROID_PACKAGE:-com.example.flutter_ai_communications}"
IOS_BUNDLE="${IOS_BUNDLE:-com.example.flutterAiCommunications}"
ANDROID_PERMISSION="${ANDROID_PERMISSION:-android.permission.RECORD_AUDIO}"

usage() {
  printf 'usage: %s <device-id>\n' "${0##*/}" >&2
  exit 1
}

[[ $# -eq 1 ]] || usage
DEVICE="$1"

if ! command -v flutter >/dev/null 2>&1; then
  printf 'flutter not on PATH\n' >&2
  exit 1
fi

devices="$(flutter devices --machine 2>/dev/null || true)"
if [[ -z "$devices" ]]; then
  printf 'flutter devices returned nothing\n' >&2
  exit 1
fi

eval "$(
  DEVICE_ID="$DEVICE" python3 - "$devices" <<'PY'
import json, os, sys
raw = sys.argv[1]
target = os.environ["DEVICE_ID"]
try:
    rows = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)
match = next((row for row in rows if row.get("id") == target), None)
if match is None:
    sys.exit(0)
platform = (match.get("targetPlatform") or "").lower()
kind = "unknown"
if platform.startswith("android"):
    kind = "android"
elif platform.startswith("ios"):
    kind = "ios-sim" if match.get("emulator") else "ios-device"
elif platform.startswith("darwin"):
    kind = "macos"
print(f'KIND={kind}')
print(f'PLATFORM={platform}')
PY
)"

KIND="${KIND:-unknown}"

case "$KIND" in
  android)
    if ! command -v adb >/dev/null 2>&1; then
      printf 'adb not on PATH\n' >&2
      exit 1
    fi
    if ! adb -s "$DEVICE" shell pm list packages 2>/dev/null | grep -q "$ANDROID_PACKAGE"; then
      printf 'package %s not installed on %s — flutter run/drive first\n' \
        "$ANDROID_PACKAGE" "$DEVICE" >&2
      exit 1
    fi
    adb -s "$DEVICE" shell pm grant "$ANDROID_PACKAGE" "$ANDROID_PERMISSION"
    printf 'granted %s to %s on %s\n' "$ANDROID_PERMISSION" "$ANDROID_PACKAGE" "$DEVICE"
    adb -s "$DEVICE" shell pm grant "$ANDROID_PACKAGE" android.permission.CAMERA || true
    printf 'granted CAMERA to %s on %s\n' "$ANDROID_PACKAGE" "$DEVICE"
    exit 0
    ;;
  ios-sim)
    xcrun simctl privacy "$DEVICE" grant microphone "$IOS_BUNDLE"
    xcrun simctl privacy "$DEVICE" grant camera "$IOS_BUNDLE" || true
    printf 'simctl granted microphone and camera to %s on %s\n' "$IOS_BUNDLE" "$DEVICE"
    exit 0
    ;;
  ios-device)
    printf 'physical iOS %s: no host TCC grant. Tap Allow on the microphone and camera sheets.\n' "$DEVICE" >&2
    printf 'Isolation Open is not this prompt. Keep the exclusive flutter process.\n' >&2
    exit 2
    ;;
  macos)
    printf 'macOS %s: grant Microphone and Camera in System Settings → Privacy & Security if prompted.\n' "$DEVICE" >&2
    exit 2
    ;;
  *)
    printf 'device %s not in flutter devices --machine (or unsupported). Human grant if a sheet is up.\n' "$DEVICE" >&2
    exit 2
    ;;
esac
