# iOS Build Fix für P2P Symbole

## Problem
Die nativen P2P-Symbole (P2P_Initialize, etc.) werden zur Laufzeit nicht gefunden, obwohl das P2P.xcframework eingebunden ist.

## Ursache
Die statische Library (`libp2p.a`) im xcframework muss mit `-force_load` Flag gelinkt werden, damit alle Symbole verfügbar sind.

## Lösung: Xcode Build Settings anpassen

### Option 1: Über Xcode GUI

1. Öffne `ios/Runner.xcworkspace` in Xcode
2. Wähle das **Runner** Projekt in der linken Sidebar
3. Wähle das **Runner** Target
4. Gehe zu **Build Settings** Tab
5. Suche nach "Other Linker Flags" (OTHER_LDFLAGS)
6. Füge hinzu:
   ```
   -force_load $(PROJECT_DIR)/P2P.xcframework/ios-arm64/libp2p.a
   ```
7. Clean Build Folder (⌘ + Shift + K)
8. Build (⌘ + B)

### Option 2: Über xcconfig-Datei

Bearbeite `ios/Flutter/Debug.xcconfig` und `ios/Flutter/Release.xcconfig`:

```xcconfig
#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.debug.xcconfig"
#include "Generated.xcconfig"

OTHER_LDFLAGS = $(inherited) -force_load $(PROJECT_DIR)/P2P.xcframework/ios-arm64/libp2p.a -framework Security -lresolv
```

### Option 3: Podfile post_install Hook (automatisch)

Der Podfile enthält bereits einen post_install Hook. Nach jedem `pod install` sollte die Konfiguration automatisch angewendet werden.

## Wichtig

- Das xcframework unterstützt nur **echte iOS-Geräte** (arm64)
- Simulator wird **NICHT** unterstützt
- Nach jeder Änderung: `flutter clean` ausführen

## Verifikation

Wenn erfolgreich, sollten keine "symbol not found" Fehler mehr auftreten beim Start der App.
