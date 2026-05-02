import 'package:flutter/material.dart';

/// Reusable empty state widget for empty lists/screens
/// 
/// Usage:
/// ```dart
/// EmptyState(
///   message: 'No messages yet',
///   icon: Icons.inbox,
/// )
/// 
/// EmptyState(
///   message: 'No contacts',
///   icon: Icons.person_outline,
///   action: ElevatedButton(
///     onPressed: () => Navigator.push(...),
///     child: Text('Add Contact'),
///   ),
/// )
/// ```
class EmptyState extends StatelessWidget {
  final String message;
  final String? subtitle;
  final IconData icon;
  final Widget? action;
  final Color? iconColor;
  
  const EmptyState({
    super.key,
    required this.message,
    this.subtitle,
    this.icon = Icons.inbox,
    this.action,
    this.iconColor,
  });
  
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 80,
              color: iconColor ?? Colors.grey[400],
            ),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact empty state for smaller spaces (e.g., sections)
class CompactEmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  
  const CompactEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
  });
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
          const SizedBox(width: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}
