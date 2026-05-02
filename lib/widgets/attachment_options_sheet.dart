import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/top_notification.dart';
import '../utils/logger.dart';

/// Bottom Sheet with attachment options (Camera, Gallery, Files)
class AttachmentOptionsSheet extends StatelessWidget {
  final Function(String imagePath) onImageSelected;
  final Function(String filePath)? onFileSelected;

  const AttachmentOptionsSheet({
    super.key,
    required this.onImageSelected,
    this.onFileSelected,
  });

  Future<void> _pickImageFromCamera(BuildContext context) async {
    Navigator.pop(context); // Close bottom sheet

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (photo != null) {
        onImageSelected(photo.path);
        if (context.mounted) {
          showTopNotification(
            context,
            '📸 Photo captured successfully',
          );
        }
      }
    } catch (e) {
      Logger.error('Error taking photo', e);
      if (context.mounted) {
        showTopNotification(
          context,
          'Failed to take photo',
          isError: true,
        );
      }
    }
  }

  Future<void> _pickImageFromGallery(BuildContext context) async {
    Navigator.pop(context); // Close bottom sheet

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        // Check file size (max 10 MB)
        final file = File(image.path);
        final sizeInBytes = await file.length();
        final sizeInMB = sizeInBytes / (1024 * 1024);

        if (sizeInMB > 10) {
          if (context.mounted) {
            showTopNotification(
              context,
              'Image too large (${sizeInMB.toStringAsFixed(1)} MB). Max: 10 MB',
              isError: true,
            );
          }
          return;
        }

        onImageSelected(image.path);
        if (context.mounted) {
          showTopNotification(
            context,
            '🖼️ Image selected successfully',
          );
        }
      }
    } catch (e) {
      Logger.error('Error selecting image', e);
      if (context.mounted) {
        showTopNotification(
          context,
          'Failed to select image',
          isError: true,
        );
      }
    }
  }

  Future<void> _pickFile(BuildContext context) async {
    Navigator.pop(context);
    
    // TODO: Implement file picker (Phase 3)
    if (context.mounted) {
      showTopNotification(
        context,
        'File picker coming soon!',
        duration: const Duration(seconds: 2),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send Media',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Choose image or file to send',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Camera option
          _buildOption(
            context,
            icon: Icons.camera_alt,
            label: 'Camera',
            color: Colors.blue,
            onTap: () {
              Logger.debug('📸 User tapped Camera option');
              _pickImageFromCamera(context);
            },
          ),
          
          // Gallery option
          _buildOption(
            context,
            icon: Icons.photo_library,
            label: 'Gallery',
            color: Colors.green,
            onTap: () {
              Logger.debug('🖼️ User tapped Gallery option');
              _pickImageFromGallery(context);
            },
          ),
          
          // File option (Phase 3)
          if (onFileSelected != null)
            _buildOption(
              context,
              icon: Icons.insert_drive_file,
              label: 'File',
              color: Colors.orange,
              onTap: () => _pickFile(context),
            ),
          
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(label),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
    );
  }
}
