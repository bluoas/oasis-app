import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';

/// Notification Utilities
/// 
/// Handles haptic feedback, vibration, and sound for incoming messages and calls.
class NotificationUtils {
  static const String _vibrationEnabledKey = 'vibration_on_message_enabled';
  static const String _soundEnabledKey = 'sound_on_message_enabled';
  
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static final AudioPlayer _callEndPlayer = AudioPlayer();
  
  /// Check if vibration is enabled in settings
  static Future<bool> isVibrationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_vibrationEnabledKey) ?? true; // Default: enabled
  }
  
  /// Set vibration preference
  static Future<void> setVibrationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vibrationEnabledKey, enabled);
  }
  
  /// Check if sound is enabled in settings
  static Future<bool> isSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_soundEnabledKey) ?? true; // Default: enabled
  }
  
  /// Set sound preference
  static Future<void> setSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundEnabledKey, enabled);
  }
  
  /// Trigger vibration for incoming message
  /// Only vibrates if the setting is enabled
  static Future<void> vibrateForIncomingMessage() async {
    final enabled = await isVibrationEnabled();
    if (enabled) {
      try {
        // Use medium impact for noticeable but not annoying vibration
        await HapticFeedback.mediumImpact();
      } catch (e) {
        // Silently fail if vibration is not supported on platform
        // (e.g., desktop platforms)
      }
    }
  }
  
  /// Play notification sound for incoming message
  /// Only plays if the setting is enabled
  static Future<void> playSoundForIncomingMessage() async {
    final enabled = await isSoundEnabled();
    if (enabled) {
      try {
        await _audioPlayer.stop(); // Stop any previous sound
        await _audioPlayer.play(AssetSource('sounds/newmessagetone.mp3'));
      } catch (e) {
        // Silently fail if sound playback is not supported
      }
    }
  }
  
  /// Trigger both vibration and sound for incoming message
  static Future<void> notifyIncomingMessage() async {
    await Future.wait([
      vibrateForIncomingMessage(),
      playSoundForIncomingMessage(),
    ]);
  }
  
  /// Trigger light vibration (for UI interactions)
  static Future<void> vibrateLite() async {
    try {
      await HapticFeedback.lightImpact();
    } catch (e) {
      // Silently fail
    }
  }
  
  /// Trigger heavy vibration (for important notifications)
  static Future<void> vibrateHeavy() async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (e) {
      // Silently fail
    }
  }
  
  /// Play end call tone
  /// Always plays regardless of notification settings
  static Future<void> playCallEndTone() async {
    try {
      await _callEndPlayer.stop(); // Stop any previous sound
      await _callEndPlayer.play(AssetSource('sounds/endtone.mp3'));
    } catch (e) {
      // Silently fail if sound playback is not supported
    }
  }
}
