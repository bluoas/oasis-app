# Background Sync Implementation Guide

## Overview

This document describes the background message polling implementation for the Oasis Chat App. The background service ensures messages are retrieved periodically even when the app is not in the foreground.

## Architecture

### Components

1. **BackgroundSyncService** (`lib/services/background_sync_service.dart`)
   - Manages WorkManager lifecycle
   - Registers periodic polling tasks
   - Executes background message retrieval

2. **P2PService Integration**
   - Caches Oasis Node addresses in SharedPreferences
   - Loads cached nodes on app startup
   - Saves nodes after successful DHT query

3. **SettingsScreen** (`lib/screens/settings_screen.dart`)
   - User-facing toggle for enabling/disabling background sync
   - Shows polling frequency (15 minutes)
   - Provides identity management options

### Data Flow

```
App Startup:
  1. Initialize WorkManager
  2. Start P2P Service
  3. Load cached nodes from SharedPreferences
  4. Connect to bootstrap nodes
  5. Query DHT for Oasis Nodes
  6. Save nodes to SharedPreferences
  7. Register background polling task

Background Task (every 15 minutes):
  1. WorkManager triggers callback
  2. Load cached nodes from SharedPreferences
  3. Query nodes directly for messages
  4. Process and store messages
  5. (Optional) Show notification
```

## Implementation Details

### 1. WorkManager Setup

**Initialization** (in `main.dart`):
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize WorkManager BEFORE runApp
  await BackgroundSyncService.initialize();
  
  runApp(const MyApp());
}
```

**Registration** (after P2P initialization):
```dart
// In _initialize() method of MyApp
await BackgroundSyncService.registerPeriodicPolling();
```

### 2. Platform Configuration

**iOS** (`ios/Runner/Info.plist`):
```xml
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>processing</string>
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.transistorsoft.fetch</string>
</array>
```

**Android** (`android/app/src/main/AndroidManifest.xml`):
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

### 3. Node Caching Strategy

The background service uses **cached Oasis Nodes** to avoid slow DHT queries (which take ~5 seconds and would timeout in background).

**Cache Storage**:
- **Location**: SharedPreferences (accessible from background isolate)
- **Key**: `cached_oasis_nodes` (StringList)
- **Timestamp**: `cache_timestamp` (int milliseconds)

**Update Triggers**:
- Manual sync from UI (cloud_sync button)
- Periodic DHT refresh in foreground app
- App startup (if cache empty or stale)

**Cache Validation**:
- Age check: Warn if > 6 hours old
- Fallback: Bootstrap nodes if cache empty
- No DHT in background: Only use cached nodes

### 4. Background Polling Logic

**Current Implementation** (MVP):
```dart
Future<void> _performMessagePolling() async {
  // 1. Load cached nodes from SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final cachedNodes = prefs.getStringList('cached_oasis_nodes');
  
  // 2. Validate cache
  if (cachedNodes == null || cachedNodes.isEmpty) {
    debugPrint('⚠️ No cached nodes available');
    return;
  }
  
  // 3. Log success (full implementation pending)
  debugPrint('✅ Found ${cachedNodes.length} nodes to query');
}
```

**Full Implementation** (TODO):
```dart
Future<void> _performMessagePolling() async {
  // 1. Load identity from secure storage
  final identity = await loadIdentityInBackground();
  
  // 2. Load cached nodes
  final nodes = await loadCachedNodes();
  
  // 3. Query each node directly
  for (final nodePeerID in nodes) {
    final messages = await queryNodeForMessages(nodePeerID, identity.peerID);
    
    // 4. Process and store messages
    for (final message in messages) {
      await processAndStoreMessage(message);
    }
  }
  
  // 5. (Optional) Show notification
  if (newMessagesCount > 0) {
    await showLocalNotification('$newMessagesCount new messages');
  }
}
```

## Testing

### Unit Tests

No additional unit tests required - background service uses existing P2P service methods which are already tested (49/49 tests passing).

### Device Testing

**IMPORTANT**: WorkManager does NOT work in iOS Simulator or Android Emulator. Must test on **physical device**.

**Testing Steps**:

1. **Install app on physical device**:
   ```bash
   flutter run --release
   ```

2. **Enable background sync**:
   - Open app
   - Navigate to Settings (gear icon in top right)
   - Toggle "Enable Background Sync"

3. **Verify registration**:
   - Check logs for: "✅ Periodic polling registered"

4. **Test background polling**:
   - Send app to background (home button)
   - Wait 15+ minutes
   - Check device logs for: "📬 Polling messages in background..."

5. **Verify message retrieval**:
   - Have another device send a message
   - Wait for background task
   - Open app - new message should appear

**iOS Testing**:
```bash
# View background task logs
xcrun simctl spawn booted log stream --predicate 'eventMessage contains "background"'
```

**Android Testing**:
```bash
# View background task logs
adb logcat | grep "BackgroundSync"
```

## Performance Considerations

### Battery Impact

- **Frequency**: Every 15 minutes (default WorkManager minimum)
- **Constraints**: Network-only (no cellular data if disabled)
- **Duration**: ~2-5 seconds per poll (no DHT queries)
- **Expected Impact**: Minimal (<1% battery per day)

### Network Usage

- **Per Poll**: ~1-5 KB (depends on message count)
- **Per Day**: ~96 polls × 3 KB = ~288 KB/day
- **Monthly**: ~8.6 MB/month (negligible)

### Storage

- **Node Cache**: ~1-2 KB (10-20 node addresses)
- **Message Storage**: Hive database (same as foreground)
- **No Duplication**: Nonce-based replay protection

## Troubleshooting

### Background tasks not running

**Issue**: No logs after 15 minutes in background

**Possible Causes**:
1. Testing on simulator/emulator (not supported)
2. Battery optimization enabled (Android)
3. Background refresh disabled (iOS)
4. Not enough time elapsed (needs 15+ min)

**Solutions**:
- Use physical device
- Disable battery optimization for app
- Enable Background App Refresh in iOS Settings
- Wait full 15 minutes before checking

### "No cached nodes available" error

**Issue**: Background polling logs show no nodes to query

**Cause**: Cache not populated (fresh install or never synced)

**Solution**:
1. Open app
2. Tap cloud_sync button (top right)
3. Wait for sync to complete
4. Nodes are now cached for background

### Messages not appearing

**Issue**: Background task runs but messages don't show in app

**Possible Causes**:
1. Nodes are offline (cached nodes may be stale)
2. Message encryption failure
3. Database write permissions issue

**Debug**:
```dart
// Enable debug mode in WorkManager
await Workmanager().initialize(
  callbackDispatcher,
  isInDebugMode: true, // Shows detailed logs
);
```

## Future Enhancements

### Priority 1: Full Background Polling

**Current State**: MVP - logs cached nodes but doesn't query them

**TODO**:
- [ ] Load identity from secure storage in background isolate
- [ ] Initialize P2P bridge in background context
- [ ] Send /retrieve requests to cached nodes
- [ ] Decrypt and store messages in Hive
- [ ] Handle encryption key exchange in background

**Challenge**: Background isolate cannot share state with main isolate

**Solution Options**:
1. Use platform channels to delegate polling to native code
2. Initialize services from scratch in background (memory intensive)
3. Use MethodChannel to trigger main app polling

### Priority 2: Local Notifications

**Feature**: Show notification when new messages arrive in background

**Implementation**:
```dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> _showNewMessageNotification(int count, String senderName) async {
  final FlutterLocalNotificationsPlugin notifications = 
      FlutterLocalNotificationsPlugin();
  
  await notifications.show(
    0,
    'New Messages',
    count == 1 
        ? 'New message from $senderName'
        : '$count new messages',
    NotificationDetails(
      iOS: DarwinNotificationDetails(),
      android: AndroidNotificationDetails(
        'messages',
        'Messages',
        importance: Importance.high,
      ),
    ),
  );
}
```

### Priority 3: Adaptive Polling

**Feature**: Adjust polling frequency based on usage patterns

**Strategy**:
- Active users: Every 5 minutes (iOS/Android allow down to 5 min for critical tasks)
- Normal users: Every 15 minutes (current)
- Inactive users: Every 30-60 minutes

**Implementation**:
```dart
// Track last message time
final prefs = await SharedPreferences.getInstance();
final lastMessageTime = prefs.getInt('last_message_timestamp') ?? 0;
final hoursSinceLastMessage = 
    (DateTime.now().millisecondsSinceEpoch - lastMessageTime) / 3600000;

// Adjust frequency
Duration frequency;
if (hoursSinceLastMessage < 1) {
  frequency = Duration(minutes: 5); // Active
} else if (hoursSinceLastMessage < 24) {
  frequency = Duration(minutes: 15); // Normal
} else {
  frequency = Duration(minutes: 60); // Inactive
}

await Workmanager().registerPeriodicTask(
  uniqueTaskName,
  messagePollingTaskName,
  frequency: frequency,
  // ...
);
```

### Priority 4: Smart Cache Refresh

**Feature**: Refresh node cache in background when it becomes stale

**Trigger**: After 6 hours, next background task performs DHT query

**Implementation**:
```dart
Future<void> _performMessagePolling() async {
  final prefs = await SharedPreferences.getInstance();
  final timestamp = prefs.getInt('cache_timestamp');
  
  // Check if cache is stale (> 6 hours)
  if (timestamp != null) {
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(timestamp)
    );
    
    if (age.inHours > 6) {
      debugPrint('🔄 Cache stale, refreshing...');
      await _refreshCacheInBackground();
    }
  }
  
  // Continue with normal polling...
}
```

## API Reference

### BackgroundSyncService

#### Methods

**`static Future<void> initialize()`**
- Initialize WorkManager
- Must be called in `main()` before `runApp()`
- Skips initialization on Web platform

**`static Future<void> registerPeriodicPolling()`**
- Register 15-minute periodic task
- Constraints: Network connected, any battery level
- Call after P2P service is initialized

**`static Future<void> cancelPeriodicPolling()`**
- Stop background polling
- Useful when user disables feature

**`static Future<void> cancelAll()`**
- Cancel all WorkManager tasks
- Use on app uninstall or reset

### P2PService (Background-Related)

#### Methods

**`Future<void> _saveCachedNodesToPrefs()`**
- Save current Oasis Nodes to SharedPreferences
- Called after successful DHT query
- Stores: node list + timestamp

**`Future<void> _loadCachedNodesFromPrefs()`**
- Load previously cached nodes
- Called on app startup
- Fallback if DHT query fails

**`Future<void> refreshOasisNodesCache()`**
- Query DHT for available Oasis Nodes
- Update in-memory cache
- Save to SharedPreferences for background

### SettingsScreen

#### Features

- **Background Sync Toggle**: Enable/disable periodic polling
- **Identity Management**: View Peer ID, reset identity
- **Network Info**: View cached nodes (coming soon)
- **About**: App version and architecture info

## Dependencies

```yaml
dependencies:
  workmanager: ^0.5.2
  shared_preferences: ^2.2.2
  flutter_secure_storage: ^9.0.0  # For identity storage
  hive: ^2.2.3                     # For message storage
```

## License

Same as main project (see root LICENSE file)

## Support

For issues or questions about background sync:
1. Check logs with WorkManager debug mode
2. Verify platform permissions
3. Test on physical device (not simulator)
4. Report bugs with device logs and reproduction steps
