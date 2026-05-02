import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import '../models/app_error.dart';
import '../utils/result.dart';
import '../utils/top_notification.dart';

/// Global error handler for the application
/// 
/// Provides centralized error handling with:
/// - Logging to console/file
/// - User-friendly UI feedback (SnackBar/Dialog)
/// - Optional retry actions
/// - Analytics/Crash reporting integration points
/// 
/// Usage:
/// ```dart
/// final result = await somethingThatCanFail();
/// if (context.mounted) {
///   ErrorHandler.handle(result, context);
/// }
/// ```
class ErrorHandler {
  /// Handle a Result<T, AppError> and show UI feedback
  static void handleResult<T>(
    Result<T, AppError> result,
    BuildContext context, {
    VoidCallback? onRetry,
    bool showSnackBar = true,
  }) {
    if (result case Failure(error: final error)) {
      handle(error, context, onRetry: onRetry, showSnackBar: showSnackBar);
    }
  }

  /// Handle an AppError directly
  static void handle(
    AppError error,
    BuildContext context, {
    VoidCallback? onRetry,
    bool showSnackBar = true,
  }) {
    // Log error
    _logError(error);

    // Show UI feedback
    if (showSnackBar && context.mounted) {
      _showSnackBar(error, context, onRetry: onRetry);
    }

    // TODO: Send to analytics/crash reporting
    // _reportToCrashlytics(error);
  }

  /// Handle an AppError with custom success callback
  static Future<void> handleAsync<T>(
    Future<Result<T, AppError>> resultFuture,
    BuildContext context, {
    void Function(T value)? onSuccess,
    VoidCallback? onRetry,
    bool showSnackBar = true,
  }) async {
    final result = await resultFuture;

    if (!context.mounted) return;

    switch (result) {
      case Success(value: final value):
        onSuccess?.call(value);
      case Failure(error: final error):
        handle(error, context, onRetry: onRetry, showSnackBar: showSnackBar);
    }
  }

  /// Show error dialog (for critical errors)
  static Future<void> showErrorDialog(
    AppError error,
    BuildContext context, {
    VoidCallback? onRetry,
    String? title,
  }) async {
    _logError(error);

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title ?? 'Fehler'),
        content: Text(error.userMessage),
        actions: [
          if (onRetry != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onRetry();
              },
              child: const Text('Erneut versuchen'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Log error to console (and optionally to file/service)
  static void _logError(AppError error) {
    final errorType = error.runtimeType.toString();
    
    developer.log(
      '[ERROR] $errorType: ${error.message}',
      time: error.timestamp,
      name: 'ErrorHandler',
      error: error,
      stackTrace: error.stackTrace,
    );

    // Detailed technical log
    if (error.details != null) {
      developer.log(
        'Details: ${error.details}',
        time: error.timestamp,
        name: 'ErrorHandler',
      );
    }

    // TODO: Write to local log file for debugging
  }

  /// Show user-friendly top notification (replaces SnackBar)
  static void _showSnackBar(
    AppError error,
    BuildContext context, {
    VoidCallback? onRetry,
  }) {
    // Determine background color based on error type
    final backgroundColor = _getBackgroundColor(error);
    
    // Determine if this is an error or info notification
    final isError = switch (error) {
      NetworkError() => true,
      UnknownError() => true,
      ValidationError() => true,
      CryptoError() => true,
      StorageError() => true,
      IdentityError() => true,
      P2PError() => true,
    };

    // Show top notification
    showTopNotification(
      context,
      error.userMessage,
      backgroundColor: backgroundColor,
      duration: const Duration(seconds: 4),
      isError: isError,
    );

    // If retry is available, show it as a separate notification  
    // Note: Top notifications don't support action button inline,
    // so retry logic should be handled differently if needed
  }

  /// Determine background color based on error severity
  static Color _getBackgroundColor(AppError error) {
    return switch (error) {
      NetworkError() => Colors.orange.shade700,
      CryptoError() => Colors.red.shade700,
      StorageError() => Colors.red.shade600,
      IdentityError() => Colors.red.shade800,
      P2PError() => Colors.orange.shade700,
      ValidationError() => Colors.blue.shade700,
      UnknownError() => Colors.grey.shade800,
    };
  }

  // TODO: Integration with crash reporting services
  /*
  static Future<void> _reportToCrashlytics(AppError error) async {
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        error.stackTrace,
        reason: error.message,
        information: [
          'Type: ${error.runtimeType}',
          'Details: ${error.details}',
          'Timestamp: ${error.timestamp}',
        ],
      );
    } catch (e) {
      developer.log(
        'Failed to report error to Crashlytics: $e',
        name: 'ErrorHandler',
      );
    }
  }
  */

  // TODO: Write errors to local log file
  /*
  static Future<void> _writeToLogFile(
    String timestamp,
    String errorType,
    AppError error,
  ) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final logFile = File('${directory.path}/error_log.txt');
      
      final logEntry = '''
[$timestamp] $errorType
Message: ${error.message}
Details: ${error.details ?? 'N/A'}
Stack Trace: ${error.stackTrace ?? 'N/A'}
---
''';
      
      await logFile.writeAsString(
        logEntry,
        mode: FileMode.append,
      );
    } catch (e) {
      developer.log(
        'Failed to write to log file: $e',
        name: 'ErrorHandler',
      );
    }
  }
  */
}

// ==================== BuildContext Extension ====================

/// Convenient extension on BuildContext for error handling
extension ErrorHandlerContext on BuildContext {
  /// Handle a Result with automatic context passing
  void handleResult<T>(
    Result<T, AppError> result, {
    VoidCallback? onRetry,
    bool showSnackBar = true,
  }) {
    ErrorHandler.handleResult(
      result,
      this,
      onRetry: onRetry,
      showSnackBar: showSnackBar,
    );
  }

  /// Handle an AppError with automatic context passing
  void handleError(
    AppError error, {
    VoidCallback? onRetry,
    bool showSnackBar = true,
  }) {
    ErrorHandler.handle(
      error,
      this,
      onRetry: onRetry,
      showSnackBar: showSnackBar,
    );
  }

  /// Handle async result with automatic context passing
  Future<void> handleAsync<T>(
    Future<Result<T, AppError>> resultFuture, {
    void Function(T value)? onSuccess,
    VoidCallback? onRetry,
    bool showSnackBar = true,
  }) {
    return ErrorHandler.handleAsync(
      resultFuture,
      this,
      onSuccess: onSuccess,
      onRetry: onRetry,
      showSnackBar: showSnackBar,
    );
  }

  /// Show error dialog with automatic context passing
  Future<void> showErrorDialog(
    AppError error, {
    VoidCallback? onRetry,
    String? title,
  }) {
    return ErrorHandler.showErrorDialog(
      error,
      this,
      onRetry: onRetry,
      title: title,
    );
  }
}
