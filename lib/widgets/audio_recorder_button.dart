import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/top_notification.dart';
import '../utils/logger.dart';

/// Audio Recorder Button - Hold to record, Release to send
/// 
/// Usage:
/// ```dart
/// AudioRecorderButton(
///   onAudioRecorded: (path, duration, waveform) {
///     print('Audio recorded: $path (${duration}s) with ${waveform.length} samples');
///   },
/// )
/// ```
class AudioRecorderButton extends StatefulWidget {
  final Function(String audioPath, Duration duration, List<double> waveform) onAudioRecorded;
  final VoidCallback? onRecordingStarted;
  final VoidCallback? onRecordingCancelled;
  final bool autoStart; // Automatically start recording when widget is mounted

  const AudioRecorderButton({
    super.key,
    required this.onAudioRecorded,
    this.onRecordingStarted,
    this.onRecordingCancelled,
    this.autoStart = false,
  });

  @override
  State<AudioRecorderButton> createState() => _AudioRecorderButtonState();
}

class _AudioRecorderButtonState extends State<AudioRecorderButton>
    with SingleTickerProviderStateMixin {
  final _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;
  DateTime? _recordingStartTime;
  Timer? _durationTimer;
  Duration _currentDuration = Duration.zero;
  late AnimationController _animationController;
  
  // Real-time amplitude tracking for waveform visualization
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  final List<double> _amplitudeHistory = [];
  static const int _maxAmplitudeHistoryLength = 50; // Keep last 50 samples

  @override
  void initState() {
    super.initState();
    
    // If autoStart is true, set recording state immediately so UI shows recording interface
    _isRecording = widget.autoStart;
    
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);    
    // Auto-start recording if requested
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startRecording();
      });
    }  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _amplitudeSubscription?.cancel();
    _audioRecorder.dispose();
    _animationController.dispose();
    super.dispose();
  }



  Future<void> _startRecording() async {
    try {
      // Check permission using native record package
      final hasPermission = await _audioRecorder.hasPermission();
      Logger.debug('🎤 Native permission check: $hasPermission');
      
      if (!hasPermission) {
        Logger.debug('🎤 No permission - start() will request it automatically');
      }

      // Generate persistent file path
      final appSupportDir = await getApplicationSupportDirectory();
      final audioDir = Directory('${appSupportDir.path}/audio');
      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _recordingPath = '${audioDir.path}/audio_$timestamp.m4a';

      // Start recording (this will automatically request permission if needed)
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc, // AAC for iOS/Android compatibility
          bitRate: 64000,  // 64 kbps - optimized for voice messages (was 128000)
          sampleRate: 22050, // 22 kHz - sufficient for speech (was 44100)
        ),
        path: _recordingPath!,
      );

      if (!mounted) return;

      setState(() {
        _isRecording = true;
        _recordingStartTime = DateTime.now();
        _currentDuration = Duration.zero;
        _amplitudeHistory.clear(); // Reset amplitude history
      });

      // Subscribe to amplitude changes for real-time waveform
      _amplitudeSubscription = _audioRecorder.onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amplitude) {
        if (mounted && _isRecording) {
          setState(() {
            // Normalize amplitude to 0.0-1.0 range
            // Current amplitude is typically between -160 dB (silence) and 0 dB (max)
            final normalizedAmplitude = ((amplitude.current + 50) / 50).clamp(0.0, 1.0);
            
            _amplitudeHistory.add(normalizedAmplitude);
            
            // Keep only last N samples
            if (_amplitudeHistory.length > _maxAmplitudeHistoryLength) {
              _amplitudeHistory.removeAt(0);
            }
          });
        }
      });

      // Start duration timer
      _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_recordingStartTime != null && mounted) {
          setState(() {
            _currentDuration = DateTime.now().difference(_recordingStartTime!);
          });

          // Auto-stop at 5 minutes
          if (_currentDuration.inMinutes >= 5) {
            _stopRecording();
          }
        }
      });

      widget.onRecordingStarted?.call();
      Logger.debug('Recording started: $_recordingPath');
    } catch (e) {
      Logger.error('Error starting recording', e);
      if (mounted) {
        showTopNotification(
          context,
          'Failed to start recording: $e',
          isError: true,
        );
        setState(() {
          _isRecording = false;
        });
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    try {
      final path = await _audioRecorder.stop();
      _durationTimer?.cancel();
      _amplitudeSubscription?.cancel();

      if (path != null && _recordingStartTime != null) {
        final duration = DateTime.now().difference(_recordingStartTime!);
        
        // Only send if recording is longer than 1 second
        if (duration.inSeconds >= 1) {
          // Save waveform data before clearing
          final waveformData = List<double>.from(_amplitudeHistory);
          
          widget.onAudioRecorded(path, duration, waveformData);
          Logger.success('Recording stopped: $path (${duration.inSeconds}s, ${waveformData.length} waveform samples)');
        } else {
          // Delete too short recording
          try {
            await File(path).delete();
          } catch (e) {
            Logger.warning('Failed to delete short recording: $e');
          }
          if (mounted) {
            showTopNotification(
              context,
              'Recording too short (min. 1 second)',
              duration: const Duration(seconds: 2),
              isError: true,
            );
          }
        }
      }
    } catch (e) {
      Logger.error('Error stopping recording', e);
    } finally {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordingStartTime = null;
          _currentDuration = Duration.zero;
          _amplitudeHistory.clear();
        });
      }
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;

    try {
      final path = await _audioRecorder.stop();
      _durationTimer?.cancel();
      _amplitudeSubscription?.cancel();

      // Delete cancelled recording
      if (path != null) {
        try {
          await File(path).delete();
        } catch (e) {
          Logger.warning('Failed to delete cancelled recording: $e');
        }
      }

      widget.onRecordingCancelled?.call();
      Logger.debug('🗑️ Recording cancelled');
    } catch (e) {
      Logger.error('Error cancelling recording', e);
    } finally {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _recordingStartTime = null;
          _currentDuration = Duration.zero;
          _amplitudeHistory.clear();
        });
      }
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
    if (_isRecording) {
      return _buildRecordingUI();
    }

    return _buildRecordButton();
  }

  Widget _buildRecordButton() {
    return GestureDetector(
      onTapDown: (_) => _startRecording(),
      onTapUp: (_) => _stopRecording(),
      onTapCancel: () => _cancelRecording(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.mic,
          color: Theme.of(context).colorScheme.primary,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildRecordingUI() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          // Cancel button
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _cancelRecording,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          
          const SizedBox(width: 8),
          
          // Recording indicator (pulsing red dot)
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.3 + _animationController.value * 0.7),
                  shape: BoxShape.circle,
                ),
              );
            },
          ),
          
          const SizedBox(width: 12),
          
          // Duration
          Text(
            _formatDuration(_currentDuration),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Real-time waveform visualization from actual audio amplitudes
          Expanded(
            child: Container(
              height: 24,
              child: _amplitudeHistory.isEmpty
                  ? const SizedBox.shrink()
                  : CustomPaint(
                      painter: WaveformPainter(
                        amplitudes: _amplitudeHistory,
                        color: Colors.red,
                      ),
                    ),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Send button
          GestureDetector(
            onTap: _stopRecording,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for real-time audio waveform visualization
/// Renders amplitude values as vertical bars
class WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final Color color;

  WaveformPainter({
    required this.amplitudes,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final barWidth = 3.0;
    final spacing = 2.0;
    final totalBarWidth = barWidth + spacing;
    final maxBars = (size.width / totalBarWidth).floor();
    
    // Take the last N bars that fit in the available width
    final visibleAmplitudes = amplitudes.length > maxBars
        ? amplitudes.sublist(amplitudes.length - maxBars)
        : amplitudes;

    for (int i = 0; i < visibleAmplitudes.length; i++) {
      final amplitude = visibleAmplitudes[i];
      final x = i * totalBarWidth;
      
      // Scale amplitude to height (minimum 4px, maximum full height)
      final barHeight = (amplitude * size.height * 0.8) + (size.height * 0.2);
      final y = (size.height - barHeight) / 2;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return oldDelegate.amplitudes != amplitudes;
  }
}
