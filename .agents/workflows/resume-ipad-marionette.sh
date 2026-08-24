#!/usr/bin/env bash
# Agent-runnable. No prompts. Exit 0 only when flutter run is up and a
# Marionette ws:// URI is printed. Exit 2 if Developer Mode is still off.
set -euo pipefail

IPAD_UDID="${IPAD_UDID:-00008110-000E24912E63A01E}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
EXAMPLE="$ROOT/example"

# Host enable first. Fails with "Device has a passcode set" when a PIN exists.
/usr/bin/devmodectl single -v "$IPAD_UDID" || true

status="$(
  /usr/bin/devmodectl list 2>/dev/null \
    | awk -v id="$IPAD_UDID" '$1 == id { print $2; exit }'
)"

if [[ "$status" != "enabled" ]]; then
  printf 'developerModeStatus=%s\n' "${status:-unknown}" >&2
  printf 'Host CLI: /usr/bin/devmodectl single -v %s\n' "$IPAD_UDID" >&2
  printf 'If that prints "Failed to arm: Device has a passcode set", the\n' >&2
  printf 'human must remove the passcode or flip Settings → Privacy &\n' >&2
  printf 'Security → Developer Mode. Wizard:\n' >&2
  printf '  %s/.agents/workflows/enable-ipad-developer-mode.sh\n' "$ROOT" >&2
  printf 'Do not flutter run until enabled.\n' >&2
  exit 2
fi

cd "$EXAMPLE"
# flutter run stays in the foreground so the agent can parse the VM URI.
exec flutter run -d "$IPAD_UDID"
