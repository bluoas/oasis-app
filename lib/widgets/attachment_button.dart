import 'package:flutter/material.dart';
import 'attachment_options_sheet.dart';
import '../utils/logger.dart';

/// Attachment Button - Shows "+" icon and opens bottom sheet with media options
/// 
/// Usage:
/// ```dart
/// AttachmentButton(
///   onImageSelected: (path) => print('Image: $path'),
///   onFileSelected: (path) => print('File: $path'),
/// )
/// ```
class AttachmentButton extends StatelessWidget {
  final Function(String imagePath) onImageSelected;
  final Function(String filePath)? onFileSelected;
  final bool enabled;

  const AttachmentButton({
    super.key,
    required this.onImageSelected,
    this.onFileSelected,
    this.enabled = true,
  });

  void _openOptions(BuildContext context) {
    Logger.debug('➕ Attachment button tapped, opening bottom sheet...');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AttachmentOptionsSheet(
        onImageSelected: (path) {
          Logger.debug('➕ Image selected callback: $path');
          onImageSelected(path);
        },
        onFileSelected: onFileSelected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: IconButton(
        onPressed: enabled ? () => _openOptions(context) : null,
        icon: Icon(
          Icons.add,
          color: enabled 
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          size: 20,
        ),
        padding: EdgeInsets.zero,
        tooltip: 'Attach media',
      ),
    );
  }
}
