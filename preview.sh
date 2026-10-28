#!/usr/bin/env bash
# Podgląd aplikacji na Macu przed instalacją na telefonie.
#   ./preview.sh          # projekt Xcode z aplikacją -> wybierz symulator iPhone i kliknij ▶︎ (Run)
#   ./preview.sh canvas   # sam pakiet w Xcode -> Previews.swift + Canvas (⌥⌘↩) z przykładowymi kursami
# Symulator ma osobne dane (puste na start), więc nic nie miesza w kursach z telefonu.
set -euo pipefail
cd "$(dirname "$0")"
[[ -f Resources/Info.plist ]] || cp Resources/Info.base.plist Resources/Info.plist

if [[ "${1:-}" == "canvas" ]]; then
    open -a Xcode Package.swift
    exit 0
fi

command -v xtool >/dev/null || { echo "Brak xtool. Zainstaluj: brew install xtool-org/tap/xtool"; exit 1; }
mkdir -p "$HOME/Library/org.swift.swiftpm/swift-sdks"
xtool dev generate-xcode-project
proj=$(find xtool . -maxdepth 3 -name '*.xcodeproj' -not -path './.build/*' 2>/dev/null | head -1)
if [[ -n "$proj" ]]; then
    echo "Otwieram $proj – wybierz u góry symulator iPhone i kliknij ▶︎."
    open -a Xcode "$proj"
else
    echo "Nie znalazłem projektu .xcodeproj – otwieram pakiet (tryb canvas)."
    open -a Xcode Package.swift
fi
