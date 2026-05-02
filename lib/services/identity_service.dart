import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'interfaces/i_crypto_service.dart';
import 'interfaces/i_identity_service.dart';
import 'p2p_bridge.dart';
import '../models/app_error.dart';
import '../utils/result.dart';
import '../utils/logger.dart';

/// Identity Service - Verwaltet PeerID und Private Key
/// 
/// Responsibilities:
/// - Generate/Load Ed25519 Identity
/// - Secure Storage (Keychain/KeyStore)
/// - Sign/Verify Messages
class IdentityService implements IIdentityService {
  // Dependencies injected via constructor
  final ICryptoService _crypto;
  final FlutterSecureStorage _storage;

  // Singleton pattern removed - now managed by Riverpod
  IdentityService({
    required ICryptoService crypto,
    FlutterSecureStorage? storage,
  })  : _crypto = crypto,
        _storage = storage ?? const FlutterSecureStorage();

  static const _keyPrivateKey = 'identity_private_key';
  static const _keyPeerID = 'identity_peer_id';
  static const _keyEncryptionPrivateKey = 'encryption_private_key';
  static const _keyEncryptionPublicKey = 'encryption_public_key';

  String? _peerID;
  Uint8List? _privateKey;  // Ed25519 for signatures
  Uint8List? _publicKey;    // Ed25519 public key
  
  // X25519 keys for encryption (separate from identity)
  Uint8List? _encryptionPrivateKey;
  Uint8List? _encryptionPublicKey;

  /// Current PeerID (read-only)
  String? get peerID => _peerID;

  /// Ed25519 private key for signatures (read-only)
  Uint8List? get privateKey => _privateKey;

  /// Ed25519 public key (read-only)
  Uint8List? get publicKey => _publicKey;
  
  /// X25519 encryption private key (read-only)
  Uint8List? get encryptionPrivateKey => _encryptionPrivateKey;
  
  /// X25519 encryption public key (read-only)
  Uint8List? get encryptionPublicKey => _encryptionPublicKey;

  bool get hasIdentity => _peerID != null && _privateKey != null && _encryptionPrivateKey != null;

  /// Load or generate identity
  @override
  Future<Result<void, AppError>> initialize() async {
    return resultOfAsync(
      () async {
        Logger.debug('🆔 IdentityService.initialize() called');
        
        // Try to load existing identity
        final loadResult = await loadIdentity();
        
        if (loadResult.isFailure) {
          throw loadResult.errorOrNull ?? IdentityError(
            message: 'Failed to check existing identity',
            type: IdentityErrorType.loadFailed,
          );
        }
        
        final success = loadResult.valueOrNull ?? false;
        
        if (!success) {
          Logger.debug('🔑 No existing identity found, generating new one...');
          // Generate new identity
          final genResult = await generateIdentity();
          if (genResult.isFailure) {
            throw genResult.errorOrNull ?? IdentityError(
              message: 'Failed to generate identity',
              type: IdentityErrorType.generationFailed,
            );
          }
        } else {
          Logger.success('🔑 Loaded existing identity: $_peerID');
          
          // VALIDATE: Check if the loaded identity is compatible with native library
          // If it starts with "QmGenerated" or "QmStub", it's from old stub code - regenerate!
          if (_peerID != null && (_peerID!.startsWith('QmGenerated') || _peerID!.startsWith('QmStub'))) {
            Logger.warning('Detected STUB identity from old implementation!');
            Logger.debug('🔄 Regenerating with real native library...');
            
            // Delete old fake identity
            final deleteResult = await deleteIdentity();
            if (deleteResult.isFailure) {
              throw deleteResult.errorOrNull ?? IdentityError(
                message: 'Failed to delete stub identity',
                type: IdentityErrorType.deleteFailed,
              );
            }
            
            // Generate real identity
            final genResult = await generateIdentity();
            if (genResult.isFailure) {
              throw genResult.errorOrNull ?? IdentityError(
                message: 'Failed to regenerate identity',
                type: IdentityErrorType.generationFailed,
              );
            }
          }
        }

        Logger.success('🆔 Identity initialized: $_peerID');
      },
      (e, stackTrace) => IdentityError(
        message: 'Identity initialization failed',
        type: IdentityErrorType.notInitialized,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  /// Generate new Ed25519 identity via gomobile
  @override
  Future<Result<void, AppError>> generateIdentity() async {
    return resultOfAsync(
      () async {
        Logger.debug('🔑 Calling P2PBridge.generateIdentity()...');
        
        // 1. Generate Ed25519 identity via libp2p
        final result = await P2PBridge.generateIdentity();
        
        Logger.debug('🔑 Got result from P2PBridge');
        Logger.debug('privateKey length: ${result.privateKey.length}');
        Logger.debug('peerID: ${result.peerID}');
        
        _privateKey = result.privateKey;
        _peerID = result.peerID;
        
        // Extract Ed25519 public key
        if (_privateKey!.length >= 32) {
          _publicKey = _privateKey!.length == 64
              ? _privateKey!.sublist(32, 64)
              : _privateKey;
        }

        // 2. Generate separate X25519 encryption keys
        Logger.debug('🔐 Generating X25519 encryption keys...');
        final encryptionKeysResult = await _crypto.generateX25519KeyPair();
        
        if (encryptionKeysResult.isFailure) {
          throw encryptionKeysResult.errorOrNull ?? IdentityError(
            message: 'Failed to generate encryption keys',
            type: IdentityErrorType.keyGenerationFailed,
          );
        }
        
        final encryptionKeys = encryptionKeysResult.valueOrNull!;
        _encryptionPrivateKey = encryptionKeys.privateKey;
        _encryptionPublicKey = encryptionKeys.publicKey;
        Logger.success('X25519 keys generated (${_encryptionPublicKey!.length} byte public key)');

        // Save securely
        await _saveIdentity();

        Logger.success('Generated new identity: $_peerID');
      },
      (e, stackTrace) {
        Logger.error('Failed to generate identity', e, stackTrace);
        return IdentityError(
          message: 'Failed to generate identity',
          type: IdentityErrorType.generationFailed,
          details: e.toString(),
          stackTrace: stackTrace,
        );
      },
    );
  }

  /// Load existing identity from secure storage
  @override
  Future<Result<bool, AppError>> loadIdentity() async {
    return resultOfAsync(
      () async {
        final privateKeyStr = await _storage.read(key: _keyPrivateKey);
        final peerIDStr = await _storage.read(key: _keyPeerID);
        final encPrivKeyStr = await _storage.read(key: _keyEncryptionPrivateKey);
        final encPubKeyStr = await _storage.read(key: _keyEncryptionPublicKey);

        if (privateKeyStr == null || peerIDStr == null) {
          return false;
        }

        _privateKey = _base64ToBytes(privateKeyStr);
        _peerID = peerIDStr;
        
        // Extract Ed25519 public key
        if (_privateKey!.length >= 32) {
          _publicKey = _privateKey!.length == 64
              ? _privateKey!.sublist(32, 64)
              : _privateKey;
        }

        // Load encryption keys if available
        if (encPrivKeyStr != null && encPubKeyStr != null) {
          _encryptionPrivateKey = _base64ToBytes(encPrivKeyStr);
          _encryptionPublicKey = _base64ToBytes(encPubKeyStr);
          Logger.success('Loaded identity with X25519 encryption keys: $_peerID');
        } else {
          Logger.warning('Identity loaded but no X25519 keys found - will regenerate');
          return false; // Force regeneration to get encryption keys
        }

        Logger.success('Loaded identity: $_peerID');
        return true;
      },
      (e, stackTrace) {
        Logger.warning('Failed to load identity: $e');
        return IdentityError(
          message: 'Failed to load identity',
          type: IdentityErrorType.loadFailed,
          details: e.toString(),
          stackTrace: stackTrace,
        );
      },
    );
  }

  /// Save identity to secure storage
  Future<void> _saveIdentity() async {
    if (_privateKey == null || _peerID == null || _encryptionPrivateKey == null || _encryptionPublicKey == null) {
      throw IdentityException('No identity to save');
    }

    await _storage.write(
      key: _keyPrivateKey,
      value: _bytesToBase64(_privateKey!),
    );
    await _storage.write(
      key: _keyPeerID,
      value: _peerID!,
    );
    await _storage.write(
      key: _keyEncryptionPrivateKey,
      value: _bytesToBase64(_encryptionPrivateKey!),
    );
    await _storage.write(
      key: _keyEncryptionPublicKey,
      value: _bytesToBase64(_encryptionPublicKey!),
    );
  }

  /// Delete identity (for testing/reset)
  @override
  Future<Result<void, AppError>> deleteIdentity() async {
    return resultOfAsync(
      () async {
        await _storage.delete(key: _keyPrivateKey);
        await _storage.delete(key: _keyPeerID);
        await _storage.delete(key: _keyEncryptionPrivateKey);
        await _storage.delete(key: _keyEncryptionPublicKey);
        _privateKey = null;
        _peerID = null;
        _publicKey = null;
        _encryptionPrivateKey = null;
        _encryptionPublicKey = null;
        Logger.info('Identity deleted');
      },
      (e, stackTrace) => IdentityError(
        message: 'Failed to delete identity',
        type: IdentityErrorType.deleteFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  /// Sign data with private key using libp2p's native Ed25519
  Future<Result<Uint8List, AppError>> sign(Uint8List data) async {
    return resultOfAsync(
      () async {
        if (_privateKey == null) {
          throw IdentityError(
            message: 'No private key available',
            type: IdentityErrorType.notInitialized,
          );
        }

        // Use libp2p's native P2P_Sign via FFI
        // This ensures compatibility with oasis_node which uses libp2p's pub.Verify()
        final signature = await P2PBridge.sign(data);
        
        Logger.debug('libp2p signature created:');
        Logger.debug('   Data length: ${data.length} bytes');
        Logger.debug('   Signature length: ${signature.length} bytes');
        
        return signature;
      },
      (e, stackTrace) => IdentityError(
        message: 'Signature generation failed',
        type: IdentityErrorType.signatureFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  /// Verify signature from another peer using libp2p's native Ed25519
  Future<Result<bool, AppError>> verify({
    required Uint8List data,
    required Uint8List signature,
    required Uint8List publicKey,
  }) async {
    return resultOfAsync(
      () async {
        // For receiving messages, we need the sender's PeerID to verify
        // But we don't have it in this interface. This method is problematic.
        // For now, we'll extract the PeerID if we can, or return a placeholder.
        
        // NOTE: This verify() method needs the sender's PeerID to work with libp2p!
        // The caller should use P2PBridge.verify() directly with the PeerID.
        throw IdentityError(
          message: 'Use P2PBridge.verify() with sender PeerID instead',
          type: IdentityErrorType.verificationFailed,
        );
      },
      (e, stackTrace) => IdentityError(
        message: 'Signature verification failed',
        type: IdentityErrorType.verificationFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  // Helper methods
  String _bytesToBase64(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Uint8List _base64ToBytes(String hex) => Uint8List.fromList(
        List.generate(
          hex.length ~/ 2,
          (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      );
}

class IdentityException implements Exception {
  final String message;
  IdentityException(this.message);

  @override
  String toString() => 'IdentityException: $message';
}
