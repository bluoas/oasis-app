import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import '../models/app_error.dart';
import '../utils/result.dart';
import 'interfaces/i_crypto_service.dart';
import 'p2p_bridge.dart';
import '../utils/logger.dart';

/// Crypto Service - E2E Verschlüsselung
/// 
/// Verwendet X25519 (ECDH) + ChaCha20-Poly1305 (AEAD)
/// Kompatibel mit NaCl Box (siehe APP_INTEGRATION.md)
class CryptoService implements ICryptoService {
  // Singleton pattern removed - now managed by Riverpod
  CryptoService();

  final _random = Random.secure();
  final _algorithm = Chacha20.poly1305Aead();

  @override
  /// Encrypt message for recipient
  /// 
  /// Uses X25519 ECDH for key exchange and ChaCha20-Poly1305 AEAD for encryption
  Future<Result<Uint8List, AppError>> encrypt({
    required String plaintext,
    required Uint8List recipientPublicKey,
    required Uint8List senderPrivateKey,
  }) async {
    return resultOfAsync(
      () async {
        Logger.debug('🔐 ENCRYPT: Recipient public key (${recipientPublicKey.length} bytes): ${base64Encode(recipientPublicKey)}');
        
        // Validate X25519 key sizes
        if (recipientPublicKey.length != 32) {
          throw Exception('X25519 public key must be 32 bytes, got ${recipientPublicKey.length}');
        }
        if (senderPrivateKey.length != 32) {
          throw Exception('X25519 private key must be 32 bytes, got ${senderPrivateKey.length}');
        }

        // 1. Convert keys to SimpleKeyPair
        final senderKeyPair = SimpleKeyPairData(
          senderPrivateKey,
          publicKey: SimplePublicKey([], type: KeyPairType.x25519),
          type: KeyPairType.x25519,
        );

        final recipientPubKey = SimplePublicKey(
          recipientPublicKey,
          type: KeyPairType.x25519,
        );

        // 2. Encrypt with shared secret
        final secretBox = await _algorithm.encrypt(
          utf8.encode(plaintext),
          secretKey: await _deriveSharedSecret(senderKeyPair, recipientPubKey),
        );

        // 3. Pack: nonce + ciphertext + mac
        final result = Uint8List.fromList([
          ...secretBox.nonce,
          ...secretBox.cipherText,
          ...secretBox.mac.bytes,
        ]);

        return result;
      },
      (e, stackTrace) => CryptoError(
        message: 'Encryption failed',
        type: CryptoErrorType.encryptionFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  /// Decrypt message from sender
  /// 
  /// Uses X25519 ECDH for key exchange and ChaCha20-Poly1305 AEAD for decryption
  @override
  Future<Result<String, AppError>> decrypt({
    required Uint8List ciphertext,
    required Uint8List senderPublicKey,
    required Uint8List recipientPrivateKey,
  }) async {
    return resultOfAsync(
      () async {
        Logger.debug('🔓 DECRYPT: Sender public key (${senderPublicKey.length} bytes): ${base64Encode(senderPublicKey)}');
        
        // 1. Unpack
        if (ciphertext.length < 12 + 16) {
          throw Exception('Invalid ciphertext length');
        }

        final nonce = ciphertext.sublist(0, 12);
        final encrypted = ciphertext.sublist(12, ciphertext.length - 16);
        final mac = ciphertext.sublist(ciphertext.length - 16);

        // Validate X25519 key sizes
        if (senderPublicKey.length != 32) {
          throw Exception('X25519 public key must be 32 bytes, got ${senderPublicKey.length}');
        }
        if (recipientPrivateKey.length != 32) {
          throw Exception('X25519 private key must be 32 bytes, got ${recipientPrivateKey.length}');
        }

        // 2. Convert keys
        final recipientKeyPair = SimpleKeyPairData(
          recipientPrivateKey,
          publicKey: SimplePublicKey([], type: KeyPairType.x25519),
          type: KeyPairType.x25519,
        );

        final senderPubKey = SimplePublicKey(
          senderPublicKey,
          type: KeyPairType.x25519,
        );

        // 3. Decrypt with shared secret
        final secretBox = SecretBox(
          encrypted,
          nonce: nonce,
          mac: Mac(mac),
        );

        final plaintext = await _algorithm.decrypt(
          secretBox,
          secretKey: await _deriveSharedSecret(recipientKeyPair, senderPubKey),
        );

        return utf8.decode(plaintext);
      },
      (e, stackTrace) => CryptoError(
        message: 'Decryption failed',
        type: CryptoErrorType.decryptionFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  /// Derive shared secret via ECDH
  Future<SecretKey> _deriveSharedSecret(
    SimpleKeyPairData keyPair,
    PublicKey publicKey,
  ) async {
    final x25519 = X25519();
    return await x25519.sharedSecretKey(
      keyPair: keyPair,
      remotePublicKey: publicKey,
    );
  }

  /// Generate nonce for replay protection
  @override
  Result<Uint8List, AppError> generateNonce({int length = 24}) {
    return resultOf(
      () => Uint8List.fromList(
        List.generate(length, (_) => _random.nextInt(256)),
      ),
      (e, stackTrace) => CryptoError(
        message: 'Failed to generate nonce',
        type: CryptoErrorType.keyGenerationFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  /// Generate Ed25519 key pair for signing
  /// 
  /// WICHTIG: Für libp2p Identity wird Ed25519 verwendet (nicht X25519)
  /// Die gomobile Bridge macht die Konvertierung
  Future<KeyPairResult> generateKeyPair() async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyData = await keyPair.extract();

    return KeyPairResult(
      privateKey: Uint8List.fromList(privateKeyData.bytes),
      publicKey: Uint8List.fromList(publicKey.bytes),
    );
  }

  @override
  /// Generate X25519 key pair for encryption
  /// 
  /// These keys are SEPARATE from Ed25519 identity keys
  /// X25519 is specifically for ECDH key exchange and encryption
  Future<Result<({Uint8List privateKey, Uint8List publicKey}), AppError>> generateX25519KeyPair() async {
    return resultOfAsync(
      () async {
        final algorithm = X25519();
        final keyPair = await algorithm.newKeyPair();
        final publicKey = await keyPair.extractPublicKey();
        final privateKeyData = await keyPair.extractPrivateKeyBytes();

        return (
          privateKey: Uint8List.fromList(privateKeyData),
          publicKey: Uint8List.fromList(publicKey.bytes),
        );
      },
      (e, stackTrace) => CryptoError(
        message: 'Failed to generate X25519 key pair',
        type: CryptoErrorType.keyGenerationFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  /// Sign data with Ed25519
  Future<Result<Uint8List, AppError>> sign({
    required Uint8List data,
    required Uint8List privateKey,
  }) async {
    return resultOfAsync(
      () async {
        // Ed25519 private key from gomobile is 64 or 68 bytes
        // Format: [32 bytes seed | 32 bytes public key | optional 4 bytes header]
        // libp2p expects signature from the FULL keypair (seed + public key)
        
        final Uint8List seed;
        final Uint8List publicKeyBytes;
        
        if (privateKey.length >= 64) {
          // Extract seed and public key from 64 or 68 byte key
          seed = privateKey.sublist(0, 32);
          publicKeyBytes = privateKey.sublist(32, 64);
        } else if (privateKey.length == 32) {
          // Only seed provided, derive public key
          seed = privateKey;
          final algorithm = Ed25519();
          final tempKeyPair = await algorithm.newKeyPairFromSeed(seed.toList());
          final tempPublicKey = await tempKeyPair.extractPublicKey();
          publicKeyBytes = Uint8List.fromList(tempPublicKey.bytes);
        } else {
          throw Exception('Invalid Ed25519 private key length: ${privateKey.length}');
        }

        // Create Ed25519 keypair with both seed and public key
        // This ensures the signature is compatible with libp2p's ExtractPublicKey()
        final algorithm = Ed25519();
        final keyPair = SimpleKeyPairData(
          seed.toList(),
          publicKey: SimplePublicKey(publicKeyBytes.toList(), type: KeyPairType.ed25519),
          type: KeyPairType.ed25519,
        );

        // Sign the data bytes
        final signature = await algorithm.sign(
          data.toList(),
          keyPair: keyPair,
        );

        Logger.debug('🔐 Ed25519 signature created:');
        Logger.debug('Data length: ${data.length} bytes');
        Logger.debug('Seed length: ${seed.length} bytes');
        Logger.debug('Public key length: ${publicKeyBytes.length} bytes');
        Logger.debug('Signature length: ${signature.bytes.length} bytes');

        return Uint8List.fromList(signature.bytes);
      },
      (e, stackTrace) => CryptoError(
        message: 'Signature generation failed',
        type: CryptoErrorType.signatureFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  /// Verify signature
  Future<Result<bool, AppError>> verify({
    required Uint8List data,
    required Uint8List signature,
    required Uint8List publicKey,
  }) async {
    return resultOfAsync(
      () async {
        final algorithm = Ed25519();
        final sig = Signature(signature, publicKey: SimplePublicKey(
          publicKey,
          type: KeyPairType.ed25519,
        ));

        return await algorithm.verify(
          data,
          signature: sig,
        );
      },
      (e, stackTrace) => CryptoError(
        message: 'Signature verification failed',
        type: CryptoErrorType.verificationFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  /// Generate Ed25519 key pair for signing
  Future<Result<({Uint8List privateKey, Uint8List publicKey}), AppError>> generateEd25519KeyPair() async {
    return resultOfAsync(
      () async {
        final algorithm = Ed25519();
        final keyPair = await algorithm.newKeyPair();
        final publicKey = await keyPair.extractPublicKey();
        final privateKeyData = await keyPair.extractPrivateKeyBytes();

        return (
          privateKey: Uint8List.fromList(privateKeyData),
          publicKey: Uint8List.fromList(publicKey.bytes),
        );
      },
      (e, stackTrace) => CryptoError(
        message: 'Failed to generate Ed25519 key pair',
        type: CryptoErrorType.keyGenerationFailed,
        details: e.toString(),
        stackTrace: stackTrace,
      ),
    );
  }

  @override
  /// Derive X25519 public key from Ed25519 public key
  Future<Result<Uint8List, AppError>> ed25519PublicKeyToX25519(Uint8List ed25519PublicKey) async {
    return Failure(CryptoError(
      message: 'Use separate X25519 keys for encryption',
      type: CryptoErrorType.invalidKey,
      details: 'Ed25519 to X25519 conversion not implemented',
    ));
  }

  @override
  /// Derive X25519 private key from Ed25519 private key
  Future<Uint8List> ed25519PrivateKeyToX25519(Uint8List ed25519PrivateKey) async {
    // This is a placeholder - proper implementation would use curve25519 conversion
    // For now, we use separate key pairs for signing and encryption
    throw UnimplementedError('Use separate X25519 keys for encryption');
  }

  /// Convert PeerID to Public Key
  /// 
  /// Uses native libp2p function to extract the public key from a PeerID
  /// PeerID format: Base58-encoded multihash containing the public key
  /// See: https://github.com/libp2p/specs/blob/master/peer-ids/peer-ids.md
  Future<Uint8List> peerIDToPublicKey(String peerID) async {
    try {
      // Use native libp2p function to extract public key
      final publicKeyBytes = await P2PBridge.publicKeyFromPeerID(peerID);
      
      // The returned bytes are marshalled libp2p public key format
      // For Ed25519, this includes a protobuf header. We need just the 32-byte key.
      // Format: [protobuf header (variable length)] + [32 bytes Ed25519 public key]
      
      // Parse the protobuf-encoded key (simple approach: last 32 bytes)
      if (publicKeyBytes.length >= 32) {
        final ed25519Key = publicKeyBytes.sublist(publicKeyBytes.length - 32);
        Logger.success('Extracted Ed25519 public key (${ed25519Key.length} bytes) from PeerID ${peerID.substring(peerID.length - 8)}');
        return ed25519Key;
      } else {
        throw CryptoException('Invalid public key length: ${publicKeyBytes.length}');
      }
    } catch (e) {
      Logger.error('Failed to extract public key from PeerID', e);
      rethrow;
    }
  }

  /// Convert Public Key to PeerID
  /// 
  /// TODO: Echte Implementierung mit libp2p peer.ID Encoding
  String publicKeyToPeerID(Uint8List publicKey) {
    // STUB: In Realität muss Public Key enkodiert werden
    // Siehe libp2p spec
    
    // Für Testing: Fake PeerID
    return 'Qm${publicKey.fold<int>(0, (sum, b) => sum + b)}';
  }
}

class KeyPairResult {
  final Uint8List privateKey;
  final Uint8List publicKey;

  KeyPairResult({
    required this.privateKey,
    required this.publicKey,
  });
}

class CryptoException implements Exception {
  final String message;
  CryptoException(this.message);

  @override
  String toString() => 'CryptoException: $message';
}
