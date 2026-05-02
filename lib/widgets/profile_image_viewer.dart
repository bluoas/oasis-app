import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-Screen Profile Image Viewer (based on ImageViewer but for profile photos)
/// 
/// Features:
/// - AppBar with "Profile Photo" title
/// - Bottom bar with "Change" and "Remove" actions
/// - Tap to toggle UI visibility
/// - Pinch to zoom (1x-10x)
/// - Double tap to zoom in/out
/// - Hero animation transition
/// 
/// Usage:
/// ```dart
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (context) => ProfileImageViewer(
///       imagePath: '/path/to/profile.jpg',
///       userName: 'Alice',
///       onChangePhoto: () => pickNewPhoto(),
///       onRemovePhoto: () => deletePhoto(),
///     ),
///   ),
/// );
/// ```
class ProfileImageViewer extends StatefulWidget {
  final String imagePath; // Path to profile image file
  final String userName; // User name for header
  final VoidCallback onChangePhoto; // Callback when user wants to change photo
  final VoidCallback onRemovePhoto; // Callback when user wants to remove photo
  final String? heroTag; // Optional hero tag for animation

  const ProfileImageViewer({
    super.key,
    required this.imagePath,
    required this.userName,
    required this.onChangePhoto,
    required this.onRemovePhoto,
    this.heroTag,
  });

  @override
  State<ProfileImageViewer> createState() => _ProfileImageViewerState();
}

class _ProfileImageViewerState extends State<ProfileImageViewer> with SingleTickerProviderStateMixin {
  final TransformationController _transformationController = TransformationController();
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  
  bool _isZoomed = false;
  bool _showControls = true; // Toggle for AppBar/BottomBar visibility
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    
    // Listen to transformation changes to detect zoom level
    _transformationController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final wasZoomed = _isZoomed;
    _isZoomed = scale > 1.05;
    
    // Update UI when zoom state changes
    if (wasZoomed != _isZoomed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  void _handleDoubleTap() {
    final newScale = _isZoomed ? 1.0 : 2.5;
    
    final Matrix4 endMatrix = Matrix4.identity()..scale(newScale);
    
    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: endMatrix,
    ).animate(
      CurveTween(curve: Curves.easeInOut).animate(_animationController),
    );
    
    _animationController.forward(from: 0).then((_) {
      _animation = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final imageFile = File(widget.imagePath);
    
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      extendBody: true,
      
      // AppBar with profile info
      appBar: _showControls
          ? AppBar(
              backgroundColor: Colors.black.withOpacity(0.7),
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Profile Photo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    widget.userName,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          : null,
      
      // Bottom bar with actions
      bottomNavigationBar: _showControls
          ? Container(
              color: Colors.black.withOpacity(0.7),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Change photo button
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onChangePhoto();
                        },
                        icon: const Icon(Icons.edit, color: Colors.white),
                        label: const Text(
                          'Change Photo',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                      // Remove photo button
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          widget.onRemovePhoto();
                        },
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        label: const Text(
                          'Remove',
                          style: TextStyle(color: Colors.red),
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
      
      body: GestureDetector(
        onTap: () {
          // Toggle controls visibility on tap (only when not zoomed)
          if (!_isZoomed) {
            setState(() {
              _showControls = !_showControls;
            });
          }
        },
        onVerticalDragUpdate: !_isZoomed ? (details) {
          // Swipe down to dismiss (only when not zoomed)
          if (details.delta.dy > 5) {
            Navigator.pop(context);
          }
        } : null,
        onDoubleTap: _handleDoubleTap,
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            if (_animation != null) {
              _transformationController.value = _animation!.value;
            }
            return InteractiveViewer(
              transformationController: _transformationController,
              minScale: 1.0,
              maxScale: 10.0,
              panEnabled: true,
              scaleEnabled: true,
              child: Center(
                child: widget.heroTag != null
                    ? Hero(
                        tag: widget.heroTag!,
                        child: Image.file(
                          imageFile,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.broken_image,
                                    size: 64,
                                    color: Colors.white54,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'Failed to load image',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                    : Image.file(
                        imageFile,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.broken_image,
                                  size: 64,
                                  color: Colors.white54,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}
