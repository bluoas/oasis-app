import 'dart:typed_data';
import '../../lib/services/interfaces/i_identity_service.dart';
import '../../lib/services/interfaces/i_crypto_service.dart';
import '../../lib/models/app_error.dart';
import '../../lib/utils/result.dart';

/// Mock Identity Service for Testing
/// 
/// Provides deterministic identity without secure storage dependencies
/// Can be pre-configured with test identities for predictable testing
class IdentityMockService implements IIdentityService {
  final ICryptoService _crypto;
  
  String? _peerID;
  Uint8List? _privateKey;
  Uint8List? _publicKey;
  Uint8List? _encryptionPrivateKey;
  Uint8List? _encryptionPublicKey;
  
  // Configurable for testing error scenarios
  bool shouldFailInitialize = false;
  bool shouldFailGenerate = false;
  bool shouldFailLoad = false;
  bool shouldFailSign = false;
  bool shouldFailVerify = false;
  
  // Track operations for verification
  int initializeCallCount = 0;
  int generateCallCount = 0;
  int loadCallCount = 0;
  int signCallCount = 0;
  int verifyCallCount = 0;

  IdentityMockService({required ICryptoService crypto}) : _crypto = crypto;

  @override
  String? get peerID => _peerID;

  @override
  Uint8List? get privateKey => _privateKey;

  @override
  Uint8List? get publicKey => _publicKey;

  @override
  Uint8List? get encryptionPrivateKey => _encryptionPrivateKey;

  @override
  Uint8List? get encryptionPublicKey => _encryptionPublicKey;

  @override
  bool get hasIdentity => 
      _peerID != null && 
      _privateKey != null && 
      _publicKey != null;

  @override
  Future<Result<void, AppError>> initialize() async {
    initializeCallCount++;
    
    if (shouldFailInitialize) {
      return Failure(IdentityError(
        message: 'Mock: Failed to initialize identity',
        type: IdentityErrorType.notInitialized,
      ));
    }
    
    await Future.delayed(const Duration(milliseconds: 10));
    
    // Try to load, if not exists generate
    final loadedResult = await loadIdentity();
    if (loadedResult.isFailure) {
      return Failure(loadedResult.errorOrNull!);
    }
    
    if (!(loadedResult.valueOrNull ?? false)) {
      final genResult = await generateIdentity();
      if (genResult.isFailure) {
        return Failure(genResult.errorOrNull!);
      }
    }
    
    return Success(null);
  }

  @override
  Future<Result<void, AppError>> generateIdentity() async {
    generateCallCount++;
    
    if (shouldFailGenerate) {
      return Failure(IdentityError(
        message: 'Mock: Failed to generate identity',
        type: IdentityErrorType.generationFailed,
      ));
    }
    
    await Future.delayed(const Duration(milliseconds: 20));
    
    // Generate Ed25519 key pair for signatures
    final ed25519KeysResult = await _crypto.generateEd25519KeyPair();
    if (ed25519KeysResult.isFailure) {
      return Failure(ed25519KeysResult.errorOrNull!);
    }
    final ed25519Keys = ed25519KeysResult.valueOrNull!;
    _privateKey = ed25519Keys.privateKey;
    _publicKey = ed25519Keys.publicKey;
    
    // Generate X25519 key pair for encryption
    final x25519KeysResult = await _crypto.generateX25519KeyPair();
    if (x25519KeysResult.isFailure) {
      return Failure(x25519KeysResult.errorOrNull!);
    }
    final x25519Keys = x25519KeysResult.valueOrNull!;
    _encryptionPrivateKey = x25519Keys.privateKey;
    _encryptionPublicKey = x25519Keys.publicKey;
    
    // Generate mock PeerID from public key
    _peerID = 'mock_peer_${_publicKey!.sublist(0, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    
    return Success(null);
  }

  @override
  Future<Result<bool, AppError>> loadIdentity() async {
    loadCallCount++;
    
    if (shouldFailLoad) {
      return Failure(IdentityError(
        message: 'Mock: Failed to load identity',
        type: IdentityErrorType.loadFailed,
      ));
    }
    
    await Future.delayed(const Duration(milliseconds: 10));
    
    // Mock: Return false (no stored identity) unless we were pre-configured
    if (_peerID != null && _privateKey != null) {
      return Success(true);
    }
    
    return Success(false);
  }

  @override
  Future<Result<void, AppError>> deleteIdentity() async {
    await Future.delayed(const Duration(milliseconds: 10));
    
    _peerID = null;
    _privateKey = null;
    _publicKey = null;
    _encryptionPrivateKey = null;
    _encryptionPublicKey = null;
    
    return Success(null);
  }

  @override
  Future<Result<Uint8List, AppError>> sign(Uint8List data) async {
    signCallCount++;
    
    if (!hasIdentity) {
      return Failure(IdentityError(
        message: 'Mock: No identity available',
        type: IdentityErrorType.notInitialized,
      ));
    }
    
    if (shouldFailSign) {
      return Failure(IdentityError(
        message: 'Mock: Signing failed',
        type: IdentityErrorType.signatureFailed,
      ));
    }
    
    final signResult = await _crypto.sign(
      data: data,
      privateKey: _privateKey!,
    );
    
    return signResult;
  }

  @override
  Future<Result<bool, AppError>> verify({
    required Uint8List data,
    required Uint8List signature,
    required Uint8List publicKey,
  }) async {
    verifyCallCount++;
    
    if (shouldFailVerify) {
      return Failure(IdentityError(
        message: 'Mock: Verification failed',
        type: IdentityErrorType.verificationFailed,
      ));
    }
    
    final verifyResult = await _crypto.verify(
      data: data,
      signature: signature,
      publicKey: publicKey,
    );
    
    return verifyResult;
  }
  
  // ==================== Test Helper Methods ====================
  
  /// Pre-configure identity (useful for deterministic tests)
  void setIdentity({
    required String peerID,
    required Uint8List privateKey,
    required Uint8List publicKey,
    required Uint8List encryptionPrivateKey,
    required Uint8List encryptionPublicKey,
  }) {
    _peerID = peerID;
    _privateKey = privateKey;
    _publicKey = publicKey;
    _encryptionPrivateKey = encryptionPrivateKey;
    _encryptionPublicKey = encryptionPublicKey;
  }
  
  /// Reset all state and counters
  void reset() {
    _peerID = null;
    _privateKey = null;
    _publicKey = null;
    _encryptionPrivateKey = null;
    _encryptionPublicKey = null;
    
    shouldFailInitialize = false;
    shouldFailGenerate = false;
    shouldFailLoad = false;
    shouldFailSign = false;
    shouldFailVerify = false;
    
    initializeCallCount = 0;
    generateCallCount = 0;
    loadCallCount = 0;
    signCallCount = 0;
    verifyCallCount = 0;
  }
  
  /// Create a simple test identity with predictable values
  Future<void> createTestIdentity([String suffix = '']) async {
    await Future.delayed(const Duration(milliseconds: 10));
    
    _privateKey = Uint8List.fromList(List.generate(32, (i) => i));
    _publicKey = Uint8List.fromList(List.generate(32, (i) => i + 100));
    _encryptionPrivateKey = Uint8List.fromList(List.generate(32, (i) => i + 50));
    _encryptionPublicKey = Uint8List.fromList(List.generate(32, (i) => i + 150));
    _peerID = 'test_peer_$suffix${DateTime.now().millisecondsSinceEpoch}';
  }
}
