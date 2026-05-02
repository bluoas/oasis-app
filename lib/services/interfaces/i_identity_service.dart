import 'dart:typed_data';
import '../../models/app_error.dart';
import '../../utils/result.dart';

/// Identity Service Interface
/// 
/// Defines the contract for identity and key management
/// Implementations: IdentityService, MockIdentityService (for tests)
abstract class IIdentityService {
  /// Current PeerID (null if not initialized)
  String? get peerID;
  
  /// Ed25519 private key for signatures (null if not initialized)
  Uint8List? get privateKey;
  
  /// Ed25519 public key (null if not initialized)
  Uint8List? get publicKey;
  
  /// X25519 encryption private key (null if not initialized)
  Uint8List? get encryptionPrivateKey;
  
  /// X25519 encryption public key (null if not initialized)
  Uint8List? get encryptionPublicKey;
  
  /// Check if identity is available
  bool get hasIdentity;
  
  /// Initialize identity service (load or generate)
  Future<Result<void, AppError>> initialize();
  
  /// Generate new identity
  Future<Result<void, AppError>> generateIdentity();
  
  /// Load existing identity from secure storage
  Future<Result<bool, AppError>> loadIdentity();
  
  /// Delete identity (for reset)
  Future<Result<void, AppError>> deleteIdentity();
  
  /// Sign data with Ed25519 private key
  Future<Result<Uint8List, AppError>> sign(Uint8List data);
  
  /// Verify signature with Ed25519 public key
  Future<Result<bool, AppError>> verify({
    required Uint8List data,
    required Uint8List signature,
    required Uint8List publicKey,
  });
}
