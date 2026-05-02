import 'package:equatable/equatable.dart';

/// Base class for all application errors
/// 
/// Uses sealed classes for exhaustive pattern matching
/// All error types must extend this class
sealed class AppError extends Equatable {
  final String message;
  final String? details;
  final StackTrace? stackTrace;
  final DateTime timestamp;

  AppError._internal({
    required this.message,
    this.details,
    this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  List<Object?> get props => [message, details, timestamp];

  /// User-friendly error message
  String get userMessage => message;

  /// Technical details for logging
  String get technicalDetails => details ?? message;
}

// ==================== Network Errors ====================

/// Network-related errors (connection, timeout, relay issues)
class NetworkError extends AppError {
  final NetworkErrorType type;

  NetworkError({
    required String message,
    required this.type,
    String? details,
    StackTrace? stackTrace,
  }) : super._internal(
          message: message,
          details: details,
          stackTrace: stackTrace,
        );

  @override
  List<Object?> get props => [...super.props, type];

  @override
  String get userMessage {
    switch (type) {
      case NetworkErrorType.noConnection:
        return 'Keine Internetverbindung';
      case NetworkErrorType.timeout:
        return 'Zeitüberschreitung - Bitte versuche es erneut';
      case NetworkErrorType.relayUnreachable:
        return 'Relay-Server nicht erreichbar';
      case NetworkErrorType.peerNotFound:
        return 'Kontakt ist offline';
      case NetworkErrorType.sendFailed:
        return 'Nachricht konnte nicht gesendet werden';
      case NetworkErrorType.notInitialized:
        return 'P2P Service nicht initialisiert';
      case NetworkErrorType.dhtQueryFailed:
        return 'DHT-Abfrage fehlgeschlagen';
      case NetworkErrorType.unknown:
        return 'Unbekannter Netzwerkfehler';
    }
  }
}

enum NetworkErrorType {
  noConnection,
  timeout,
  relayUnreachable,
  peerNotFound,
  sendFailed,
  notInitialized,
  dhtQueryFailed,
  unknown,
}

// ==================== Crypto Errors ====================

/// Cryptography-related errors (encryption, decryption, signature)
class CryptoError extends AppError {
  final CryptoErrorType type;

  CryptoError({
    required String message,
    required this.type,
    String? details,
    StackTrace? stackTrace,
  }) : super._internal(
          message: message,
          details: details,
          stackTrace: stackTrace,
        );

  @override
  List<Object?> get props => [...super.props, type];

  @override
  String get userMessage {
    switch (type) {
      case CryptoErrorType.encryptionFailed:
        return 'Verschlüsselung fehlgeschlagen';
      case CryptoErrorType.decryptionFailed:
        return 'Entschlüsselung fehlgeschlagen - Nachricht beschädigt?';
      case CryptoErrorType.signatureFailed:
        return 'Signatur konnte nicht erstellt werden';
      case CryptoErrorType.verificationFailed:
        return 'Signatur ungültig - Nachricht wurde manipuliert';
      case CryptoErrorType.keyGenerationFailed:
        return 'Schlüsselerstellung fehlgeschlagen';
      case CryptoErrorType.invalidKey:
        return 'Ungültiger Schlüssel';
    }
  }
}

enum CryptoErrorType {
  encryptionFailed,
  decryptionFailed,
  signatureFailed,
  verificationFailed,
  keyGenerationFailed,
  invalidKey,
}

// ==================== Storage Errors ====================

/// Storage-related errors (Hive, SecureStorage)
class StorageError extends AppError {
  final StorageErrorType type;

  StorageError({
    required String message,
    required this.type,
    String? details,
    StackTrace? stackTrace,
  }) : super._internal(
          message: message,
          details: details,
          stackTrace: stackTrace,
        );

  @override
  List<Object?> get props => [...super.props, type];

  @override
  String get userMessage {
    switch (type) {
      case StorageErrorType.initializationFailed:
        return 'Speicher konnte nicht initialisiert werden';
      case StorageErrorType.saveFailed:
        return 'Daten konnten nicht gespeichert werden';
      case StorageErrorType.loadFailed:
        return 'Daten konnten nicht geladen werden';
      case StorageErrorType.deleteFailed:
        return 'Daten konnten nicht gelöscht werden';
      case StorageErrorType.corruptedData:
        return 'Gespeicherte Daten sind beschädigt';
      case StorageErrorType.insufficientSpace:
        return 'Nicht genügend Speicherplatz';
    }
  }
}

enum StorageErrorType {
  initializationFailed,
  saveFailed,
  loadFailed,
  deleteFailed,
  corruptedData,
  insufficientSpace,
}

// ==================== Identity Errors ====================

/// Identity/Key management errors
class IdentityError extends AppError {
  final IdentityErrorType type;

  IdentityError({
    required String message,
    required this.type,
    String? details,
    StackTrace? stackTrace,
  }) : super._internal(
          message: message,
          details: details,
          stackTrace: stackTrace,
        );

  @override
  List<Object?> get props => [...super.props, type];

  @override
  String get userMessage {
    switch (type) {
      case IdentityErrorType.notInitialized:
        return 'Identität nicht initialisiert';
      case IdentityErrorType.generationFailed:
        return 'Identität konnte nicht erstellt werden';
      case IdentityErrorType.loadFailed:
        return 'Identität konnte nicht geladen werden';
      case IdentityErrorType.deleteFailed:
        return 'Identität konnte nicht gelöscht werden';
      case IdentityErrorType.keyGenerationFailed:
        return 'Schlüsselgenerierung fehlgeschlagen';
      case IdentityErrorType.signatureFailed:
        return 'Signatur konnte nicht erstellt werden';
      case IdentityErrorType.verificationFailed:
        return 'Signaturprüfung fehlgeschlagen';
      case IdentityErrorType.invalidIdentity:
        return 'Ungültige Identität';
    }
  }
}

enum IdentityErrorType {
  notInitialized,
  generationFailed,
  loadFailed,
  deleteFailed,
  keyGenerationFailed,
  signatureFailed,
  verificationFailed,
  invalidIdentity,
}

// ==================== P2P Errors ====================

/// P2P protocol errors (libp2p, DHT)
class P2PError extends AppError {
  final P2PErrorType type;

  P2PError({
    required String message,
    required this.type,
    String? details,
    StackTrace? stackTrace,
  }) : super._internal(
          message: message,
          details: details,
          stackTrace: stackTrace,
        );

  @override
  List<Object?> get props => [...super.props, type];

  @override
  String get userMessage {
    switch (type) {
      case P2PErrorType.initializationFailed:
        return 'P2P-Netzwerk konnte nicht initialisiert werden';
      case P2PErrorType.dhtLookupFailed:
        return 'Kontakt konnte nicht gefunden werden';
      case P2PErrorType.protocolError:
        return 'Protokollfehler';
      case P2PErrorType.bridgeError:
        return 'Native Bridge-Fehler';
    }
  }
}

enum P2PErrorType {
  initializationFailed,
  dhtLookupFailed,
  protocolError,
  bridgeError,
}

// ==================== Validation Errors ====================

/// Input validation errors
class ValidationError extends AppError {
  final String field;

  ValidationError({
    required String message,
    required this.field,
    String? details,
  }) : super._internal(
          message: message,
          details: details,
        );

  @override
  List<Object?> get props => [...super.props, field];

  @override
  String get userMessage => message;
}

// ==================== Unknown Errors ====================

/// Fallback for unexpected errors
class UnknownError extends AppError {
  UnknownError({
    required String message,
    String? details,
    StackTrace? stackTrace,
  }) : super._internal(
          message: message,
          details: details,
          stackTrace: stackTrace,
        );

  @override
  String get userMessage => 'Ein unerwarteter Fehler ist aufgetreten';
}

// ==================== Error Factory ====================

/// Factory for creating AppError from exceptions
class AppErrorFactory {
  /// Convert any exception to AppError
  static AppError fromException(dynamic exception, [StackTrace? stackTrace]) {
    if (exception is AppError) {
      return exception;
    }

    // Try to map common exceptions
    final message = exception.toString();
    
    if (message.contains('SocketException') || 
        message.contains('NetworkException') ||
        message.contains('Connection')) {
      return NetworkError(
        message: 'Network error',
        type: NetworkErrorType.noConnection,
        details: message,
        stackTrace: stackTrace,
      );
    }

    if (message.contains('TimeoutException')) {
      return NetworkError(
        message: 'Request timeout',
        type: NetworkErrorType.timeout,
        details: message,
        stackTrace: stackTrace,
      );
    }

    if (message.contains('Crypto') || 
        message.contains('Encryption') ||
        message.contains('Decryption')) {
      return CryptoError(
        message: 'Cryptographic operation failed',
        type: CryptoErrorType.encryptionFailed,
        details: message,
        stackTrace: stackTrace,
      );
    }

    if (message.contains('Hive') || 
        message.contains('Storage') ||
        message.contains('FileSystem')) {
      return StorageError(
        message: 'Storage operation failed',
        type: StorageErrorType.saveFailed,
        details: message,
        stackTrace: stackTrace,
      );
    }

    // Fallback to unknown error
    return UnknownError(
      message: 'Unexpected error occurred',
      details: message,
      stackTrace: stackTrace,
    );
  }
}
