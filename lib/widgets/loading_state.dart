import 'package:flutter/material.dart';

/// Reusable loading state widget with optional message
/// 
/// Usage:
/// ```dart
/// LoadingState()
/// LoadingState(message: 'Loading messages...')
/// ```
class LoadingState extends StatelessWidget {
  final String? message;
  final double? size;
  
  const LoadingState({
    super.key,
    this.message,
    this.size,
  });
  
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size ?? 40,
            height: size ?? 40,
            child: const CircularProgressIndicator(),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Inline loading indicator for buttons and small spaces
class InlineLoadingIndicator extends StatelessWidget {
  final double size;
  final Color? color;
  
  const InlineLoadingIndicator({
    super.key,
    this.size = 20,
    this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: color != null 
            ? AlwaysStoppedAnimation<Color>(color!)
            : null,
      ),
    );
  }
}
