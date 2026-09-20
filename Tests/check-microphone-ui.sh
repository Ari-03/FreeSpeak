#!/usr/bin/env bash
# Pass the pinned agent-device command (or a wrapper) supplied by T3's Device panel.
# Start on the Dictate tab, with a provider that can pass its configuration checks.
set -euo pipefail
if (( $# == 0 )); then
  echo 'Usage: bash Tests/check-microphone-ui.sh /path/to/pinned-device-command' >&2
  exit 2
fi
snapshot="$("$@" snapshot -i)"
button="$(printf '%s\n' "$snapshot" | sed -n 's/^\(@e[0-9]*\).*\[button\] "Start dictating".*/\1/p' | head -1)"
if [[ -z "$button" ]]; then
  echo 'FAIL: Open the Dictate tab with Start dictating available.' >&2
  exit 1
fi
result="$("$@" click "$button" --settle)"
printf '%s\n' "$result"
if [[ "$result" == *'snapshot capture stalled'* ]]; then
  echo 'FAIL: Microphone startup froze the UI.' >&2
  exit 1
fi
snapshot="$("$@" snapshot -i)"
button="$(printf '%s\n' "$snapshot" | sed -n 's/^\(@e[0-9]*\).*\[button\] "Modes".*/\1/p' | head -1)"
[[ -n "$button" ]] || { echo 'FAIL: UI unavailable after microphone tap.' >&2; exit 1; }
result="$("$@" click "$button" --settle)"
[[ "$result" != *'snapshot capture stalled'* ]] || { echo 'FAIL: Tab navigation froze.' >&2; exit 1; }
snapshot="$("$@" snapshot -i)"
[[ "$snapshot" == *'"Modes" [selected]'* ]] || { echo 'FAIL: Modes did not open.' >&2; exit 1; }
echo 'PASS: Microphone tap and tab navigation remain responsive.'
