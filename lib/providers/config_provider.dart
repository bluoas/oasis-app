import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';

/// Global app configuration provider
/// 
/// This is overridden at app startup by main_dev.dart, main_staging.dart, or main_prod.dart
/// Default is development for fallback
final appConfigProvider = Provider<AppConfig>((ref) {
  // Default to development if not overridden
  // In practice, this is always overridden by the main entry point
  return AppConfig.development();
});

/// Global connectivity state
/// 
/// Set to true when no internet connection is detected at startup.
/// Watched by MaterialApp.builder to show a persistent offline banner across all screens.
final connectivityProvider = StateProvider<bool>((ref) => false);
