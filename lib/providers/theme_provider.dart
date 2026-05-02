import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

/// Theme mode state notifier with persistence
/// 
/// Manages the app's theme mode (light/dark/system) and persists the user's choice
class ThemeNotifier extends StateNotifier<ThemeMode> {
  static const String _key = 'theme_mode';
  
  ThemeNotifier() : super(ThemeMode.dark) {
    // Load persisted theme on initialization
    _loadTheme();
  }

  /// Load theme mode from shared preferences
  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeModeString = prefs.getString(_key);
      
      if (themeModeString != null) {
        state = ThemeMode.values.firstWhere(
          (mode) => mode.toString() == themeModeString,
          orElse: () => ThemeMode.dark,
        );
      }
    } catch (e) {
      Logger.warning('Failed to load theme preference: $e');
      // Default to dark theme on error
      state = ThemeMode.dark;
    }
  }

  /// Save theme mode to shared preferences
  Future<void> _saveTheme(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.toString());
    } catch (e) {
      Logger.warning('Failed to save theme preference: $e');
    }
  }

  /// Set theme mode to light
  Future<void> setLightMode() async {
    state = ThemeMode.light;
    await _saveTheme(ThemeMode.light);
  }

  /// Set theme mode to dark
  Future<void> setDarkMode() async {
    state = ThemeMode.dark;
    await _saveTheme(ThemeMode.dark);
  }

  /// Set theme mode to system (follows OS setting)
  Future<void> setSystemMode() async {
    state = ThemeMode.system;
    await _saveTheme(ThemeMode.system);
  }

  /// Toggle between light and dark mode
  Future<void> toggleTheme() async {
    if (state == ThemeMode.dark) {
      await setLightMode();
    } else {
      await setDarkMode();
    }
  }

  /// Check if current mode is dark
  bool get isDark => state == ThemeMode.dark;

  /// Check if current mode is light
  bool get isLight => state == ThemeMode.light;

  /// Check if current mode is system
  bool get isSystem => state == ThemeMode.system;
}

/// Global theme provider
/// 
/// Usage:
/// ```dart
/// // Get current theme mode
/// final themeMode = ref.watch(themeProvider);
/// 
/// // Change theme
/// ref.read(themeProvider.notifier).setDarkMode();
/// ref.read(themeProvider.notifier).setLightMode();
/// ref.read(themeProvider.notifier).setSystemMode();
/// ref.read(themeProvider.notifier).toggleTheme();
/// ```
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});
