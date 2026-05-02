import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import '../models/message.dart';
import 'image_viewer.dart';
import '../utils/logger.dart';

/// Image Message Bubble - Shows encrypted/decrypted images in chat
/// 
/// Features:
/// - Shows image thumbnail
/// - Loading state while decrypting
/// - Delivery status (sent, pending, failed)
/// - Timestamp
/// - Tap to open full-screen viewer
/// 
/// Usage:
/// ```dart
/// ImageMessageBubble(
///   imagePath: '/path/to/decrypted/image.jpg',
///   timestamp: DateTime.now(),
///   isMe: true,
///   deliveryStatus: DeliveryStatus.sent,
/// )
/// ```
class ImageMessageBubble extends StatefulWidget {
  final String messageId; // Message ID for hero tag
  final String imagePath; // Path to decrypted image file
  final DateTime timestamp;
  final bool isMe;
  final String senderName; // Sender name for viewer header
  final DeliveryStatus deliveryStatus;
  final String? caption; // Optional text caption
  final VoidCallback? onTap;
  final VoidCallback? onLongPress; // Long press handler for context menu
  final VoidCallback? onLoadError;
  final String? replyToMessageId; // Reply functionality
  final String? replyToPreviewText;
  final String? replyToContentType; // ContentType as string to avoid circular dependency
  final String? replyToSenderName; // Name of person who sent the original message
  final bool isHighlighted; // Whether this message is currently highlighted
  final double highlightOpacity; // Opacity for smooth highlight animation (0.0-1.0)
  final VoidCallback? onReplyTap; // Callback when tapping on reply indicator

  const ImageMessageBubble({
    super.key,
    required this.messageId,
    required this.imagePath,
    required this.timestamp,
    required this.isMe,
    required this.senderName,
    required this.deliveryStatus,
    this.caption,
    this.onTap,
    this.onLongPress,
    this.onLoadError,
    this.replyToMessageId,
    this.replyToPreviewText,
    this.replyToContentType,
    this.replyToSenderName,
    this.isHighlighted = false,
    this.highlightOpacity = 0.0,
    this.onReplyTap,
  });

  @override
  State<ImageMessageBubble> createState() => _ImageMessageBubbleState();
}

class _ImageMessageBubbleState extends State<ImageMessageBubble> {
  bool _isLoading = true;
  bool _hasError = false;
  File? _imageFile;
  double? _imageAspectRatio; // Store image aspect ratio

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(ImageMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // Resolve relative path to absolute
      String absolutePath = widget.imagePath;
      if (!absolutePath.startsWith('/')) {
        final appSupportDir = await getApplicationSupportDirectory();
        absolutePath = '${appSupportDir.path}/${widget.imagePath}';
      }
      
      final file = File(absolutePath);
      
      // Check if file exists
      if (!await file.exists()) {
        throw Exception('Image file not found: $absolutePath');
      }

      // Get image dimensions to calculate aspect ratio
      final imageBytes = await file.readAsBytes();
      final image = img.decodeImage(imageBytes);
      
      double aspectRatio = 1.0; // Default
      if (image != null) {
        aspectRatio = image.width / image.height;
      }

      if (!mounted) return;
      
      setState(() {
        _imageFile = file;
        _imageAspectRatio = aspectRatio;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('Error loading image', e);
      if (!mounted) return;
      
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
      
      widget.onLoadError?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: (!_isLoading && !_hasError && _imageFile != null) 
            ? () {
                if (widget.onTap != null) {
                  widget.onTap!();
                } else {
                  // Default: Open full-screen viewer
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ImageViewer(
                        imagePath: _imageFile!.path,
                        heroTag: 'image_${widget.messageId}',
                        senderName: widget.senderName,
                        timestamp: widget.timestamp,
                        caption: widget.caption,
                        isMe: widget.isMe,
                      ),
                    ),
                  );
                }
              }
            : null,
        onLongPress: widget.onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          decoration: BoxDecoration(
            color: () {
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
            }(),
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
              if (widget.replyToMessageId != null) ...[Padding(padding: const EdgeInsets.fromLTRB(8, 8, 8, 4), child: _buildReplyIndicator())],
              // Image content
              ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(widget.caption != null ? 0 : (widget.isMe ? 16 : 4)),
                  bottomRight: Radius.circular(widget.caption != null ? 0 : (widget.isMe ? 4 : 16)),
                ),
                child: _buildImageContent(),
              ),
              
              // Caption (if present)
              if (widget.caption != null && widget.caption!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Text(
                    widget.caption!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              
              // Timestamp and delivery status
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: _buildFooter(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageContent() {
    if (_isLoading) {
      return Container(
        width: 200,
        height: 200,
        color: widget.isMe
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.1),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Loading image...',
                style: TextStyle(
                  fontSize: 12,
                  color: (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87).withOpacity(0.7),
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasError || _imageFile == null) {
      return Container(
        width: 200,
        height: 200,
        color: widget.isMe
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.1),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.broken_image,
                size: 48,
                color: (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87).withOpacity(0.5),
              ),
              const SizedBox(height: 8),
              Text(
                'Failed to load image',
                style: TextStyle(
                  fontSize: 12,
                  color: (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87).withOpacity(0.7),
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show actual image
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
        maxHeight: 400, // Limit height for portrait images
      ),
      child: AspectRatio(
        aspectRatio: _getOptimalAspectRatio(),
        child: Hero(
          tag: 'image_${widget.messageId}',
          child: Image.file(
            _imageFile!,
            fit: BoxFit.cover, // Crop top/bottom for portrait images
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 200,
                height: 200,
                color: Colors.red.withOpacity(0.1),
                child: const Center(
                  child: Icon(Icons.broken_image, size: 48),
                ),
              );
            },
          ),
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

  /// Get optimal aspect ratio for display in chat
  /// - Portrait images (taller than 4:3): limit to 3:4 ratio to avoid being too tall
  /// - Other images: use original aspect ratio
  double _getOptimalAspectRatio() {
    if (_imageAspectRatio == null) {
      return 1.0; // Default square
    }
    
    // Portrait image (height > width * 1.3, e.g., 9:16)
    if (_imageAspectRatio! < 0.77) {
      return 3 / 4; // Limit to 3:4 ratio (crop top/bottom)
    }
    
    // Landscape or square: use original ratio
    return _imageAspectRatio!;
  }

  Widget _buildFooter() {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.end, // Always align timestamp to right
      children: [
        Text(
          DateFormat('HH:mm').format(widget.timestamp.toLocal()),
          style: TextStyle(
            fontSize: 10,
            color: textColor.withOpacity(0.7),
            decoration: TextDecoration.none,
          ),
        ),
        
        // Delivery status icon (for sent messages)
        if (widget.isMe && widget.deliveryStatus == DeliveryStatus.sent) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.check,
            size: 14,
            color: textColor.withOpacity(0.7),
          ),
        ],
        
        // Pending/Failed status
        if (widget.isMe && widget.deliveryStatus != DeliveryStatus.sent) ...[
          const SizedBox(width: 4),
          Icon(
            widget.deliveryStatus == DeliveryStatus.pending
                ? Icons.schedule
                : Icons.warning,
            size: 12,
            color: widget.deliveryStatus == DeliveryStatus.pending
                ? (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87).withOpacity(0.7)
                : Colors.orange,
          ),
        ],
      ],
    );
  }
}
