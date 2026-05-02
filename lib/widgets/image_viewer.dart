import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:gal/gal.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/top_notification.dart';

/// Full-Screen Image Viewer with WhatsApp-style UI
/// 
/// Features:
/// - AppBar with sender name and timestamp
/// - Bottom bar with save/forward actions
/// - Tap to toggle UI visibility
/// - Pinch to zoom (1x-10x)
/// - Pan/drag to move zoomed image
/// - Double tap to zoom in/out
/// - Hero animation transition
/// 
/// Usage:
/// ```dart
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (context) => ImageViewer(
///       imagePath: '/path/to/image.jpg',
///       senderName: 'Alice',
///       timestamp: DateTime.now(),
///       heroTag: 'image_$messageId',
///     ),
///   ),
/// );
/// ```
class ImageViewer extends StatefulWidget {
  final String imagePath; // Path to image file
  final String senderName; // Sender name for header
  final DateTime timestamp; // Message timestamp
  final bool isMe; // Is this from me?
  final String? heroTag; // Optional hero tag for animation
  final String? caption; // Optional caption to display

  const ImageViewer({
    super.key,
    required this.imagePath,
    required this.senderName,
    required this.timestamp,
    this.isMe = false,
    this.heroTag,
    this.caption,
  });

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> with SingleTickerProviderStateMixin {
  final TransformationController _transformationController = TransformationController();
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  
  bool _isZoomed = false;
  bool _showControls = true; // Toggle for AppBar/BottomBar visibility
  bool _isSavedToGallery = false; // Track if image was already saved
  String? _imageHash; // SHA256 hash of the image
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    
    // Listen to transformation changes to detect zoom level
    _transformationController.addListener(_onTransformChanged);
    
    // Check if image was already saved to gallery
    _checkIfAlreadySaved();
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
    
    // Update UI when zoom state changes (schedule after current frame to avoid setState during build)
    if (wasZoomed != _isZoomed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  /// Check if image was already saved to gallery using hash
  Future<void> _checkIfAlreadySaved() async {
    try {
      final imageFile = File(widget.imagePath);
      if (!await imageFile.exists()) return;
      
      // Calculate SHA256 hash of image
      final bytes = await imageFile.readAsBytes();
      final digest = sha256.convert(bytes);
      _imageHash = digest.toString();
      
      // Check SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedImages = prefs.getStringList('saved_images') ?? [];
      
      if (mounted && savedImages.contains(_imageHash)) {
        setState(() {
          _isSavedToGallery = true;
        });
      }
    } catch (e) {
      // Ignore errors during check
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

  /// Save image to device gallery
  Future<void> _saveToGallery() async {
    // Check if already saved - show confirmation dialog
    if (_isSavedToGallery) {
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Image Already Saved'),
          content: const Text(
            'This image has already been saved to your gallery. '
            'Do you want to save it again?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save Again'),
            ),
          ],
        ),
      );
      
      if (shouldSave != true) return;
    }
    
    try {
      // Read image file as bytes
      final imageFile = File(widget.imagePath);
      if (!await imageFile.exists()) {
        throw Exception('Image file not found');
      }
      
      final bytes = await imageFile.readAsBytes();
      
      // Calculate hash if not already done
      if (_imageHash == null) {
        final digest = sha256.convert(bytes);
        _imageHash = digest.toString();
      }
      
      // Save to gallery using gal
      await Gal.putImageBytes(bytes);
      
      if (!mounted) return;
      
      // Save hash to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final savedImages = prefs.getStringList('saved_images') ?? [];
      if (_imageHash != null && !savedImages.contains(_imageHash)) {
        savedImages.add(_imageHash!);
        await prefs.setStringList('saved_images', savedImages);
      }
      
      setState(() {
        _isSavedToGallery = true;
      });
      
      showTopNotification(
        context,
        'Image saved to gallery',
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      
      showTopNotification(
        context,
        'Failed to save image: $e',
        duration: const Duration(seconds: 3),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageFile = File(widget.imagePath);
    
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      extendBody: true,
      
      // AppBar with sender info
      appBar: _showControls
          ? AppBar(
              backgroundColor: Colors.black.withOpacity(0.7),
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.senderName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    DateFormat('dd.MM.yyyy • HH:mm').format(widget.timestamp.toLocal()),
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
                      IconButton(
                        icon: Icon(
                          _isSavedToGallery ? Icons.check_circle : Icons.save_alt,
                          color: Colors.white,
                        ),
                        iconSize: 28,
                        onPressed: _saveToGallery,
                        tooltip: _isSavedToGallery ? 'Already saved' : 'Save to gallery',
                      ),
                      IconButton(
                        icon: const Icon(Icons.share, color: Colors.white),
                        iconSize: 28,
                        onPressed: () {
                          // TODO: Implement forward/share
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Forward coming soon'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        tooltip: 'Forward',
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
        child: Stack(
          children: [
            // Image with zoom/pan
            AnimatedBuilder(
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
            
            // Caption overlay (above bottom bar)
            if (widget.caption != null && widget.caption!.isNotEmpty)
              Positioned(
                bottom: _showControls ? 120 : 20,
                left: 16,
                right: 16,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.caption!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
