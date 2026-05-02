# DHT Polling Architecture - UI Blocking Problem & Solution

## 🐛 Problem

Die App verwendet **synchrone FFI-Calls** für DHT-Abfragen, was den UI-Thread blockiert:

### Root Cause
1. **FFI ist synchron**: Native Go-Code (`dhtFindProviders`) läuft auf dem Main Thread
2. **DHT-Timeout**: Native Code hat 5s Timeout → UI friert für 5s ein
3. **Dart async hilft nicht**: `.timeout()` in Dart greift NICHT bei synchronen FFI-Calls
4. **Isolates unmöglich**: FFI-Pointer können nicht zwischen Isolates transferiert werden

### Code-Flow (VORHER - mit Blocking)
```dart
// p2p_service.dart
void _startPolling() {
  Timer.periodic(Duration(seconds: 10), (_) {
    _pollMessages(); // Ruft dhtFindProviders() auf
  });
}

// p2p_bridge.dart  
Future<List<String>> dhtFindProviders(String key) async {
  // SYNCHRONER FFI-CALL - blockiert UI!
  final resultPtr = _dhtFindProviders!(keyPtr, maxProviders);  
  // ↑ Dauert bis zu 5 Sekunden, UI komplett eingefroren
}

// mobile/p2p_c.go
func P2P_DHT_FindProviders(keyStr *C.char) *C.char {
  ctx, cancel := context.WithTimeout(globalCtx, 5*time.Second)
  // ↑ Läuft auf Main Thread → blockiert Dart
  providersChan := globalNode.DHT.FindProvidersAsync(ctx, c, maxProv)
}
```

### Symptome
- ✅ App startet normal
- ❌ Nach 5-10 Sekunden: **UI friert ein für ~5s**
- ❌ Alle 10 Sekunden wiederholt sich das Freezing
- ❌ Buttons reagieren nicht
- ❌ Scrolling ruckelt bzw. bleibt stehen

## ✅ Lösung

### Automatisches Polling DEAKTIVIERT

**Änderungen in `p2p_service.dart`:**

```dart
void _startPolling() {
  // AUTOMATIC POLLING DISABLED!
  // Polling now happens only on-demand
  print('📵 Automatic polling DISABLED (prevents UI blocking)');
}

// Neue Methode für manuelles Polling
Future<void> pollMessagesManually() async {
  print('🔄 Manual poll triggered');
  await _pollMessages();
}
```

### Polling nur noch bei:

1. **Manueller Refresh** (Refresh-Button in HomeScreen)
   ```dart
   // home_screen.dart
   void _loadChats() async {
     await _p2pService.pollMessagesManually(); // Explizit vom User getriggert
     final chats = await _p2pService.getChats();
   }
   ```

2. **App kommt in Foreground** (Optional TODO)
   ```dart
   // main.dart - AppLifecycleListener
   onResume: () => _p2pService.pollMessagesManually();
   ```

3. **Chat wird geöffnet** (Optional TODO)
   ```dart
   // chat_screen.dart
   @override
   void initState() {
     _p2pService.pollMessagesManually(); // Poll beim Öffnen
   }
   ```

### Vorteile
- ✅ **Keine UI-Blockierung** während normaler Nutzung
- ✅ User hat Kontrolle über Polling (Refresh-Button)
- ✅ Loading-Spinner zeigt, dass Polling läuft
- ✅ Reduziert DHT-Network-Load (weniger Abfragen)

### Nachteile
- ⚠️ Nachrichten kommen nicht automatisch an
- ⚠️ User muss manuell refreshen
- ⚠️ Bei längerem Hintergrund keine Sync

## 🔮 Langfristige Lösung (TODO)

### Option 1: Async FFI mit Port-based Messaging
```go
// mobile/p2p_c.go
//export P2P_DHT_FindProviders_Async
func P2P_DHT_FindProviders_Async(keyStr *C.char, callbackPort C.int64) {
  go func() {
    // Run in separate goroutine
    providers := findProviders(key)
    // Send result back via Dart SendPort
    sendResultToPort(callbackPort, providers)
  }()
}
```

```dart
// p2p_bridge.dart
ReceivePort _resultPort = ReceivePort();

Future<List<String>> dhtFindProvidersAsync(String key) async {
  final completer = Completer<List<String>>();
  _resultPort.listen((result) {
    completer.complete(result);
  });
  _dhtFindProvidersAsync!(keyPtr, _resultPort.sendPort.nativePort);
  return completer.future;
}
```

### Option 2: Background Fetch (Push Notifications)
- APNS für iOS
- FCM für Android
- Oasis Node sendet Push bei neuer Nachricht
- App pollt nur wenn Push kommt

### Option 3: WebSocket Connection
- Oasis Node öffnet WebSocket
- App hält Verbindung offen
- Server pushed neue Nachrichten
- Kein Polling nötig

## 📊 Performance-Verbesserungen

### Vorher (mit Auto-Polling)
```
App Start: ═══════════════════════════════
           ↓ 5s (DHT init)
           ▓▓▓▓▓ (UI blocked)
           ↓ 10s idle
           ▓▓▓▓▓ (UI blocked - poll #1)
           ↓ 10s idle
           ▓▓▓▓▓ (UI blocked - poll #2)
           ... alle 10s wiederholt
```

### Nachher (Manual Polling)
```
App Start: ═══════════════════════════════
           ↓ instant (kein auto-poll)
           ✅ UI smooth
           
User klickt Refresh:
           ▓▓▓▓▓ (UI blocked, aber erwartet!)
           ✅ Nachrichten geladen
           
Normale Nutzung:
           ✅✅✅ Komplett smooth
```

## 🧪 Testing

### Vor Änderungen
1. App starten
2. Nach ~10s: UI freezt für ~5s
3. Wiederholt sich alle 10s

### Nach Änderungen
1. App starten
2. ✅ UI bleibt smooth
3. Refresh-Button klicken
4. ⏳ Loading-Spinner während Polling
5. ✅ Nachrichten aktualisiert
6. ✅ UI bleibt smooth danach

## 📝 Logs

### Alte Logs (mit Blocking)
```
flutter: 🔍 Searching for messages via DHT: /oasis-mailbox/...
[5 Sekunden Stille - UI eingefroren]
flutter: ✅ DHT found 1 providers for key: ...
```

### Neue Logs (ohne Auto-Polling)
```
flutter: 📵 Automatic polling DISABLED (prevents UI blocking)
flutter:    → Poll manually via pullToRefresh or pollMessagesManually()

[User klickt Refresh]
flutter: 🔄 Manual poll triggered
flutter: 🔍 [BLOCKING] Searching for messages via DHT: ...
flutter:    ⚠️ UI will freeze for ~5s during DHT query!
[5 Sekunden - aber erwartet, da User aktiv refresht]
flutter: ✅ DHT found 1 providers for key: ...
```

## 🎯 Zusammenfassung

**Problem**: Synchrone FFI-Calls blockieren UI für 5s alle 10s
**Lösung**: Automatisches Polling deaktiviert, nur on-demand
**Trade-off**: Keine automatischen Updates, aber smooth UI
**Langfristig**: Async FFI oder Push Notifications implementieren
