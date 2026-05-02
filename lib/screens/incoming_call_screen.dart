import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/call.dart';
import '../models/contact.dart';
import '../providers/services_provider.dart';
import '../utils/logger.dart';
import 'active_call_screen.dart';

/// Incoming Call Screen - Full screen overlay for incoming calls
/// 
/// Shows:
/// - Caller name & avatar
/// - Call type (audio/video)
/// - Accept/Reject buttons
class IncomingCallScreen extends ConsumerWidget {
  final Call call;

  const IncomingCallScreen({
    super.key,
    required this.call,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callService = ref.watch(callServiceProvider);
    final storageService = ref.watch(storageServiceProvider);
    
    // Watch current call state - auto-close if call ended/rejected
    final currentCall = ref.watch(currentCallProvider).valueOrNull;
    
    // Auto-close screen if call ended, rejected, or removed
    if (currentCall == null || 
        currentCall.state == CallState.ended || 
        currentCall.state == CallState.rejected ||
        currentCall.id != call.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: PopScope(
        canPop: true,
        onPopInvoked: (didPop) async {
          // If user dismisses screen (back button, swipe, etc.), reject the call
          // Only reject if call is still in ringing state (not already rejected/accepted)
          if (didPop && currentCall.state == CallState.ringing) {
            Logger.info('📞 Screen dismissed, rejecting call from ${call.contactName}');
            // Don't await - let it run in background to avoid blocking navigation
            callService.rejectCall(call);
          }
        },
        child: SafeArea(
          child: FutureBuilder(
            future: storageService.getContact(call.contactId),
            builder: (context, snapshot) {
              Logger.debug('[IncomingCall] FutureBuilder state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}');
              
              // Extract contact data once
              Contact? contact;
              if (snapshot.hasData && snapshot.data!.isSuccess) {
                contact = snapshot.data!.valueOrNull;
                Logger.debug('[IncomingCall] Contact loaded: ${contact?.displayName}, profileImagePath: ${contact?.profileImagePath}');
              } else if (snapshot.hasData) {
                Logger.warning('[IncomingCall] Contact load failed: ${snapshot.data!.errorOrNull}');
              }
              
              final displayName = contact?.displayName ?? call.contactName;
              Logger.debug('[IncomingCall] Displaying name: $displayName');
            
              return Column(
                children: [
                  const SizedBox(height: 60),
                  
                  // Call type indicator
                  Text(
                    'Incoming ${call.type.displayName}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Avatar with contact profile image
                  _ContactAvatar(
                    contact: contact,
                    radius: 80,
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Caller name (display name from contact)
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Ringing indicator
                  Text(
                    'is calling...',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  
                  const Spacer(),
                  
                  // Action buttons
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Reject button
                        _CallActionButton(
                          icon: Icons.call_end,
                          label: 'Reject',
                          color: Colors.red,
                          onPressed: () async {
                            Logger.info('📞 Rejecting call from ${call.contactName}');
                            await callService.rejectCall(call);
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                        
                        // Accept button
                        _CallActionButton(
                          icon: Icons.call,
                          label: 'Accept',
                          color: Colors.green,
                          onPressed: () async {
                            Logger.info('📞 Accepting call from ${call.contactName}');
                            try {
                              await callService.acceptCall(call);
                              if (context.mounted) {
                                // Navigate to active call screen
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => const ActiveCallScreen(),
                                  ),
                                );
                              }
                            } catch (e) {
                              Logger.error('❌ Failed to accept call: $e');
                              if (context.mounted) {
                                // Just pop back - don't show SnackBar to avoid layout issues
                                Navigator.of(context).pop();
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Call Action Button - Circular button with icon and label
class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
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
              width: 72,
              height: 72,
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 36,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ],
    );
  }
}

/// Contact Avatar - Shows profile image if available, fallback to icon
class _ContactAvatar extends StatelessWidget {
  final Contact? contact;
  final double radius;

  const _ContactAvatar({
    this.contact,
    required this.radius,
  });

  Future<ImageProvider?> _loadProfileImage() async {
    Logger.debug('[IncomingCallAvatar] Loading profile image for contact: ${contact?.displayName}');
    
    if (contact?.profileImagePath == null) {
      Logger.debug('[IncomingCallAvatar] No profileImagePath, showing default icon');
      return null;
    }
    
    try {
      final imagePath = contact!.profileImagePath!;
      Logger.debug('[IncomingCallAvatar] Profile image path: $imagePath');
      
      File imageFile;
      
      // Check if path is absolute
      if (imagePath.startsWith('/')) {
        imageFile = File(imagePath);
        Logger.debug('[IncomingCallAvatar] Using absolute path: ${imageFile.path}');
      } else {
        // Relative path - get app documents directory
        final dir = await getApplicationSupportDirectory();
        imageFile = File('${dir.path}/$imagePath');
        Logger.debug('[IncomingCallAvatar] Using relative path: ${imageFile.path}');
      }
      
      final exists = await imageFile.exists();
      Logger.debug('[IncomingCallAvatar] File exists: $exists at ${imageFile.path}');
      
      if (exists) {
        Logger.success('[IncomingCallAvatar] Loading image from ${imageFile.path}');
        return FileImage(imageFile);
      } else {
        Logger.warning('[IncomingCallAvatar] Image file not found at ${imageFile.path}');
      }
    } catch (e, stackTrace) {
      Logger.error('[IncomingCallAvatar] Failed to load profile image: $e', stackTrace);
    }
    
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ImageProvider?>(
      future: _loadProfileImage(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done && snapshot.data != null) {
          return CircleAvatar(
            radius: radius,
            backgroundImage: snapshot.data,
          );
        }
        
        // Fallback to default icon (while loading or if no image)
        return CircleAvatar(
          radius: radius,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.person,
            size: radius * 0.8,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        );
      },
    );
  }
}
