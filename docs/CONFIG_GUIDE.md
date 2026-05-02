# App Configuration & Build Modes

This document explains how to build and run the app with different configurations for development and production environments.

## Overview

The app automatically selects its configuration based on the build mode:
- **Debug Build** - Development config: Fast polling, debug logging enabled
- **Release Build** - Production config: Conservative polling, battery-optimized, no debug logs

**No multiple entry points needed** - Flutter's `kDebugMode` automatically handles the configuration.

## Configuration Differences

| Feature | Debug Build | Release Build |
|---------|------------|---------------|
| **Message Polling** | 10 seconds | 60 seconds |
| **Background Sync** | 5 minutes | 15 minutes |
| **Max Cache** | 100 messages | 500 messages |
| **Debug Logging** | ✅ Enabled | ❌ Disabled (removed at compile-time) |
| **Debug Banner** | ✅ Shown | ❌ Hidden |

## Running the App

### Debug Mode (Development)

Fastest iteration with all debug features enabled:

```bash
# Run in debug mode (default)
flutter run

# Run on specific device
flutter run -d <device-id>
```

### Release Mode (Production)

Optimized build for production deployment:

```bash
# Run in release mode
flutter run --release

# Run on specific device
flutter run --release -d <device-id>
```

## Build Commands

### Android

```bash
# Debug APK (for testing)
flutter build apk --debug

# Release APK
flutter build apk --release

# App Bundle (for Play Store)
flutter build appbundle --release
```

### iOS

```bash
# Debug build
flutter build ios --debug

# Release build
flutter build ios --release
```

## Configuration Files

### `lib/config/app_config.dart`

Defines the `AppConfig` class with environment-specific settings:

```dart
class AppConfig {
  final Environment environment;
  final List<String> bootstrapNodes;
  final Duration messagePollingInterval;
  final Duration backgroundSyncInterval;
  final bool debugLogging;
  // ... more settings
  
  factory AppConfig.development() => const AppConfig(...);
  factory AppConfig.production() => const AppConfig(...);
}
```

### `lib/main.dart`

Single entry point that automatically selects config:

```dart
void main() async {
  // Auto-select config based on build mode
  final config = kDebugMode 
      ? AppConfig.development()   // Debug builds
      : AppConfig.production();   // Release builds
  
  runApp(ProviderScope(
    overrides: [appConfigProvider.overrideWithValue(config)],
    child: const MyApp(),
  ));
}
```

## How Configuration Selection Works

Flutter's `kDebugMode` constant is a **compile-time constant** that:
- Is `true` in debug builds (`flutter run`)
- Is `false` in release builds (`flutter run --release`)
- Enables tree-shaking: debug code is completely removed from release binaries

This means:
- ✅ No multiple entry points needed
- ✅ No manual config selection
- ✅ Debug logs automatically removed in release builds
- ✅ Smaller app size in production
- ✅ Better performance (zero overhead)

## Testing Configurations

Run all tests including config tests:

```bash
# Run all tests
flutter test

# Run only config tests
flutter test test/config/app_config_test.dart
```

## Adding New Configuration Options

1. **Add to AppConfig class** (`lib/config/app_config.dart`):
   ```dart
   final Duration newTimeout;
   ```

2. **Update factory constructors**:
   ```dart
   factory AppConfig.development() => AppConfig(
     // ... existing configs
     newTimeout: Duration(seconds: 5),
   );
   ```

3. **Use in services**:
   ```dart
   class MyService {
     final AppConfig _config;
     
     void doSomething() {
       final timeout = _config.newTimeout;
       // ...
     }
   }
   ```

4. **Add tests** (`test/config/app_config_test.dart`)

## Environment Detection

Check current environment in code:

```dart
final config = ref.read(appConfigProvider);

if (config.isDevelopment) {
  print('Running in development mode');
}

if (config.isProduction) {
  // Disable debug features
}

// Or check directly:
if (config.environment == Environment.staging) {
  // Staging-specific logic
}
```

## Debug Logging

Debug logs are controlled by `config.debugLogging`:

```dart
if (_config.debugLogging) {
  print('🚀 Initializing service...');
  print('   Config: ${_config.bootstrapNodes}');
}
```

**Production** has debug logging disabled to:
- Reduce log clutter
- Improve performance
- Reduce binary size
- Prevent sensitive info leakage

## Bootstrap Nodes

### Development
- Uses local server (`172.16.10.10`) for fast testing
- Falls back to public servers if local unavailable

### Staging & Production
- Only uses public libp2p bootstrap nodes
- Ensures reliability and availability
- Example: `/dnsaddr/bootstrap.libp2p.io/p2p/...`

## Polling Intervals

### Message Polling (Foreground)
How often to check for new messages while app is active:
- **Dev**: 10s (instant feedback for testing)
- **Staging**: 20s (moderate for realistic testing)
- **Prod**: 30s (battery-friendly)

### Background Sync
How often to check messages when app is in background:
- **Dev**: 5 min (frequent updates)
- **Staging**: 10 min (moderate)
- **Prod**: 15 min (battery-optimized)

## Best Practices

1. **Development**: Use for daily development and debugging
2. **Staging**: Use for pre-release testing and QA
3. **Production**: Only for final builds and app store releases

4. **Never** commit changes that hardcode production credentials
5. **Always** test production build before release
6. **Monitor** actual polling behavior in production

## Troubleshooting

### "No bootstrap peers reachable"
- Check network connection
- For dev: Ensure local server is running
- For prod: Check DNS resolution

### "Polling too slow/fast"
- Verify correct entry point is used (`-t lib/main_X.dart`)
- Check config values in logs
- Ensure background sync interval is configured

### "Wrong environment at runtime"
```dart
// Check current config
print(ref.read(appConfigProvider));
```

## Related Files

- `lib/config/app_config.dart` - Configuration definitions
- `lib/providers/config_provider.dart` - Riverpod provider
- `lib/services/p2p_service.dart` - Uses bootstrap nodes, polling interval
- `lib/services/background_sync_service.dart` - Uses background interval
- `test/config/app_config_test.dart` - Configuration tests

---

**Next Steps**: See [REFACTORING_ROADMAP.md](../REFACTORING_ROADMAP.md) for remaining tasks (Priority 3).
