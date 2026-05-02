import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/call.dart';
import '../models/contact.dart';
import '../providers/services_provider.dart';
import '../utils/logger.dart';

/// Active Call Screen - Shows ongoing call with controls
/// 
/// Features:
/// - Call duration timer
/// - Mute/Unmute button
/// - Speaker on/off button
/// - End call button
/// - Contact info
class ActiveCallScreen extends ConsumerStatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen> {
  @override
  Widget build(BuildContext context) {
    final callAsync = ref.watch(currentCallProvider);

    return callAsync.when(
      data: (call) {
        if (call == null || call.state.isEnded) {
          // No active call, close screen
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const SizedBox.shrink();
        }

        return _ActiveCallContent(call: call);
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => Scaffold(
        body: Center(
          child: Text('Error: $error'),
        ),
      ),
    );
  }
}

class _ActiveCallContent extends ConsumerStatefulWidget {
  final Call call;

  const _ActiveCallContent({required this.call});

  @override
  ConsumerState<_ActiveCallContent> createState() => _ActiveCallContentState();
}

class _ActiveCallContentState extends ConsumerState<_ActiveCallContent> {
  Contact? _cachedContact;
  ImageProvider? _cachedProfileImage;

  @override
  void initState() {
    super.initState();
    _loadContact();
  }

  Future<void> _loadContact() async {
    final storageService = ref.read(storageServiceProvider);
    final result = await storageService.getContact(widget.call.contactId);
    
    if (result.isSuccess) {
      _cachedContact = result.valueOrNull;
      Logger.debug('[ActiveCall] Contact cached: ${_cachedContact?.displayName}, profileImagePath: ${_cachedContact?.profileImagePath}');
      
      // Load profile image once and cache it
      await _loadProfileImage();
    } else {
      Logger.warning('[ActiveCall] Contact load failed: ${result.errorOrNull}');
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadProfileImage() async {
    if (_cachedContact?.profileImagePath == null) {
      Logger.debug('[ActiveCall] No profileImagePath, using default icon');
      return;
    }
    
    try {
      final imagePath = _cachedContact!.profileImagePath!;
      Logger.debug('[ActiveCall] Profile image path: $imagePath');
      
      File imageFile;
      
      if (imagePath.startsWith('/')) {
        imageFile = File(imagePath);
      } else {
        final dir = await getApplicationSupportDirectory();
        imageFile = File('${dir.path}/$imagePath');
      }
      
      final exists = await imageFile.exists();
      Logger.debug('[ActiveCall] File exists: $exists at ${imageFile.path}');
      
      if (exists) {
        _cachedProfileImage = FileImage(imageFile);
        Logger.success('[ActiveCall] Profile image cached');
      } else {
        Logger.warning('[ActiveCall] Image file not found at ${imageFile.path}');
      }
    } catch (e, stackTrace) {
      Logger.error('[ActiveCall] Failed to load profile image: $e', stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    final callService = ref.watch(callServiceProvider);
    final displayName = _cachedContact?.displayName ?? widget.call.contactName;
    
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            
            // Call state indicator
            Text(
              _getCallStateText(widget.call.state),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                ),
            
            const SizedBox(height: 24),
            
            // Avatar with cached profile image
            CircleAvatar(
              radius: 80,
              backgroundImage: _cachedProfileImage,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: _cachedProfileImage == null
                  ? Icon(
                      Icons.person,
                      size: 64,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    )
                  : null,
            ),
            
            const SizedBox(height: 16),
            
            // Contact name
            Text(
              displayName,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            
            const SizedBox(height: 16),
            
            // Call duration timer
            if (widget.call.state == CallState.connected && widget.call.duration != null)
              Text(
                _formatDuration(widget.call.duration!),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
              ),
            
            const Spacer(),
            
            // Call controls
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mute & Speaker buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Mute button
                      _CallControlButton(
                        icon: widget.call.isMuted ? Icons.mic_off : Icons.mic,
                        label: widget.call.isMuted ? 'Unmute' : 'Mute',
                        isActive: widget.call.isMuted,
                        onPressed: () async {
                          await callService.toggleMute();
                        },
                      ),
                      
                      // Speaker button
                      _CallControlButton(
                        icon: widget.call.isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                        label: widget.call.isSpeakerOn ? 'Speaker On' : 'Speaker Off',
                        isActive: widget.call.isSpeakerOn,
                        onPressed: () async {
                          await callService.toggleSpeaker();
                        },
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // End call button
                  Material(
                    color: Colors.red,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () async {
                        Logger.info('📞 Ending call with ${widget.call.contactName}');
                        await callService.endCall();
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 72,
                        height: 72,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.call_end,
                          size: 36,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  Text(
                    'End Call',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.red,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getCallStateText(CallState state) {
    switch (state) {
      case CallState.initiating:
        return 'Initiating...';
      case CallState.ringing:
        return 'Ringing...';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.connected:
        return 'Connected';
      case CallState.ending:
        return 'Ending...';
      default:
        return '';
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }
}

/// Call Control Button - Circular button with icon and label
class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onPressed;

  const _CallControlButton({
    required this.icon,
    required this.label,
    this.isActive = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final iconColor = isActive
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 32,
                color: iconColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}
