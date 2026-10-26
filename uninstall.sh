#!/usr/bin/env bash
# Removes OwlMac and its settings.
set -euo pipefail

say() { printf '\033[1;33m🦉 %s\033[0m\n' "$*"; }

# Quitting normally lets OwlMac undo `pmset disablesleep` if it was on.
if pgrep -x OwlMac >/dev/null; then
  osascript -e 'tell application "OwlMac" to quit' 2>/dev/null || pkill -x OwlMac || true
  sleep 2
fi

rm -rf "/Applications/OwlMac.app" "$HOME/Applications/OwlMac.app"
defaults delete io.github.owlmac 2>/dev/null || true

if pmset -g | grep -q 'SleepDisabled[[:space:]]*1'; then
  say "뚜껑 닫힘 잠자기가 아직 꺼져 있어요. 되돌리려면: sudo pmset -a disablesleep 0"
fi
say "OwlMac을 지웠어요. 잘 자요."
