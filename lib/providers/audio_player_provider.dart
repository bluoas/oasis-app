import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import '../utils/logger.dart';

/// Audio Player Manager - Ensures only one audio plays at a time
/// 
/// Usage:
/// ```dart
/// // In AudioMessageBubble:
/// ref.read(audioPlayerManagerProvider.notifier).registerPlayer(_audioPlayer);
/// 
/// // When starting playback:
/// ref.read(audioPlayerManagerProvider.notifier).setCurrentPlayer(_audioPlayer);
/// ```

class AudioPlayerManager extends StateNotifier<AudioPlayer?> {
  AudioPlayerManager() : super(null);

  /// Set the currently playing audio player
  /// Automatically pauses the previous player if different
  Future<void> setCurrentPlayer(AudioPlayer newPlayer) async {
    if (state != null && state != newPlayer) {
      // Pause the previous player
      try {
        await state!.pause();
      } catch (e) {
        Logger.warning('Failed to pause previous audio: $e');
      }
    }
    state = newPlayer;
  }

  /// Clear the current player (called when audio completes or is paused)
  void clearCurrentPlayer(AudioPlayer player) {
    if (state == player) {
      state = null;
    }
  }

  /// Stop all audio playback
  Future<void> stopAll() async {
    if (state != null) {
      try {
        await state!.stop();
      } catch (e) {
        Logger.warning('Failed to stop audio: $e');
      }
      state = null;
    }
  }
}

/// Global audio player manager provider
final audioPlayerManagerProvider = StateNotifierProvider<AudioPlayerManager, AudioPlayer?>((ref) {
  return AudioPlayerManager();
});
