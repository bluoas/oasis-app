import 'dart:convert';
import 'dart:typed_data';
import '../../lib/services/interfaces/i_crypto_service.dart';
import '../../lib/models/app_error.dart';
import '../../lib/utils/result.dart';

/// Mock Crypto Service for Testing
/// 
/// Provides deterministic crypto operations without real cryptography
/// Useful for testing business logic without crypto overhead
class CryptoMockService implements ICryptoService {
  // Configurable for testing error scenarios
  bool shouldFailEncrypt = false;
  bool shouldFailDecrypt = false;
  bool shouldFailSign = false;
  bool shouldFailVerify = false;
  
  // Track operations for verification
  int encryptCallCount = 0;
  int decryptCallCount = 0;
  int signCallCount = 0;
  int verifyCallCount = 0;

  @override
  Future<Result<Uint8List, AppError>> encrypt({
    required String plaintext,
    required Uint8List recipientPublicKey,
    required Uint8List senderPrivateKey,
  }) async {
    encryptCallCount++;
    
    if (shouldFailEncrypt) {
      return Failure(CryptoError(
        message: 'Mock: Encryption failed',
        type: CryptoErrorType.encryptionFailed,
      ));
    }
    
    await Future.delayed(const Duration(milliseconds: 5));
    
    // Mock: Just base64 encode (NOT SECURE, only for testing!)
    final encoded = base64.encode(utf8.encode(plaintext));
    return Success(Uint8List.fromList(utf8.encode('MOCK_ENCRYPTED:$encoded')));
  }

  @override
  Future<Result<String, AppError>> decrypt({
    required Uint8List ciphertext,
    required Uint8List senderPublicKey,
    required Uint8List recipientPrivateKey,
  }) async {
    decryptCallCount++;
    
    if (shouldFailDecrypt) {
      return Failure(CryptoError(
        message: 'Mock: Decryption failed',
        type: CryptoErrorType.decryptionFailed,
      ));
    }
    
    await Future.delayed(const Duration(milliseconds: 5));
    
    // Mock: Reverse the mock encryption
    final text = utf8.decode(ciphertext);
    if (text.startsWith('MOCK_ENCRYPTED:')) {
      final encoded = text.substring('MOCK_ENCRYPTED:'.length);
      return Success(utf8.decode(base64.decode(encoded)));
    }
    
    return Failure(CryptoError(
      message: 'Mock: Invalid ciphertext format',
      type: CryptoErrorType.decryptionFailed,
    ));
  }

  @override
  Result<Uint8List, AppError> generateNonce({int length = 24}) {
    // Return deterministic nonce for testing
    return Success(Uint8List.fromList(List.generate(length, (i) => i % 256)));
  }

  @override
  Future<Result<({Uint8List privateKey, Uint8List publicKey}), AppError>> generateEd25519KeyPair() async {
    await Future.delayed(const Duration(milliseconds: 10));
    
    // Return deterministic key pair (NOT SECURE, only for testing!)
    return Success((
      privateKey: Uint8List.fromList(List.generate(32, (i) => i)),
      publicKey: Uint8List.fromList(List.generate(32, (i) => i + 100)),
    ));
  }

  @override
  Future<Result<({Uint8List privateKey, Uint8List publicKey}), AppError>> generateX25519KeyPair() async {
    await Future.delayed(const Duration(milliseconds: 10));
    
    // Return deterministic key pair (NOT SECURE, only for testing!)
    return Success((
      privateKey: Uint8List.fromList(List.generate(32, (i) => i + 50)),
      publicKey: Uint8List.fromList(List.generate(32, (i) => i + 150)),
    ));
  }

  @override
  Future<Result<Uint8List, AppError>> sign({
    required Uint8List data,
    required Uint8List privateKey,
  }) async {
    signCallCount++;
    
    if (shouldFailSign) {
      return Failure(CryptoError(
        message: 'Mock: Signing failed',
        type: CryptoErrorType.signatureFailed,
      ));
    }
    
    await Future.delayed(const Duration(milliseconds: 3));
    
    // Return deterministic signature (64 bytes for Ed25519)
    // Mock: Hash the data length into signature for some determinism
    return Success(Uint8List.fromList(
      List.generate(64, (i) => (i + data.length) % 256),
    ));
  }

  @override
  Future<Result<bool, AppError>> verify({
    required Uint8List data,
    required Uint8List signature,
    required Uint8List publicKey,
  }) async {
    verifyCallCount++;
    
    if (shouldFailVerify) {
      return Failure(CryptoError(
        message: 'Mock: Verification failed',
        type: CryptoErrorType.verificationFailed,
      ));
    }
    
    await Future.delayed(const Duration(milliseconds: 3));
    
    // Mock: Always return true unless signature is obviously invalid
    if (signature.length != 64) {
      return Success(false);
    }
    
    return Success(true);
  }

  @override
  Future<Result<Uint8List, AppError>> ed25519PublicKeyToX25519(Uint8List ed25519PublicKey) async {
    await Future.delayed(const Duration(milliseconds: 5));
    
    // Mock: Generate deterministic X25519 key from Ed25519 key
    return Success(Uint8List.fromList(
      List.generate(32, (i) => (ed25519PublicKey[i % 32] + 50) % 256),
    ));
  }

  @override
  Future<Uint8List> ed25519PrivateKeyToX25519(Uint8List ed25519PrivateKey) async {
    await Future.delayed(const Duration(milliseconds: 5));
    
    // Mock: Generate deterministic X25519 private key from Ed25519 private key
    return Uint8List.fromList(
      List.generate(32, (i) => (ed25519PrivateKey[i % 32] + 25) % 256),
    );
  }
  
  // ==================== Test Helper Methods ====================
  
  /// Reset all state and counters
  void reset() {
    shouldFailEncrypt = false;
    shouldFailDecrypt = false;
    shouldFailSign = false;
    shouldFailVerify = false;
    
    encryptCallCount = 0;
    decryptCallCount = 0;
    signCallCount = 0;
    verifyCallCount = 0;
  }
  
  /// Get total crypto operations count
  int get totalOperations =>
      encryptCallCount + decryptCallCount + signCallCount + verifyCallCount;
}
