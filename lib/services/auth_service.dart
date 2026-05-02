import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

/// Auth Service - App-Lock mit PIN/Passwort
/// 
/// Sicherheitsfeatures:
/// - PBKDF2 Hashing mit 100k Iterationen
/// - Kryptographisch sicherer Salt (16 bytes)
/// - FlutterSecureStorage für Hash/Salt
/// - Rate-Limiting gegen Brute-Force
class AuthService {
  final FlutterSecureStorage _secureStorage;
  final Random _random = Random.secure();
  
  // Storage Keys
  static const _keyAuthHash = 'app_auth_hash';
  static const _keySalt = 'app_auth_salt';
  static const _keyType = 'app_auth_type'; // 'pin' or 'password'
  static const _keyPinLength = 'app_auth_pin_length'; // PIN length (4, 5, or 6)
  static const _keyEnabled = 'app_auth_enabled';
  static const _keyFailedAttempts = 'app_auth_failed_attempts';
  static const _keyLastFailedTime = 'app_auth_last_failed_time';
  
  // PBKDF2 Configuration
  static const int _iterations = 100000;
  static const int _keyLength = 32;
  static const int _saltLength = 16;
  
  // Rate-Limiting Configuration
  static const Map<int, int> _delaySeconds = {
    3: 5,      // Nach 3 Versuchen: 5 Sekunden
    4: 15,     // Nach 4 Versuchen: 15 Sekunden
    5: 60,     // Nach 5 Versuchen: 60 Sekunden
    6: 300,    // Nach 6+ Versuchen: 5 Minuten
  };
  
  AuthService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();
  
  // ==================== PUBLIC API ====================
  
  /// Prüft ob App-Lock aktiviert ist
  Future<bool> isAuthEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_keyEnabled) ?? false;
    } catch (e) {
      Logger.error('Failed to check if auth is enabled', e);
      return false;
    }
  }
  
  /// Aktiviert App-Lock mit neuem PIN/Passwort
  /// 
  /// [value] - PIN (4-6 Ziffern) oder Passwort (min 6 Zeichen)
  /// [isPin] - true für PIN, false für Passwort
  Future<bool> enableAuth({
    required String value,
    required bool isPin,
  }) async {
    try {
      // Validierung
      if (isPin) {
        if (!RegExp(r'^\d{4,6}$').hasMatch(value)) {
          Logger.warning('Invalid PIN format (must be 4-6 digits)');
          return false;
        }
      } else {
        if (value.length < 6) {
          Logger.warning('Password too short (min 6 characters)');
          return false;
        }
      }
      
      // Generiere Salt
      final salt = _generateSalt();
      
      // Hash mit PBKDF2
      final hash = _hashPassword(value, salt);
      
      // Speichere sicher
      await _secureStorage.write(key: _keyAuthHash, value: base64Encode(hash));
      await _secureStorage.write(key: _keySalt, value: base64Encode(salt));
      await _secureStorage.write(key: _keyType, value: isPin ? 'pin' : 'password');
      
      // Speichere PIN-Länge wenn PIN
      if (isPin) {
        await _secureStorage.write(key: _keyPinLength, value: value.length.toString());
      } else {
        await _secureStorage.delete(key: _keyPinLength);
      }
      
      // Aktiviere in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEnabled, true);
      
      // Reset failed attempts
      await _resetFailedAttempts();
      
      Logger.success('🔒 App-Lock enabled (${isPin ? 'PIN' : 'Password'})');
      return true;
    } catch (e, stackTrace) {
      Logger.error('Failed to enable auth', e, stackTrace);
      return false;
    }
  }
  
  /// Deaktiviert App-Lock
  /// 
  /// Erfordert erfolgreiche Authentifizierung vorher!
  Future<bool> disableAuth() async {
    try {
      // Lösche sichere Daten
      await _secureStorage.delete(key: _keyAuthHash);
      await _secureStorage.delete(key: _keySalt);
      await _secureStorage.delete(key: _keyType);
      
      // Deaktiviere in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyEnabled, false);
      
      // Reset failed attempts
      await _resetFailedAttempts();
      
      Logger.success('🔓 App-Lock disabled');
      return true;
    } catch (e, stackTrace) {
      Logger.error('Failed to disable auth', e, stackTrace);
      return false;
    }
  }
  
  /// Verifiziert eingegebenen PIN/Passwort
  /// 
  /// Returns true bei Erfolg, false bei Fehler
  /// Implementiert Rate-Limiting gegen Brute-Force
  Future<AuthVerificationResult> verifyAuth(String input) async {
    try {
      // Check Rate-Limiting
      final delayResult = await _checkRateLimit();
      if (delayResult != null) {
        return delayResult;
      }
      
      // Lade gespeicherte Daten
      final hashStr = await _secureStorage.read(key: _keyAuthHash);
      final saltStr = await _secureStorage.read(key: _keySalt);
      
      if (hashStr == null || saltStr == null) {
        Logger.error('Auth data not found in secure storage');
        return AuthVerificationResult(
          success: false,
          error: 'Authentication data not found',
        );
      }
      
      final storedHash = base64Decode(hashStr);
      final salt = base64Decode(saltStr);
      
      // Hash Input
      final inputHash = _hashPassword(input, salt);
      
      // Vergleiche
      final isValid = _compareHashes(storedHash, inputHash);
      
      if (isValid) {
        // Erfolg → Reset failed attempts
        await _resetFailedAttempts();
        Logger.success('✅ Authentication successful');
        return AuthVerificationResult(success: true);
      } else {
        // Fehler → Increment failed attempts
        await _incrementFailedAttempts();
        Logger.warning('❌ Authentication failed');
        return AuthVerificationResult(
          success: false,
          error: 'Invalid PIN/Password',
        );
      }
    } catch (e, stackTrace) {
      Logger.error('Error during authentication', e, stackTrace);
      return AuthVerificationResult(
        success: false,
        error: 'Authentication error: $e',
      );
    }
  }
  
  /// Ändert PIN/Passwort
  /// 
  /// Erfordert aktuellen PIN/Passwort zur Verifikation!
  Future<bool> changeAuth({
    required String currentValue,
    required String newValue,
    required bool isPin,
  }) async {
    // Verifiziere aktuellen Wert
    final verifyResult = await verifyAuth(currentValue);
    if (!verifyResult.success) {
      Logger.warning('Cannot change auth: current value incorrect');
      return false;
    }
    
    // Deaktiviere und aktiviere neu
    await disableAuth();
    return await enableAuth(value: newValue, isPin: isPin);
  }
  
  /// Gibt Auth-Typ zurück ('pin' oder 'password')
  Future<String?> getAuthType() async {
    try {
      return await _secureStorage.read(key: _keyType);
    } catch (e) {
      Logger.error('Failed to get auth type', e);
      return null;
    }
  }
  
  /// Gibt PIN-Länge zurück (4, 5, oder 6)
  /// Gibt null zurück wenn kein PIN aktiv ist
  Future<int?> getPinLength() async {
    try {
      final lengthStr = await _secureStorage.read(key: _keyPinLength);
      if (lengthStr == null) return null;
      return int.tryParse(lengthStr);
    } catch (e) {
      Logger.error('Failed to get PIN length', e);
      return null;
    }
  }
  
  // ==================== PRIVATE HELPERS ====================
  
  /// Generiert kryptographisch sicheren Salt
  Uint8List _generateSalt() {
    final salt = Uint8List(_saltLength);
    for (int i = 0; i < _saltLength; i++) {
      salt[i] = _random.nextInt(256);
    }
    return salt;
  }
  
  /// Hasht Passwort mit PBKDF2
  Uint8List _hashPassword(String password, Uint8List salt) {
    // PBKDF2 mit HMAC-SHA256
    final codec = Pbkdf2(
      macAlgorithm: Hmac(sha256, []), // HMAC mit SHA256
      iterations: _iterations,
      bits: _keyLength * 8,
    );
    
    final secretKey = codec.deriveKeyFromPassword(
      password: password,
      nonce: salt.toList(),
    );
    
    return Uint8List.fromList(secretKey.extractBytes());
  }
  
  /// Vergleicht zwei Hashes in konstanter Zeit (gegen Timing-Attacks)
  bool _compareHashes(Uint8List hash1, Uint8List hash2) {
    if (hash1.length != hash2.length) return false;
    
    int result = 0;
    for (int i = 0; i < hash1.length; i++) {
      result |= hash1[i] ^ hash2[i];
    }
    return result == 0;
  }
  
  /// Prüft Rate-Limiting und gibt ggf. Delay zurück
  Future<AuthVerificationResult?> _checkRateLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final failedAttempts = prefs.getInt(_keyFailedAttempts) ?? 0;
    
    if (failedAttempts >= 3) {
      final lastFailedTime = prefs.getInt(_keyLastFailedTime) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final timeSinceLastFailed = (now - lastFailedTime) ~/ 1000; // Sekunden
      
      // Bestimme erforderliches Delay
      int requiredDelay = 0;
      if (failedAttempts >= 6) {
        requiredDelay = _delaySeconds[6]!;
      } else {
        requiredDelay = _delaySeconds[failedAttempts] ?? 0;
      }
      
      if (timeSinceLastFailed < requiredDelay) {
        final remainingSeconds = requiredDelay - timeSinceLastFailed;
        Logger.warning('🚫 Rate limit active: wait $remainingSeconds seconds');
        return AuthVerificationResult(
          success: false,
          error: 'Too many failed attempts',
          remainingDelaySeconds: remainingSeconds,
        );
      }
    }
    
    return null;
  }
  
  /// Erhöht failed attempts Counter
  Future<void> _incrementFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_keyFailedAttempts) ?? 0;
    await prefs.setInt(_keyFailedAttempts, current + 1);
    await prefs.setInt(_keyLastFailedTime, DateTime.now().millisecondsSinceEpoch);
  }
  
  /// Setzt failed attempts zurück
  Future<void> _resetFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFailedAttempts);
    await prefs.remove(_keyLastFailedTime);
  }
}

/// PBKDF2 Implementation für Dart
class Pbkdf2 {
  final Hmac macAlgorithm;
  final int iterations;
  final int bits;
  
  Pbkdf2({
    required this.macAlgorithm,
    required this.iterations,
    required this.bits,
  });
  
  SecretKey deriveKeyFromPassword({
    required String password,
    required List<int> nonce,
  }) {
    final passwordBytes = utf8.encode(password);
    final dkLen = bits ~/ 8;
    final hLen = 32; // SHA256 output length
    final l = (dkLen / hLen).ceil();
    
    final result = <int>[];
    
    for (int i = 1; i <= l; i++) {
      final block = _computeBlock(passwordBytes, nonce, i);
      result.addAll(block);
    }
    
    return SecretKey(result.sublist(0, dkLen));
  }
  
  List<int> _computeBlock(List<int> password, List<int> salt, int blockNumber) {
    // U1 = PRF(password, salt + blockNumber)
    final saltWithBlock = [...salt, ...int32ToBytes(blockNumber)];
    var u = _hmac(password, saltWithBlock);
    final result = List<int>.from(u);
    
    // U2 to Un
    for (int i = 1; i < iterations; i++) {
      u = _hmac(password, u);
      for (int j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    
    return result;
  }
  
  List<int> _hmac(List<int> key, List<int> data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(data).bytes;
  }
  
  List<int> int32ToBytes(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }
}

/// Secret Key Container
class SecretKey {
  final List<int> _bytes;
  
  SecretKey(this._bytes);
  
  List<int> extractBytes() => List<int>.from(_bytes);
}

/// Verification Result
class AuthVerificationResult {
  final bool success;
  final String? error;
  final int? remainingDelaySeconds;
  
  AuthVerificationResult({
    required this.success,
    this.error,
    this.remainingDelaySeconds,
  });
}
