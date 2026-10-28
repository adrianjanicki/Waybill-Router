# Karta drogowa (WaybillRouter)

Aplikacja na iPhone'a dla kierowcy: skanujesz list przewozowy, aplikacja znajduje firmy z kolumny „Trasa”,
TomTom układa optymalną kolejność przystanków (Magazyn → firmy → Magazyn) i liczy kilometry,
a kurs trafia do historii. Na koniec miesiąca masz podsumowanie i gotowe karty drogowe (po 15 kursów) w PDF
oraz zestawienie CSV do Excela.

Budowane przez [xtool](https://github.com/xtool-org/xtool) — zwykły pakiet SwiftPM, bez projektu Xcode,
podpisywany darmowym kontem Apple ID (personal team).

## Co jest w środku

| Funkcja | Gdzie |
|---|---|
| Skan dokumentu (VisionKit, prostowanie kartki) | `Sources/WaybillRouter/Scanning/DocumentScanner.swift` |
| OCR (Vision) i wyciąganie firm/daty | `Sources/WaybillRouter/Scanning/ScanService.swift` |
| TomTom: wyszukiwanie adresów, trasa `computeBestOrder=true`, profil `truck`, bez promów i dróg nieutwardzonych | `Sources/WaybillRouter/Services/TomTomService.swift` |
| Karty drogowe PDF + CSV | `Sources/WaybillRouter/Services/KartaExport.swift` |
| Dane (SwiftData): kursy i adresy firm | `Sources/WaybillRouter/Models/` |
| Ekrany | `Sources/WaybillRouter/Views/` |
| Konfiguracja xtool (bundle ID, Info.plist) | `xtool.yml` |

## Jak używać

1. **Skanuj listę przewozową** — aparat sam wykryje kartkę. Firmy, które aplikacja już zna, zaznaczy automatycznie;
   pozostałe dodajesz jednym dotknięciem z listy „Tekst z dokumentu” albo wpisujesz.
2. Nowej firmie podajesz adres **tylko raz** (np. „ul. Przemysłowa 5, Radzymin”). Potem jest zapamiętany.
3. Trasa liczy się sama. Możesz poprawić kilometry ręcznie i zapisać kurs.
4. Ikona **Karty** (lewy górny róg) — karty drogowe miesiąca, eksport PDF i CSV (udostępnij → Mail, Pliki, WhatsApp…).
5. **Ustawienia** — klucz TomTom, stawka zł/km, dane do karty, adres magazynu, lista adresów firm.

## Budowanie na Macu

Wymagania: Mac z **Xcode** (uruchom go raz i zaakceptuj licencję), iPhone z iOS 17+ podłączony kablem,
darmowe Apple ID. Na Macu **nie** trzeba `xtool sdk install` — to krok tylko dla Linuksa.

```bash
# 0. Xcode z App Store, potem (jednorazowo):
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -downloadPlatform iOS

# 1. xtool (jednorazowo)
brew install xtool-org/tap/xtool
xtool setup            # wybierz "Password", zaloguj się Apple ID (+ kod 2FA)

# 2. Projekt
cd WaybillRouter
# W xtool.yml zmień bundleID na własny, np. pl.twojenazwisko.WaybillRouter

# 3. Klucz TomTom (darmowy: https://developer.tomtom.com/) — opcjonalnie, można go też wpisać w aplikacji
export TOMTOM_API_KEY="twój_klucz"

# 4. Build + instalacja na podłączonym iPhonie
./build_and_install.sh
```

Przy pierwszej instalacji na iPhonie:
- **Ustawienia → Prywatność i ochrona → Tryb dewelopera** → włącz (telefon się zrestartuje).
- **Ustawienia → Ogólne → VPN i urządzenia** → zaufaj swojemu Apple ID.

Darmowe konto Apple podpisuje aplikację na **7 dni** — potem uruchom `./build_and_install.sh` jeszcze raz
(dane w aplikacji zostają).

### Inne komendy

```bash
./build_and_install.sh build   # tylko kompilacja, bez telefonu
xtool dev run --simulator      # symulator iOS (skaner nie działa, użyj „Wybierz zdjęcie z galerii”)
xtool dev generate-xcode-project   # jeśli chcesz otworzyć projekt w Xcode
```

## Najczęstsze problemy

- **`Resources/Info.plist` not found** — uruchamiaj przez `./build_and_install.sh` (tworzy ten plik), a nie gołe `xtool dev`.
- **„Brak klucza TomTom”** — wpisz klucz w Ustawieniach aplikacji albo zbuduj z `TOMTOM_API_KEY`.
- **Błąd bundle ID / App ID** — zmień `bundleID` w `xtool.yml` na unikalny.
- **Darmowe konto: limit 3 aplikacji / 10 App ID tygodniowo** — usuń stare aplikacje z telefonu.
