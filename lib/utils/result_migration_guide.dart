import 'dart:typed_data';
import '../models/app_error.dart';
import '../utils/result.dart';

/// Example: How to refactor services to use Result Type
/// 
/// This file demonstrates the pattern for migrating services
/// from throwing exceptions to returning Result<T, AppError>
/// 
/// BEFORE (throwing exceptions):
/// ```dart
/// class MyService {
///   Future<User> loadUser(String id) async {
///     if (id.isEmpty) {
///       throw ValidationException('ID cannot be empty');
///     }
///     
///     try {
///       final user = await api.getUser(id);
///       return user;
///     } catch (e) {
///       throw NetworkException('Failed to load user: $e');
///     }
///   }
/// }
/// 
/// // Usage (error-prone):
/// try {
///   final user = await service.loadUser(id);
///   print('Loaded: ${user.name}');
/// } catch (e) {
///   print('Error: $e');  // Generic error handling
/// }
/// ```
/// 
/// AFTER (using Result):
/// ```dart
/// class MyService {
///   Future<Result<User, AppError>> loadUser(String id) async {
///     if (id.isEmpty) {
///       return Failure(ValidationError(
///         message: 'ID cannot be empty',
///         field: 'id',
///       ));
///     }
///     
///     return resultOfAsync(
///       () async => await api.getUser(id),
///       (e, stackTrace) => NetworkError(
///         message: 'Failed to load user',
///         type: NetworkErrorType.sendFailed,
///         details: e.toString(),
///         stackTrace: stackTrace,
///       ),
///     );
///   }
/// }
/// 
/// // Usage (type-safe):
/// final result = await service.loadUser(id);
/// switch (result) {
///   case Success(value: final user):
///     print('Loaded: ${user.name}');
///   case Failure(error: final error):
///     // Type-safe pattern matching on error type
///     if (error is NetworkError) {
///       print('Network error: ${error.userMessage}');
///     } else if (error is ValidationError) {
///       print('Validation error: ${error.field}');
///     }
/// }
/// ```

// ==================== Example: Crypto Service ====================

/// Example interface for a crypto service using Result
abstract class ICryptoServiceResult {
  /// Encrypt plaintext - returns Result instead of throwing
  Future<Result<Uint8List, AppError>> encrypt({
    required String plaintext,
    required Uint8List recipientPublicKey,
    required Uint8List senderPrivateKey,
  });

  /// Decrypt ciphertext - returns Result instead of throwing
  Future<Result<String, AppError>> decrypt({
    required Uint8List ciphertext,
    required Uint8List senderPublicKey,
    required Uint8List recipientPrivateKey,
  });

  /// Generate key pair - returns Result instead of throwing
  Future<Result<({Uint8List privateKey, Uint8List publicKey}), AppError>>
      generateKeyPair();
}

/// Example implementation showing Result pattern
class CryptoServiceResultExample implements ICryptoServiceResult {
  @override
  Future<Result<Uint8List, AppError>> encrypt({
    required String plaintext,
    required Uint8List recipientPublicKey,
    required Uint8List senderPrivateKey,
  }) async {
    // Validation
    if (plaintext.isEmpty) {
      return Failure(
        ValidationError(
          message: 'Plaintext cannot be empty',
          field: 'plaintext',
        ),
      );
    }

    if (recipientPublicKey.length != 32) {
      return Failure(
        CryptoError(
          message: 'Invalid recipient public key length',
          type: CryptoErrorType.invalidKey,
          details: 'Expected 32 bytes, got ${recipientPublicKey.length}',
        ),
      );
    }

    // Wrap crypto operation in resultOfAsync
    return resultOfAsync(
      () async {
        // Actual encryption logic here
        // For this example, just return dummy data
        return Uint8List.fromList([1, 2, 3]);
      },
      (exception, stackTrace) => CryptoError(
        message: 'Encryption failed',
        type: CryptoErrorType.encryptionFailed,
        details: exception.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<String, AppError>> decrypt({
    required Uint8List ciphertext,
    required Uint8List senderPublicKey,
    required Uint8List recipientPrivateKey,
  }) async {
    // Validation
    if (ciphertext.isEmpty) {
      return Failure(
        CryptoError(
          message: 'Ciphertext cannot be empty',
          type: CryptoErrorType.decryptionFailed,
        ),
      );
    }

    // Wrap crypto operation
    return resultOfAsync(
      () async {
        // Actual decryption logic here
        return 'decrypted text';
      },
      (exception, stackTrace) => CryptoError(
        message: 'Decryption failed',
        type: CryptoErrorType.decryptionFailed,
        details: exception.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<({Uint8List privateKey, Uint8List publicKey}), AppError>>
      generateKeyPair() async {
    return resultOfAsync(
      () async {
        // Actual key generation logic
        return (
          privateKey: Uint8List.fromList(List.generate(32, (i) => i)),
          publicKey: Uint8List.fromList(List.generate(32, (i) => i + 100)),
        );
      },
      (exception, stackTrace) => CryptoError(
        message: 'Key generation failed',
        type: CryptoErrorType.keyGenerationFailed,
        details: exception.toString(),
        stackTrace: stackTrace,
      ),
    );
  }
}

// ==================== Example: Storage Service ====================

/// Example interface for storage using Result
abstract class IStorageServiceResult {
  Future<Result<void, AppError>> saveData(String key, String value);
  Future<Result<String, AppError>> loadData(String key);
  Future<Result<void, AppError>> deleteData(String key);
}

/// Example implementation
class StorageServiceResultExample implements IStorageServiceResult {
  final _data = <String, String>{};

  @override
  Future<Result<void, AppError>> saveData(String key, String value) async {
    if (key.isEmpty) {
      return Failure(
        ValidationError(
          message: 'Key cannot be empty',
          field: 'key',
        ),
      );
    }

    return resultOfAsync(
      () async {
        _data[key] = value;
      },
      (exception, stackTrace) => StorageError(
        message: 'Failed to save data',
        type: StorageErrorType.saveFailed,
        details: exception.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<String, AppError>> loadData(String key) async {
    if (key.isEmpty) {
      return Failure(
        ValidationError(
          message: 'Key cannot be empty',
          field: 'key',
        ),
      );
    }

    return resultOfAsync(
      () async {
        final value = _data[key];
        if (value == null) {
          throw Exception('Key not found: $key');
        }
        return value;
      },
      (exception, stackTrace) => StorageError(
        message: 'Failed to load data',
        type: StorageErrorType.loadFailed,
        details: exception.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  Future<Result<void, AppError>> deleteData(String key) async {
    return resultOfAsync(
      () async {
        _data.remove(key);
      },
      (exception, stackTrace) => StorageError(
        message: 'Failed to delete data',
        type: StorageErrorType.deleteFailed,
        details: exception.toString(),
        stackTrace: stackTrace,
      ),
    );
  }
}

// ==================== Usage Examples in UI ====================

/// Example widget showing how to use Result in UI
/* 
class ExampleWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: _loadData(ref, context),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        }
        return Text('Data loaded');
      },
    );
  }

  Future<void> _loadData(WidgetRef ref, BuildContext context) async {
    final service = ref.read(storageServiceProvider);
    
    // Option 1: Pattern matching
    final result = await service.loadData('user_id');
    switch (result) {
      case Success(value: final data):
        print('Loaded: $data');
      case Failure(error: final error):
        if (context.mounted) {
          context.handleError(error);
        }
    }
    
    // Option 2: Using fold
    await service.loadData('user_id').fold(
      onSuccess: (data) => print('Loaded: $data'),
      onFailure: (error) {
        if (context.mounted) {
          context.handleError(error);
        }
      },
    );
    
    // Option 3: Using extensions (cleanest)
    await context.handleAsync(
      service.loadData('user_id'),
      onSuccess: (data) => print('Loaded: $data'),
    );
  }
  
  // Example with retry
  Future<void> _saveDataWithRetry(
    WidgetRef ref,
    BuildContext context,
  ) async {
    final service = ref.read(storageServiceProvider);
    
    await context.handleAsync(
      service.saveData('key', 'value'),
      onSuccess: (_) {
        showTopNotification(context, 'Gespeichert!');
      },
      onRetry: () => _saveDataWithRetry(ref, context), // Recursive retry
    );
  }
}
*/

// ==================== Chaining Results ====================

/// Example of chaining multiple operations
Future<Result<String, AppError>> exampleChaining(
  ICryptoServiceResult cryptoService,
  IStorageServiceResult storageService,
) async {
  // Generate key pair
  final keyPairResult = await cryptoService.generateKeyPair();

  // Chain: if key generation succeeds, save private key
  return await keyPairResult.flatMapAsync((keyPair) async {
    return await storageService.saveData(
      'private_key',
      'base64_encoded_key_here',
    );
  }).then((saveResult) {
    // Chain: if save succeeds, load it back
    return saveResult.flatMapAsync((_) async {
      return await storageService.loadData('private_key');
    });
  });

  // All of this in one expression:
  // return await cryptoService
  //     .generateKeyPair()
  //     .flatMapAsync((keyPair) => storageService.saveData('key', 'value'))
  //     .flatMapAsync((_) => storageService.loadData('key'));
}

// ==================== Migration Checklist ====================

/*
MIGRATION STEPS:

1. Update interface return types:
   - Future<T> → Future<Result<T, AppError>>
   - void methods → Future<Result<void, AppError>>

2. Wrap implementations with resultOfAsync:
   - Wrap entire method body in resultOfAsync
   - Map exceptions to appropriate AppError types
   - Add validation before async operation

3. Update callers:
   - Remove try-catch blocks
   - Use pattern matching or fold()
   - Use context.handleAsync() for UI feedback

4. Update tests:
   - Expect Result types
   - Test both Success and Failure cases
   - Verify correct AppError types

5. Benefits:
   - Compiler enforces error handling
   - Type-safe error types
   - No silent failures
   - Better testability
   - Consistent error UX
*/
