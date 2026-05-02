import 'package:flutter/foundation.dart';

/// Centralized logging utility with automatic debug/release filtering
/// 
/// Usage:
/// ```dart
/// Logger.debug('P2P initialization started');
/// Logger.info('Connected to 5 peers');
/// Logger.error('Failed to connect', error, stackTrace);
/// ```
/// 
/// All debug/info logs are automatically removed in release builds via tree-shaking.
/// Only errors are logged in production (useful for crash reporting).
class Logger {
  /// Debug log - only visible in debug builds
  /// Completely removed from release builds via tree-shaking
  static void debug(String message) {
    if (kDebugMode) {
      print('🔍 $message');
    }
  }
  
  /// Info log - only visible in debug builds  
  /// Completely removed from release builds via tree-shaking
  static void info(String message) {
    if (kDebugMode) {
      print('ℹ️  $message');
    }
  }
  
  /// Warning log - only visible in debug builds
  /// Completely removed from release builds via tree-shaking
  static void warning(String message) {
    if (kDebugMode) {
      print('⚠️ $message');
    }
  }
  
  /// Error log - visible in both debug and release builds
  /// Use this for errors that should be reported in production (e.g., crash reporting)
  /// Stack traces are only shown in debug mode
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    print('❌ $message');
    if (error != null) {
      print('   Error: $error');
    }
    if (stackTrace != null && kDebugMode) {
      print('   Stack trace:');
      print(stackTrace);
    }
  }
  
  /// Success log - only visible in debug builds
  /// Completely removed from release builds via tree-shaking
  static void success(String message) {
    if (kDebugMode) {
      print('✅ $message');
    }
  }
}
