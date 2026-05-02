import 'dart:typed_data';
import '../../models/app_error.dart';
import '../../utils/result.dart';

/// Crypto Service Interface
/// 
/// Defines the contract for cryptographic operations
/// Implementations: CryptoService, MockCryptoService (for tests)
abstract class ICryptoService {
  /// Encrypt plaintext for recipient using X25519 ECDH + ChaCha20-Poly1305
  /// 
  /// Returns: nonce + ciphertext + mac (packed as single Uint8List)
  Future<Result<Uint8List, AppError>> encrypt({
    required String plaintext,
    required Uint8List recipientPublicKey,
    required Uint8List senderPrivateKey,
  });
  
  /// Decrypt ciphertext from sender using X25519 ECDH + ChaCha20-Poly1305
  /// 
  /// Returns: decrypted plaintext string
  Future<Result<String, AppError>> decrypt({
    required Uint8List ciphertext,
    required Uint8List senderPublicKey,
    required Uint8List recipientPrivateKey,
  });
  
  /// Generate random nonce for replay protection
  Result<Uint8List, AppError> generateNonce({int length = 24});
  
  /// Generate Ed25519 key pair for signing
  Future<Result<({Uint8List privateKey, Uint8List publicKey}), AppError>> generateEd25519KeyPair();
  
  /// Generate X25519 key pair for encryption
  Future<Result<({Uint8List privateKey, Uint8List publicKey}), AppError>> generateX25519KeyPair();
  
  /// Sign data with Ed25519 private key
  Future<Result<Uint8List, AppError>> sign({
    required Uint8List data,
    required Uint8List privateKey,
  });
  
  /// Verify Ed25519 signature
  Future<Result<bool, AppError>> verify({
    required Uint8List data,
    required Uint8List signature,
    required Uint8List publicKey,
  });
  
  /// Derive X25519 public key from Ed25519 public key
  Future<Result<Uint8List, AppError>> ed25519PublicKeyToX25519(Uint8List ed25519PublicKey);
  
  /// Derive X25519 private key from Ed25519 private key
  Future<Uint8List> ed25519PrivateKeyToX25519(Uint8List ed25519PrivateKey);
}
