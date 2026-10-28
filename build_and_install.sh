#!/usr/bin/env bash
# Buduje aplikację przez xtool i instaluje ją na podłączonym iPhonie.
# Użycie:
#   export TOMTOM_API_KEY="..."   # opcjonalnie - klucz można też wpisać w Ustawieniach aplikacji
#   ./build_and_install.sh        # build + instalacja + uruchomienie
#   ./build_and_install.sh build  # tylko build (bez telefonu)
set -euo pipefail
cd "$(dirname "$0")"

command -v xtool >/dev/null || { echo "Brak xtool. Zainstaluj: brew install xtool-org/tap/xtool"; exit 1; }

if ! xcrun -sdk iphoneos -show-sdk-path >/dev/null 2>&1; then
    echo "Brak iOS SDK. Zainstaluj Xcode z App Store, a potem:"
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo "  sudo xcodebuild -license accept"
    echo "  xcodebuild -downloadPlatform iOS"
    exit 1
fi

# SwiftPM na macOS wywraca się, gdy katalog Swift SDK nie istnieje (xtool używa wbudowanego SDK iOS).
mkdir -p "$HOME/Library/org.swift.swiftpm/swift-sdks"

cp Resources/Info.base.plist Resources/Info.plist
if [[ "${TOMTOM_API_KEY:-}" == "tu_wklej_klucz" || "${TOMTOM_API_KEY:-}" == "twój_klucz" ]]; then
    echo "Uwaga: TOMTOM_API_KEY to wciąż przykładowy tekst - wpisz prawdziwy klucz (albo podasz go w Ustawieniach aplikacji)."
    unset TOMTOM_API_KEY
fi

if [[ -n "${TOMTOM_API_KEY:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :TomTomAPIKey ${TOMTOM_API_KEY}" Resources/Info.plist
    echo "Klucz TomTom wbudowany w aplikację."
else
    echo "Uwaga: brak TOMTOM_API_KEY - wpisz klucz w Ustawieniach aplikacji na telefonie."
fi

if [[ "${1:-}" == "build" ]]; then
    xtool dev build
else
    # Pierwsze uruchomienie: xtool poprosi o logowanie Apple ID (xtool setup).
    xtool dev run
fi
