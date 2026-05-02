import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/audio_player_provider.dart';
import '../utils/top_notification.dart';
import '../utils/logger.dart';

/// Audio Message Bubble - Displays audio message with playback controls
/// 
/// Usage:
/// ```dart
/// AudioMessageBubble(
///   audioPath: '/path/to/audio.m4a',
///   duration: Duration(seconds: 15),
///   timestamp: DateTime.now(),
///   isMe: true,
///   waveform: [0.3, 0.5, 0.8, ...], // Optional visualization data
/// )
/// ```
class AudioMessageBubble extends ConsumerStatefulWidget {
  final String audioPath; // Local file path or decrypted audio data path
  final Duration duration; // Total duration of audio
  final DateTime timestamp;
  final bool isMe;
  final List<double>? waveform; // Optional waveform visualization data
  final VoidCallback? onPlayError;
  final VoidCallback? onLongPress; // Long press handler for context menu
  final dynamic deliveryStatus; // DeliveryStatus enum (import would cause circular dependency)
  final String? replyToMessageId; // Reply functionality
  final String? replyToPreviewText;
  final String? replyToContentType; // ContentType as string to avoid circular dependency
  final String? replyToSenderName; // Name of person who sent the original message
  final bool isHighlighted; // Whether this message is currently highlighted
  final double highlightOpacity; // Opacity for smooth highlight animation (0.0-1.0)
  final VoidCallback? onReplyTap; // Callback when tapping on reply indicator

  const AudioMessageBubble({
    super.key,
    required this.audioPath,
    required this.duration,
    required this.timestamp,
    required this.isMe,
    this.waveform,
    this.onPlayError,
    this.onLongPress,
    this.deliveryStatus,
    this.replyToMessageId,
    this.replyToPreviewText,
    this.replyToContentType,
    this.replyToSenderName,
    this.isHighlighted = false,
    this.highlightOpacity = 0.0,
    this.onReplyTap,
  });

  @override
  ConsumerState<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends ConsumerState<AudioMessageBubble> {
  final _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isLoading = false;
  
  // Stream subscriptions for proper cleanup
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<void>? _completeSubscription;

  @override
  void initState() {
    super.initState();
    _totalDuration = widget.duration;
    _setupAudioPlayer();
  }

  @override
  void dispose() {
    // Clear this player from the manager if it's the current one
    // Wrap in try-catch because ref might not be available during dispose
    try {
      ref.read(audioPlayerManagerProvider.notifier).clearCurrentPlayer(_audioPlayer);
    } catch (e) {
      // Widget already disposed, ignore
    }
    
    // Cancel all stream subscriptions FIRST to prevent any callbacks
    _playerStateSubscription?.cancel();
    _playerStateSubscription = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _durationSubscription?.cancel();
    _durationSubscription = null;
    _completeSubscription?.cancel();
    _completeSubscription = null;
    
    // Then dispose the audio player
    _audioPlayer.dispose();
    
    // Finally call super.dispose()
    super.dispose();
  }

  void _setupAudioPlayer() {
    // Listen to player state
    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    // Listen to position changes
    _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });

    // Listen to duration changes (in case widget.duration is inaccurate)
    _durationSubscription = _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted && duration.inSeconds > 0) {
        setState(() {
          _totalDuration = duration;
        });
      }
    });

    // Reset when playback completes
    _completeSubscription = _audioPlayer.onPlayerComplete.listen((_) async {
      if (mounted) {
        // Stop the player explicitly to prevent position updates after completion
        await _audioPlayer.stop();
        
        // Clear this player from the manager
        ref.read(audioPlayerManagerProvider.notifier).clearCurrentPlayer(_audioPlayer);
        
        setState(() {
          _isPlaying = false;
          _currentPosition = Duration.zero;
        });
      }
    });
  }

  Future<void> _togglePlayPause() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      if (_isPlaying) {
        await _audioPlayer.pause().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            Logger.warning('Audio pause timeout');
          },
        );
        // Clear this player from the manager when paused
        ref.read(audioPlayerManagerProvider.notifier).clearCurrentPlayer(_audioPlayer);
      } else {
        // Notify manager that this player is starting (stops any other playing audio)
        await ref.read(audioPlayerManagerProvider.notifier).setCurrentPlayer(_audioPlayer);
        
        // Reconstruct absolute path from relative path (iOS container changes on restart)
        String fullPath = widget.audioPath;
        if (!widget.audioPath.startsWith('/')) {
          // Relative path - reconstruct with current Application Support directory
          final appSupportDir = await getApplicationSupportDirectory();
          fullPath = '${appSupportDir.path}/${widget.audioPath}';
          Logger.debug('🎵 Reconstructed audio path: $fullPath');
        }
        
        // Check if file exists
        if (!await File(fullPath).exists()) {
          throw Exception('Audio file not found: $fullPath');
        }

        // Check if audio is completed or at position 0 - always play from start
        final playerState = _audioPlayer.state;
        final shouldPlayFromStart = _currentPosition.inSeconds == 0 || 
                                    playerState == PlayerState.completed ||
                                    playerState == PlayerState.stopped;

        if (shouldPlayFromStart) {
          await _audioPlayer.play(DeviceFileSource(fullPath)).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              Logger.warning('Audio play timeout');
            },
          );
        } else {
          // Resume from current position
          await _audioPlayer.resume().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              Logger.warning('Audio resume timeout');
            },
          );
        }
      }
    } catch (e) {
      Logger.error('Audio playback error', e);
      widget.onPlayError?.call();
      if (mounted) {
        showTopNotification(
          context,
          'Could not play audio: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _seekToPosition(double value) async {
    try {
      final position = Duration(milliseconds: (value * _totalDuration.inMilliseconds).round());
      await _audioPlayer.seek(position).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          Logger.warning('Audio seek timeout');
        },
      );
    } catch (e) {
      Logger.warning('Seek error: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = () {
      if (widget.highlightOpacity > 0) {
        final highlightColor = Theme.of(context).brightness == Brightness.dark
            ? Colors.amber
            : Colors.orange[200]!;
        return highlightColor.withOpacity(0.3 * widget.highlightOpacity);
      }
      return widget.isMe
          ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
          : (Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[800]!.withOpacity(0.3)
              : Colors.grey[400]!.withOpacity(0.2));
    }();

    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;

    final iconColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return GestureDetector(
      onLongPress: widget.onLongPress,
      child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
        minWidth: 200,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(widget.isMe ? 16 : 4),
          bottomRight: Radius.circular(widget.isMe ? 4 : 16),
        ),
        border: Border.all(
          color: widget.isMe
              ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
              : (Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[600]!.withOpacity(0.3)
                  : Colors.grey[400]!.withOpacity(0.3)),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reply indicator (if replying to another message)
          if (widget.replyToMessageId != null) ...[_buildReplyIndicator(), const SizedBox(height: 4)],
          // Audio controls row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Play/Pause button
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: _isLoading
                      ? Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(iconColor),
                          ),
                        )
                      : AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          switchInCurve: Curves.easeInOut,
                          switchOutCurve: Curves.easeInOut,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: child,
                            );
                          },
                          child: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            key: ValueKey<bool>(_isPlaying),
                            color: iconColor,
                            size: 24,
                          ),
                        ),
                ),
              ),

              const SizedBox(width: 8),

              // Waveform with duration below
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Waveform with integrated timeline (WhatsApp style)
                    SizedBox(
                      height: 32,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Waveform visualization with padding to match slider thumb
                          Positioned.fill(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: _buildWaveform(iconColor),
                            ),
                          ),
                          
                          // Integrated progress slider (transparent overlay, centered)
                          Positioned.fill(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: Colors.transparent,
                                inactiveTrackColor: Colors.transparent,
                                thumbColor: iconColor,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                trackHeight: 32,
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                              ),
                              child: Slider(
                                value: _totalDuration.inMilliseconds > 0
                                    ? (_currentPosition.inMilliseconds / _totalDuration.inMilliseconds)
                                        .clamp(0.0, 1.0)
                                    : 0.0,
                                onChanged: (value) => _seekToPosition(value),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 2),
                    
                    // Duration and Timestamp on same line below waveform
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Duration (left)
                        Text(
                          _formatDuration(_isPlaying ? _currentPosition : _totalDuration),
                          style: TextStyle(
                            fontSize: 10,
                            color: textColor.withOpacity(0.7),
                            decoration: TextDecoration.none,
                          ),
                        ),
                        // Timestamp with checkmark (right)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat('HH:mm').format(widget.timestamp.toLocal()),
                              style: TextStyle(
                                fontSize: 10,
                                color: textColor.withOpacity(0.7),
                                decoration: TextDecoration.none,
                              ),
                            ),
                            if (widget.isMe && widget.deliveryStatus?.toString() == 'DeliveryStatus.sent') ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.check,
                                size: 14,
                                color: textColor.withOpacity(0.7),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 4),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildReplyIndicator() {
    return GestureDetector(
      onTap: widget.onReplyTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
        decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: widget.isMe 
                ? (Theme.of(context).brightness == Brightness.dark
                    ? Colors.amber.withOpacity(0.9)
                    : Colors.orange[800]!)
                : Colors.grey.withOpacity(0.7),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.replyToSenderName ?? 'Message',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: widget.isMe 
                  ? (Theme.of(context).brightness == Brightness.dark
                      ? Colors.amber
                      : Colors.orange[800]!)
                  : (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withOpacity(0.8)
                      : Colors.black87),
              decoration: TextDecoration.none,
            ),
          ),
          Text(
            widget.replyToPreviewText ?? '',
            style: TextStyle(
              fontSize: 10,
              color: (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black87).withOpacity(0.6),
              decoration: TextDecoration.none,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildWaveform(Color color) {
    // Guard against race conditions during navigation/disposal
    if (!mounted) {
      return const SizedBox.shrink();
    }
    
    // Use real waveform data if available, otherwise fallback to pseudo-random
    // Make a local copy to prevent race conditions if widget.waveform changes during build
    final List<double> waveformData;
    final waveformSnapshot = widget.waveform;
    
    if (waveformSnapshot != null && waveformSnapshot.isNotEmpty) {
      // Use real recorded waveform (make defensive copy)
      waveformData = List<double>.from(waveformSnapshot);
    } else {
      // Fallback: Generate pseudo-random heights for visual effect
      final barCount = 40;
      waveformData = List.generate(barCount, (index) {
        final seed = widget.audioPath.hashCode + index;
        return 0.3 + ((seed % 70) / 100.0); // 0.3-1.0 range
      });
    }
    
    final barCount = waveformData.length;
    
    // Guard against empty waveform data
    if (barCount == 0) {
      return const SizedBox.shrink();
    }
    
    // Use the same normalized progress value as the slider for perfect sync
    final progress = _totalDuration.inMilliseconds > 0
        ? (_currentPosition.inMilliseconds / _totalDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final playedBars = (progress * barCount).floor().clamp(0, barCount);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(barCount, (index) {
        // Defensive: ensure index is within bounds
        if (index >= waveformData.length) {
          return const SizedBox.shrink();
        }
        
        // Map normalized amplitude (0.0-1.0) to height (8-24px)
        final normalizedAmplitude = waveformData[index].clamp(0.0, 1.0);
        final height = 8 + (normalizedAmplitude * 16); // 8-24px heights
        
        final isPlayed = index < playedBars;
        
        return Container(
          width: 2,
          height: height,
          decoration: BoxDecoration(
            color: color.withOpacity(isPlayed ? 1.0 : 0.3),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}
