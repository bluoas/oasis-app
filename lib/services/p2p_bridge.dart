import 'dart:typed_data';
import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:convert';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import '../utils/logger.dart';

/// P2P Bridge - FFI Interface to libp2p C library
/// 
/// REAL P2P IMPLEMENTATION - iOS ONLY
/// This uses native libp2p (Go) compiled as a static library for iOS.
/// No simulation, no stubs - this is production-ready peer-to-peer networking.
/// 
/// Features:
/// - Direct peer connections via DHT
/// - Relay fallback for offline peers
/// - E2E encrypted messaging
/// - Native libp2p with full NAT traversal

// FFI type definitions
typedef P2PInitializeC = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8> privateKeyBytes, ffi.Int32 privateKeyLen, ffi.Pointer<Utf8> bootstrapPeersJson, ffi.Pointer<Utf8> pskHex);
typedef P2PInitializeDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8> privateKeyBytes, int privateKeyLen, ffi.Pointer<Utf8> bootstrapPeersJson, ffi.Pointer<Utf8> pskHex);

typedef P2PConnectToPeerC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> multiaddr);
typedef P2PConnectToPeerDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> multiaddr);

typedef P2PSendToRelayC = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8> relayPeerID, ffi.Pointer<Utf8> protocol, ffi.Pointer<Utf8> jsonData);
typedef P2PSendToRelayDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8> relayPeerID, ffi.Pointer<Utf8> protocol, ffi.Pointer<Utf8> jsonData);

typedef P2PFindPeerC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> peerID);
typedef P2PFindPeerDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> peerID);

typedef P2PSendDirectC = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8> peerID, ffi.Pointer<Utf8> protocol, ffi.Pointer<Utf8> data, ffi.Int32 dataLen);
typedef P2PSendDirectDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8> peerID, ffi.Pointer<Utf8> protocol, ffi.Pointer<Utf8> data, int dataLen);

typedef P2PGenerateIdentityC = ffi.Pointer<Utf8> Function();
typedef P2PGenerateIdentityDart = ffi.Pointer<Utf8> Function();

typedef P2PFreeStringC = ffi.Void Function(ffi.Pointer<Utf8> str);
typedef P2PFreeStringDart = void Function(ffi.Pointer<Utf8> str);

typedef P2PCloseC = ffi.Void Function();
typedef P2PCloseDart = void Function();

// DHT type definitions
typedef P2PDHTProvideC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> keyStr);
typedef P2PDHTProvideDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> keyStr);

typedef P2PDHTFindProvidersC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> keyStr, ffi.Int32 maxProviders);
typedef P2PDHTFindProvidersDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> keyStr, int maxProviders);

typedef P2PGetHealthyNodesC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> peerIDStr, ffi.Pointer<Utf8> keyStr, ffi.Int32 maxProviders);
typedef P2PGetHealthyNodesDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> peerIDStr, ffi.Pointer<Utf8> keyStr, int maxProviders);

typedef P2PUnregisterPeerC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> nodePeerIDStr, ffi.Pointer<Utf8> userPeerIDStr);
typedef P2PUnregisterPeerDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> nodePeerIDStr, ffi.Pointer<Utf8> userPeerIDStr);

typedef P2PDHTFindPeerC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> peerIDStr);
typedef P2PDHTFindPeerDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> peerIDStr);

typedef P2PDHTGetStatusC = ffi.Pointer<Utf8> Function();
typedef P2PDHTGetStatusDart = ffi.Pointer<Utf8> Function();

typedef P2PPublicKeyFromPeerIDC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> peerIDStr);
typedef P2PPublicKeyFromPeerIDDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> peerIDStr);

typedef P2PSignC = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Uint8> dataBytes, ffi.Int32 dataLen);
typedef P2PSignDart = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Uint8> dataBytes, int dataLen);

typedef P2PVerifyC = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8> peerIDStr,
    ffi.Pointer<ffi.Uint8> dataBytes,
    ffi.Int32 dataLen,
    ffi.Pointer<ffi.Uint8> signatureBytes,
    ffi.Int32 signatureLen);
typedef P2PVerifyDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8> peerIDStr,
    ffi.Pointer<ffi.Uint8> dataBytes,
    int dataLen,
    ffi.Pointer<ffi.Uint8> signatureBytes,
    int signatureLen);

// Call Signal type definitions
typedef P2PSendCallSignalC = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8> nodePeerIDStr,
    ffi.Pointer<Utf8> targetPeerIDStr,
    ffi.Pointer<Utf8> signalTypeStr,
    ffi.Pointer<Utf8> callIDStr,
    ffi.Pointer<Utf8> dataJSON);
typedef P2PSendCallSignalDart = ffi.Pointer<Utf8> Function(
    ffi.Pointer<Utf8> nodePeerIDStr,
    ffi.Pointer<Utf8> targetPeerIDStr,
    ffi.Pointer<Utf8> signalTypeStr,
    ffi.Pointer<Utf8> callIDStr,
    ffi.Pointer<Utf8> dataJSON);

typedef P2PSetCallSignalHandlerC = ffi.Pointer<Utf8> Function();
typedef P2PSetCallSignalHandlerDart = ffi.Pointer<Utf8> Function();

typedef P2PGetPendingCallSignalsC = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> nodePeerIDStr);
typedef P2PGetPendingCallSignalsDart = ffi.Pointer<Utf8> Function(ffi.Pointer<Utf8> nodePeerIDStr);

class P2PBridge {
  // Singleton instance
  static P2PBridge? _instance;
  
  // FFI library and functions
  static ffi.DynamicLibrary? _lib;
  static P2PInitializeDart? _initialize;
  static P2PConnectToPeerDart? _connectToPeer;
  static P2PSendToRelayDart? _sendToRelay;
  static P2PFindPeerDart? _findPeer;
  static P2PSendDirectDart? _sendDirect;
  static P2PGenerateIdentityDart? _generateIdentity;
  static P2PFreeStringDart? _freeString;
  static P2PCloseDart? _close;
  
  // DHT functions
  static P2PDHTProvideDart? _dhtProvide;
  static P2PDHTFindProvidersDart? _dhtFindProviders;
  static P2PGetHealthyNodesDart? _getHealthyNodes;
  static P2PUnregisterPeerDart? _unregisterPeer;
  static P2PDHTFindPeerDart? _dhtFindPeer;
  static P2PDHTGetStatusDart? _dhtGetStatus;
  
  // Utility functions
  static P2PPublicKeyFromPeerIDDart? _publicKeyFromPeerID;
  static P2PSignDart? _sign;
  static P2PVerifyDart? _verify;
  
  // Call Signal functions
  static P2PSendCallSignalDart? _sendCallSignal;
  static P2PSetCallSignalHandlerDart? _setCallSignalHandler;
  static P2PGetPendingCallSignalsDart? _getPendingCallSignals;

  // Private constructor
  P2PBridge._();

  // Factory constructor for singleton
  factory P2PBridge() {
    Logger.debug('🔧 [P2PBRIDGE_FACTORY] P2PBridge factory called');
    _instance ??= P2PBridge._();
    Logger.success('[P2PBRIDGE_FACTORY] P2PBridge instance ready');
    return _instance!;
  }

  // Runtime state
  bool _initialized = false;
  String? _myPeerID;
  
  // Connection cache: multiaddr -> last successful connection time
  final Map<String, DateTime> _connectionCache = {};
  static const _connectionCacheDuration = Duration(minutes: 5);

  // Note: Relay/Bootstrap nodes are now configured in AppConfig (lib/config/app_config.dart)
  // No hardcoded node addresses here - use environment-specific configs instead

  // Load the C library
  static void _loadLibrary() {
    if (_lib != null) {
      Logger.debug('🔧 [P2PBRIDGE_LOAD] Library already loaded, skipping');
      return;
    }

    Logger.debug('🔧 [P2PBRIDGE_LOAD] Starting to load P2P native library...');

    try {
      if (Platform.isIOS) {
        Logger.debug('[P2PBRIDGE_LOAD] Platform: iOS - loading with DynamicLibrary.process()');
        // For iOS, the static library is linked into the process
        _lib = ffi.DynamicLibrary.process();
        Logger.success('[P2PBRIDGE_LOAD] DynamicLibrary.process() loaded (iOS)');
      } else if (Platform.isAndroid) {
        Logger.debug('[P2PBRIDGE_LOAD] Platform: Android - loading libp2p.so');
        // For Android, load the shared library from jniLibs
        _lib = ffi.DynamicLibrary.open('libp2p.so');
        Logger.success('[P2PBRIDGE_LOAD] libp2p.so loaded (Android)');
      } else {
        Logger.warning('[P2PBRIDGE_LOAD] ⚠️  Platform not supported for native P2P');
        return;
      }

      Logger.debug('[P2PBRIDGE_LOAD] Looking up FFI functions...');
      // Lookup functions
      Logger.debug('[P2PBRIDGE_LOAD] Looking up P2P_Initialize...');
      _initialize = _lib!
          .lookup<ffi.NativeFunction<P2PInitializeC>>('P2P_Initialize')
          .asFunction();
      Logger.success('[P2PBRIDGE_LOAD] P2P_Initialize found');
      
      Logger.debug('[P2PBRIDGE_LOAD] Looking up P2P_ConnectToPeer...');
      _connectToPeer = _lib!
          .lookup<ffi.NativeFunction<P2PConnectToPeerC>>('P2P_ConnectToPeer')
          .asFunction();
      Logger.success('[P2PBRIDGE_LOAD] P2P_ConnectToPeer found');
      
      _sendToRelay = _lib!
          .lookup<ffi.NativeFunction<P2PSendToRelayC>>('P2P_SendToRelay')
          .asFunction();
      Logger.success('P2P_SendToRelay found');
      
      _findPeer = _lib!
          .lookup<ffi.NativeFunction<P2PFindPeerC>>('P2P_FindPeer')
          .asFunction();
      Logger.success('P2P_FindPeer found');
      
      _sendDirect = _lib!
          .lookup<ffi.NativeFunction<P2PSendDirectC>>('P2P_SendDirect')
          .asFunction();
      Logger.success('P2P_SendDirect found');
      
      _generateIdentity = _lib!
          .lookup<ffi.NativeFunction<P2PGenerateIdentityC>>('P2P_GenerateIdentity')
          .asFunction();
      Logger.success('P2P_GenerateIdentity found');
      
      _freeString = _lib!
          .lookup<ffi.NativeFunction<P2PFreeStringC>>('P2P_FreeString')
          .asFunction();
      Logger.success('P2P_FreeString found');
      
      _close = _lib!
          .lookup<ffi.NativeFunction<P2PCloseC>>('P2P_Close')
          .asFunction();
      Logger.success('P2P_Close found');
      
      // DHT functions
      _dhtProvide = _lib!
          .lookup<ffi.NativeFunction<P2PDHTProvideC>>('P2P_DHT_Provide')
          .asFunction();
      Logger.success('P2P_DHT_Provide found');
      
      _dhtFindProviders = _lib!
          .lookup<ffi.NativeFunction<P2PDHTFindProvidersC>>('P2P_DHT_FindProviders')
          .asFunction();
      Logger.success('P2P_DHT_FindProviders found');
      
      _getHealthyNodes = _lib!
          .lookup<ffi.NativeFunction<P2PGetHealthyNodesC>>('P2P_GetHealthyNodes')
          .asFunction();
      Logger.success('P2P_GetHealthyNodes found');
      
      _unregisterPeer = _lib!
          .lookup<ffi.NativeFunction<P2PUnregisterPeerC>>('P2P_UnregisterPeer')
          .asFunction();
      Logger.success('P2P_UnregisterPeer found');
      
      _dhtFindPeer = _lib!
          .lookup<ffi.NativeFunction<P2PDHTFindPeerC>>('P2P_DHT_FindPeer')
          .asFunction();
      Logger.success('P2P_DHT_FindPeer found');
      
      _dhtGetStatus = _lib!
          .lookup<ffi.NativeFunction<P2PDHTGetStatusC>>('P2P_DHT_GetStatus')
          .asFunction();
      Logger.success('P2P_DHT_GetStatus found');
      
      _publicKeyFromPeerID = _lib!
          .lookup<ffi.NativeFunction<P2PPublicKeyFromPeerIDC>>('P2P_PublicKeyFromPeerID')
          .asFunction();
      Logger.success('P2P_PublicKeyFromPeerID found');
      
      _sign = _lib!
          .lookup<ffi.NativeFunction<P2PSignC>>('P2P_Sign')
          .asFunction();
      Logger.success('P2P_Sign found');
      
      _verify = _lib!
          .lookup<ffi.NativeFunction<P2PVerifyC>>('P2P_Verify')
          .asFunction();
      Logger.success('P2P_Verify found');
      
      _sendCallSignal = _lib!
          .lookup<ffi.NativeFunction<P2PSendCallSignalC>>('P2P_SendCallSignal')
          .asFunction();
      Logger.success('P2P_SendCallSignal found');
      
      _setCallSignalHandler = _lib!
          .lookup<ffi.NativeFunction<P2PSetCallSignalHandlerC>>('P2P_SetCallSignalHandler')
          .asFunction();
      Logger.success('P2P_SetCallSignalHandler found');
      
      _getPendingCallSignals = _lib!
          .lookup<ffi.NativeFunction<P2PGetPendingCallSignalsC>>('P2P_GetPendingCallSignals')
          .asFunction();
      Logger.success('P2P_GetPendingCallSignals found');

      Logger.success('P2P FFI library loaded successfully - all functions available');
    } catch (e, stackTrace) {
      Logger.error('Failed to load P2P library', e, stackTrace);
      throw Exception('Failed to load native P2P library. Make sure libp2p_ios.a is properly linked in Xcode: $e');
    }
  }

  /// Initialize libp2p host with resolved bootstrap peers
  /// 
  /// [psk] - Pre-Shared Key for private network authentication (null = public network)
  Future<void> initialize(Uint8List privateKey, List<String> bootstrapPeers, {String? psk}) async {
    if (_initialized) return;

    _loadLibrary();

    Logger.info('🔧 [P2P_INIT] Starting native P2P initialization...');
    Logger.info('   Private key length: ${privateKey.length} bytes');
    Logger.info('   Bootstrap peers: ${bootstrapPeers.length}');
    if (psk != null) {
      Logger.info('   PSK: ${psk.length} chars (private network mode)');
    } else {
      Logger.info('   PSK: null (public network mode)');
    }

    // Convert private key to C format (pointer + length)
    final privKeyPtr = malloc<ffi.Uint8>(privateKey.length);
    try {
      // Copy private key bytes
      for (int i = 0; i < privateKey.length; i++) {
        privKeyPtr[i] = privateKey[i];
      }

      // Convert bootstrap peers to JSON
      final bootstrapPeersJson = jsonEncode(bootstrapPeers);
      final bootstrapPeersJsonPtr = bootstrapPeersJson.toNativeUtf8();

      // Convert PSK to hex string (or null)
      final ffi.Pointer<Utf8> pskHexPtr;
      if (psk != null) {
        pskHexPtr = psk.toNativeUtf8();
      } else {
        pskHexPtr = ffi.nullptr;
      }

      try {
        Logger.info('📞 [P2P_INIT] Calling native P2P_Initialize...');
        
        // Call native P2P_Initialize
        final resultPtr = _initialize!(
          privKeyPtr.cast<Utf8>(),
          privateKey.length,
          bootstrapPeersJsonPtr,
          pskHexPtr,
        );
        
        Logger.info('✅ [P2P_INIT] Native call returned');
        
        final resultJson = resultPtr.toDartString();
        Logger.info('📦 [P2P_INIT] Result JSON: $resultJson');
        
        _freeString!(resultPtr);

        // Parse result
        final result = jsonDecode(resultJson) as Map<String, dynamic>;
        
        if (result.containsKey('error')) {
          throw Exception('P2P initialization failed: ${result['error']}');
        }

        _myPeerID = result['peerID'] as String;
        _initialized = true;
        
        Logger.success('🎉 [P2P_INIT] Initialized successfully!');
        Logger.success('   Peer ID: $_myPeerID');
        
        if (result.containsKey('psk_enabled') && result['psk_enabled'] == true) {
          Logger.success('   🔒 Private Network Mode: PSK enabled (${result['psk_length']} bytes)');
        }

        // Log DHT status after initialization
        await Future.delayed(const Duration(seconds: 2));
        await _logDHTStatus();
        
      } finally {
        malloc.free(bootstrapPeersJsonPtr);
        if (pskHexPtr != ffi.nullptr) {
          malloc.free(pskHexPtr);
        }
      }
    } finally {
      malloc.free(privKeyPtr);
    }
  }

  /// Get DHT status for diagnostics
  Future<Map<String, dynamic>> getDHTStatus() async {
    if (_dhtGetStatus == null) {
      throw Exception('P2P_DHT_GetStatus function not available');
    }

    final resultPtr = _dhtGetStatus!();
    final resultJson = resultPtr.toDartString();
    _freeString!(resultPtr);

    final result = jsonDecode(resultJson) as Map<String, dynamic>;
    if (result.containsKey('error')) {
      throw Exception('DHT GetStatus failed: ${result['error']}');
    }

    return result;
  }

  /// Log DHT status for debugging
  Future<void> _logDHTStatus() async {
    try {
      final status = await getDHTStatus();
      Logger.info('📊 [DHT Status]');
      Logger.info('   Routing Table Size: ${status['routing_table_size']}');
      Logger.info('   Connected Peers: ${status['connected_peers']}');
      Logger.info('   Bootstrap Configured: ${status['bootstrap_configured']}');
      Logger.info('   Bootstrap Connected: ${status['bootstrap_connected']}');
      
      // Show enhanced diagnostics if available
      if (status.containsKey('bootstrap_attempts')) {
        Logger.info('   Bootstrap Attempts: ${status['bootstrap_attempts']}');
        Logger.info('   Bootstrap Success: ${status['bootstrap_success']}');
        
        if (status['bootstrap_errors'] != null && (status['bootstrap_errors'] as List).isNotEmpty) {
          Logger.warning('   Bootstrap Errors:');
          for (final error in status['bootstrap_errors'] as List) {
            Logger.warning('      - $error');
          }
        }
      }
      
      final bootstrapConnected = status['bootstrap_connected'] as int;
      final bootstrapConfigured = status['bootstrap_configured'] as int;
      
      if (bootstrapConnected == 0 && bootstrapConfigured > 0) {
        Logger.warning('⚠️  [DHT] No bootstrap peers connected! DHT will not work properly.');
        Logger.warning('   This explains why FindProviders returns instantly with 0 results.');
      } else if (bootstrapConnected > 0) {
        Logger.success('✅ [DHT] Bootstrap successful: $bootstrapConnected/$bootstrapConfigured peers connected');
      }
    } catch (e) {
      Logger.warning('⚠️  Could not get DHT status: $e');
    }
  }

  /// Get own PeerID
  String? get myPeerID => _myPeerID;

  bool get isInitialized => _initialized;

  /// Connect to a relay peer (with connection caching)
  Future<void> connectToRelay(String multiaddr, {bool force = false}) async {
    if (!_initialized) throw StateError('Not initialized');

    // Check if we have a cached connection (unless forced)
    if (!force && _connectionCache.containsKey(multiaddr)) {
      final lastConnection = _connectionCache[multiaddr]!;
      final age = DateTime.now().difference(lastConnection);
      
      if (age < _connectionCacheDuration) {
        // Connection is still fresh, skip reconnecting
        return;
      }
    }

    final multiaddrPtr = multiaddr.toNativeUtf8();
    try {
      final resultPtr = _connectToPeer!(multiaddrPtr);
      final resultJson = resultPtr.toDartString();
      _freeString!(resultPtr);

      // Try to parse JSON response
      try {
        final result = jsonDecode(resultJson) as Map<String, dynamic>;
        if (result.containsKey('error')) {
          // Remove from cache on error
          _connectionCache.remove(multiaddr);
          throw Exception('Failed to connect: ${result['error']}');
        }
      } on FormatException catch (e) {
        // If JSON parsing fails, log raw response and treat as error
        _connectionCache.remove(multiaddr);
        Logger.warning('Failed to parse connect response: $e');
        Logger.debug('Raw response: ${resultJson.replaceAll('\n', '\\n')}');
        throw Exception('Connect response error: ${resultJson.split('\n').first}');
      }

      // Cache successful connection
      _connectionCache[multiaddr] = DateTime.now();
      Logger.success('Connected to relay: $multiaddr');
    } catch (e) {
      _connectionCache.remove(multiaddr);
      rethrow;
    } finally {
      malloc.free(multiaddrPtr);
    }
  }
  
  /// Invalidate connection cache for a specific multiaddr
  void invalidateConnection(String multiaddr) {
    _connectionCache.remove(multiaddr);
  }
  
  /// Clear all cached connections
  void clearConnectionCache() {
    _connectionCache.clear();
  }

  /// Find peer in DHT
  /// Returns multiaddr if peer is online, null otherwise
  Future<String?> findPeer(String peerID) async {
    if (!_initialized) throw StateError('Not initialized');

    final peerIDPtr = peerID.toNativeUtf8();
    try {
      final resultPtr = _findPeer!(peerIDPtr);
      final result = resultPtr.toDartString();
      _freeString!(resultPtr);

      if (result.isEmpty) {
        Logger.debug('🔍 Finding peer: $peerID → offline');
        return null;
      }

      Logger.debug('🔍 Finding peer: $peerID → $result');
      return result;
    } finally {
      malloc.free(peerIDPtr);
    }
  }

  /// Send message directly via P2P
  Future<void> sendDirect({
    required String peerID,
    required String protocol,
    required Uint8List data,
  }) async {
    if (!_initialized) throw StateError('Not initialized');

    final peerIDPtr = peerID.toNativeUtf8();
    final protocolPtr = protocol.toNativeUtf8();
    final dataPtr = malloc<ffi.Uint8>(data.length);
    for (int i = 0; i < data.length; i++) {
      dataPtr[i] = data[i];
    }

    try {
      final resultPtr = _sendDirect!(peerIDPtr, protocolPtr, dataPtr.cast<Utf8>(), data.length);
      final resultJson = resultPtr.toDartString();
      _freeString!(resultPtr);

      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      if (result.containsKey('error')) {
        throw Exception('Failed to send direct: ${result['error']}');
      }

      Logger.success('📤 Sent directly: $peerID via $protocol');
    } finally {
      malloc.free(peerIDPtr);
      malloc.free(protocolPtr);
      malloc.free(dataPtr);
    }
  }

  /// Send to relay via protocol stream
  /// 
  /// Relay Protocols:
  /// - /oasis-node/store/1.0.0
  /// - /oasis-node/retrieve/1.0.0
  /// - /oasis-node/delete/1.0.0
  Future<String> sendToRelay({
    required String relayPeerID,
    required String protocol,
    required String jsonData,
  }) async {
    if (!_initialized) throw StateError('Not initialized');

    final relayPeerIDPtr = relayPeerID.toNativeUtf8();
    final protocolPtr = protocol.toNativeUtf8();
    final jsonDataPtr = jsonData.toNativeUtf8();

    try {
      final resultPtr = _sendToRelay!(relayPeerIDPtr, protocolPtr, jsonDataPtr);
      final result = resultPtr.toDartString();
      _freeString!(resultPtr);

      // Handle empty response
      if (result.isEmpty) {
        Logger.warning('Empty response from relay');
        return '[]'; // Return empty array for retrieve operations
      }

      // Try to parse as JSON - handle both Map and List responses
      try {
        final parsed = jsonDecode(result);
        
        // Check if it's an error response (Map with 'error' key)
        if (parsed is Map<String, dynamic> && parsed.containsKey('error')) {
          throw Exception('Relay call failed: ${parsed['error']}');
        }

        // Log success based on protocol
        if (protocol == '/oasis-node/store/1.0.0') {
          Logger.success('💾 Stored on relay');
        } else if (protocol == '/oasis-node/retrieve/1.0.0') {
          final count = (parsed is List) ? parsed.length : 0;
          Logger.info('📬 Retrieved from relay: $count messages');
        } else if (protocol == '/oasis-node/delete/1.0.0') {
          Logger.success('🗑️ Deleted from relay');
        }

        return result;
      } on FormatException catch (e) {
        // If JSON parsing fails, treat it as an error message
        Logger.warning('Failed to parse relay response as JSON: $e');
        Logger.debug('Raw response: ${result.replaceAll('\n', '\\n').replaceAll('\r', '\\r')}');
        throw Exception('Relay response parse error: ${result.split('\n').first}');
      }
    } finally {
      malloc.free(relayPeerIDPtr);
      malloc.free(protocolPtr);
      malloc.free(jsonDataPtr);
    }
  }

  /// Generate new Ed25519 identity
  static Future<IdentityResult> generateIdentity() async {
    Logger.debug('🔧 P2PBridge.generateIdentity() called');
    
    // Try to load native library first
    try {
      _loadLibrary();
    } catch (e) {
      // If library loading fails on Android, fall back to platform channel
      if (Platform.isAndroid) {
        Logger.warning('⚠️  Native library not available, using platform channel fallback');
        try {
          const channel = MethodChannel('libp2p_plugin');
          final String resultJson = await channel.invokeMethod('generateIdentity');
          
          Logger.debug('Received from Android: $resultJson');
          
          final result = jsonDecode(resultJson) as Map<String, dynamic>;
          
          if (result.containsKey('error')) {
            throw Exception('Failed to generate identity: ${result['error']}');
          }
          
          // Decode Base64 privateKey from plugin
          final privateKeyBase64 = result['private_key'] as String;
          final privateKey = base64.decode(privateKeyBase64);
          final peerID = result['peer_id'] as String;
          
          Logger.success('🔑 Generated identity (Android fallback): $peerID (privateKey: ${privateKey.length} bytes)');
          return IdentityResult(
            privateKey: privateKey,
            peerID: peerID,
          );
        } catch (e, stackTrace) {
          Logger.error('P2PBridge.generateIdentity() Android fallback failed', e, stackTrace);
          rethrow;
        }
      }
      rethrow;
    }
    
    // Use FFI if library loaded successfully
    try {
      Logger.success('Library loaded, calling native P2P_GenerateIdentity...');

      if (_generateIdentity == null) {
        throw Exception('P2P_GenerateIdentity function is null! Library not properly loaded.');
      }

      final resultPtr = _generateIdentity!();
      Logger.debug('Native function returned a pointer');
      
      final resultJson = resultPtr.toDartString();
      Logger.debug('Converted pointer to string: $resultJson');
      
      _freeString!(resultPtr);
      Logger.debug('Freed native string');

      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      Logger.debug('Parsed JSON result');
      
      if (result.containsKey('error')) {
        throw Exception('Failed to generate identity: ${result['error']}');
      }

      Logger.debug('📋 Result contains: ${result.keys}');
      
      // Decode Base64 privateKey from native library
      final privateKeyBase64 = result['privateKey'] as String;
      final privateKey = base64.decode(privateKeyBase64);
      final peerID = result['peerID'] as String;

      Logger.success('🔑 Generated identity: $peerID (privateKey: ${privateKey.length} bytes)');
      return IdentityResult(
        privateKey: privateKey,
        peerID: peerID,
      );
    } catch (e, stackTrace) {
      Logger.error('P2PBridge.generateIdentity() failed', e, stackTrace);
      rethrow;
    }
  }

  /// Announce to DHT that we provide content for a key
  /// This is used to advertise mailbox locations
  Future<void> dhtProvide(String key) async {
    if (!_initialized) throw StateError('Not initialized');
    
    if (_dhtProvide == null) {
      throw Exception('DHT Provide function not available');
    }
    
    final keyPtr = key.toNativeUtf8();
    
    try {
      final resultPtr = _dhtProvide!(keyPtr);
      final resultJson = resultPtr.toDartString();
      _freeString!(resultPtr);
      
      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      if (result.containsKey('error')) {
        throw Exception('DHT Provide failed: ${result['error']}');
      }
      
      Logger.success('DHT Provide successful for key: $key');
    } finally {
      malloc.free(keyPtr);
    }
  }

  /// Find providers for a key in the DHT
  /// Returns list of PeerIDs that provide this content
  Future<List<String>> dhtFindProviders(String key, {int maxProviders = 5}) async {
    if (!_initialized) throw StateError('Not initialized');
    
    if (_dhtFindProviders == null) {
      throw Exception('DHT FindProviders function not available');
    }
    
    Logger.debug('🔍 [DHT] Starting FindProviders query...');
    Logger.debug('🔍 [DHT] Key: "$key"');
    Logger.debug('🔍 [DHT] Max providers: $maxProviders');
    Logger.debug('🔍 [DHT] Initialized: $_initialized');
    Logger.debug('🔍 [DHT] My PeerID: $_myPeerID');
    
    final keyPtr = key.toNativeUtf8();
    
    try {
      final stopwatch = Stopwatch()..start();
      Logger.debug('📤 [DHT] Calling native P2P_DHT_FindProviders...');
      
      final resultPtr = _dhtFindProviders!(keyPtr, maxProviders);
      final resultJson = resultPtr.toDartString();
      _freeString!(resultPtr);
      
      stopwatch.stop();
      Logger.debug('📥 [DHT] Got response in ${stopwatch.elapsedMilliseconds}ms');
      Logger.debug('📥 [DHT] Raw JSON: $resultJson');
      
      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      if (result.containsKey('error')) {
        Logger.error('❌ [DHT] Error from Go backend: ${result['error']}');
        throw Exception('DHT FindProviders failed: ${result['error']}');
      }
      
      // Safely handle null or empty providers list
      final providersList = result['providers'] as List?;
      final providers = providersList?.cast<String>() ?? [];
      
      if (providers.isEmpty) {
        Logger.warning('⚠️  [DHT] No providers found for key: $key');
        Logger.warning('⚠️  [DHT] This could mean:');
        Logger.warning('    - DHT is not bootstrapped yet (needs more time)');
        Logger.warning('    - No nodes announced themselves with this key');
        Logger.warning('    - Network connectivity issues');
        Logger.warning('    - Mobile DHT routing table is empty');
      } else {
        Logger.success('✅ [DHT] Found ${providers.length} providers for key: $key');
        Logger.debug('📋 [DHT] Provider PeerIDs: ${providers.join(", ")}');
      }
      
      return providers;
    } catch (e, stackTrace) {
      Logger.error('❌ [DHT] FindProviders exception', e, stackTrace);
      rethrow;
    } finally {
      malloc.free(keyPtr);
    }
  }

  /// Get healthy providers from an Oasis Node (server-side filtered)
  /// This asks a specific node to check which providers are reachable
  /// Returns list of PeerIDs that are healthy and responsive
  Future<List<String>> getHealthyNodes(String nodePeerID, String key, {int maxProviders = 10}) async {
    if (!_initialized) throw StateError('Not initialized');
    
    if (_getHealthyNodes == null) {
      throw Exception('P2P_GetHealthyNodes function not available');
    }
    
    final nodePeerIDPtr = nodePeerID.toNativeUtf8();
    final keyPtr = key.toNativeUtf8();
    
    try {
      final resultPtr = _getHealthyNodes!(nodePeerIDPtr, keyPtr, maxProviders);
      final resultJson = resultPtr.toDartString();
      _freeString!(resultPtr);
      
      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      if (result.containsKey('error')) {
        throw Exception('GetHealthyNodes failed: ${result['error']}');
      }
      
      // Safely handle null or empty providers list
      final providersList = result['providers'] as List?;
      final providers = providersList?.cast<String>() ?? [];
      Logger.success('Got ${providers.length} healthy providers from $nodePeerID');
      return providers;
    } finally {
      malloc.free(nodePeerIDPtr);
      malloc.free(keyPtr);
    }
  }

  /// Unregister user peer from node (when removing node from My Private Networks)
  Future<void> unregisterPeer(String nodePeerID, String userPeerID) async {
    if (!_initialized) throw StateError('Not initialized');
    
    if (_unregisterPeer == null) {
      throw Exception('P2P_UnregisterPeer function not available');
    }
    
    final nodePeerIDPtr = nodePeerID.toNativeUtf8();
    final userPeerIDPtr = userPeerID.toNativeUtf8();
    
    try {
      final resultPtr = _unregisterPeer!(nodePeerIDPtr, userPeerIDPtr);
      final resultJson = resultPtr.toDartString();
      _freeString!(resultPtr);
      
      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      final status = result['status'] as String?;
      
      if (status == 'rejected') {
        final reason = result['reason'] as String? ?? 'unknown';
        throw Exception('Unregistration rejected: $reason');
      }
      
      if (status != 'accepted') {
        throw Exception('Unexpected status: $status');
      }
      
      Logger.success('Successfully unregistered from node $nodePeerID');
    } finally {
      malloc.free(nodePeerIDPtr);
      malloc.free(userPeerIDPtr);
    }
  }

  /// Find a peer in the DHT and get their addresses
  Future<Map<String, dynamic>?> dhtFindPeer(String peerID) async {
    if (!_initialized) throw StateError('Not initialized');
    
    if (_dhtFindPeer == null) {
      throw Exception('DHT FindPeer function not available');
    }
    
    final peerIDPtr = peerID.toNativeUtf8();
    
    try {
      final resultPtr = _dhtFindPeer!(peerIDPtr);
      final resultJson = resultPtr.toDartString();
      _freeString!(resultPtr);
      
      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      if (result.containsKey('error')) {
        Logger.warning('DHT FindPeer failed: ${result['error']}');
        return null;
      }
      
      Logger.success('DHT found peer: $peerID');
      return result;
    } finally {
      malloc.free(peerIDPtr);
    }
  }

  /// Extract public key from PeerID using native libp2p function
  /// Returns base64-encoded public key bytes
  static Future<Uint8List> publicKeyFromPeerID(String peerID) async {
    _loadLibrary();
    
    if (_publicKeyFromPeerID == null) {
      throw Exception('P2P_PublicKeyFromPeerID function not available');
    }
    
    final peerIDPtr = peerID.toNativeUtf8();
    
    try {
      final resultPtr = _publicKeyFromPeerID!(peerIDPtr);
      final resultJson = resultPtr.toDartString();
      _freeString!(resultPtr);
      
      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      if (result.containsKey('error')) {
        throw Exception('Failed to extract public key from PeerID: ${result['error']}');
      }
      
      final publicKeyBase64 = result['publicKey'] as String;
      final publicKeyBytes = base64Decode(publicKeyBase64);
      
      Logger.success('Extracted public key from PeerID (${publicKeyBytes.length} bytes)');
      return publicKeyBytes;
    } finally {
      malloc.free(peerIDPtr);
    }
  }

  /// Sign data using native libp2p private key
  /// Returns signature bytes
  static Future<Uint8List> sign(Uint8List data) async {
    _loadLibrary();
    
    if (_sign == null) {
      throw Exception('P2P_Sign function not available');
    }
    
    // Allocate C memory for data
    final dataPtr = malloc<ffi.Uint8>(data.length);
    for (int i = 0; i < data.length; i++) {
      dataPtr[i] = data[i];
    }
    
    try {
      final resultPtr = _sign!(dataPtr, data.length);
      final resultJson = resultPtr.toDartString();
      _freeString!(resultPtr);
      
      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      if (result.containsKey('error')) {
        throw Exception('Failed to sign data: ${result['error']}');
      }
      
      final signatureBase64 = result['signature'] as String;
      final signatureBytes = base64Decode(signatureBase64);
      
      Logger.success('Signed data with native libp2p (${signatureBytes.length} bytes signature)');
      return signatureBytes;
    } finally {
      malloc.free(dataPtr);
    }
  }

  /// Verify signature using native libp2p public key from PeerID
  /// Returns true if signature is valid, false otherwise
  static Future<bool> verify({
    required String peerID,
    required Uint8List data,
    required Uint8List signature,
  }) async {
    _loadLibrary();
    
    if (_verify == null) {
      throw Exception('P2P_Verify function not available');
    }
    
    // Allocate C memory for data and signature
    final dataPtr = malloc<ffi.Uint8>(data.length);
    for (int i = 0; i < data.length; i++) {
      dataPtr[i] = data[i];
    }
    
    final signaturePtr = malloc<ffi.Uint8>(signature.length);
    for (int i = 0; i < signature.length; i++) {
      signaturePtr[i] = signature[i];
    }
    
    final peerIDPtr = peerID.toNativeUtf8();
    
    try {
      final resultPtr = _verify!(
        peerIDPtr,
        dataPtr,
        data.length,
        signaturePtr,
        signature.length,
      );
      final resultJson = resultPtr.toDartString();
      _freeString!(resultPtr);
      
      final result = jsonDecode(resultJson) as Map<String, dynamic>;
      if (result.containsKey('error')) {
        throw Exception('Failed to verify signature: ${result['error']}');
      }
      
      final valid = result['valid'] as bool;
      Logger.success('Verified signature with native libp2p: $valid');
      return valid;
    } finally {
      malloc.free(dataPtr);
      malloc.free(signaturePtr);
      malloc.free(peerIDPtr);
    }
  }

  /// Send call signal (offer/answer/ice/reject/end) to peer via Oasis Node
  Future<void> sendCallSignal({
    required String nodePeerID,
    required String targetPeerID,
    required String signalType,
    required String callID,
    required Map<String, dynamic> data,
    String? signature, // Optional Ed25519 signature (base64) for security
    int? signatureTimestamp, // Unix timestamp used for signature
  }) async {
    _loadLibrary();

    Logger.debug('📞 Sending call signal: $signalType to $targetPeerID via $nodePeerID');

    final nodePeerIDPtr = nodePeerID.toNativeUtf8();
    final targetPeerIDPtr = targetPeerID.toNativeUtf8();
    final signalTypePtr = signalType.toNativeUtf8();
    final callIDPtr = callID.toNativeUtf8();
    
    // Add signature and timestamp to data payload if provided
    final dataWithSignature = Map<String, dynamic>.from(data);
    if (signature != null && signature.isNotEmpty) {
      dataWithSignature['_signature'] = signature;
      if (signatureTimestamp != null) {
        dataWithSignature['_timestamp'] = signatureTimestamp;
      }
      Logger.debug('✅ Including signature with call signal (${signature.length} chars, timestamp: $signatureTimestamp)');
    }
    
    final dataJSONPtr = jsonEncode(dataWithSignature).toNativeUtf8();

    try {
      final resultPtr = _sendCallSignal!(
        nodePeerIDPtr,
        targetPeerIDPtr,
        signalTypePtr,
        callIDPtr,
        dataJSONPtr,
      );

      final resultJson = resultPtr.toDartString();
      _freeString!(resultPtr);
      final result = jsonDecode(resultJson) as Map<String, dynamic>;

      if (result.containsKey('error')) {
        throw Exception('Failed to send call signal: ${result['error']}');
      }

      Logger.success('Call signal sent successfully');
    } finally {
      malloc.free(nodePeerIDPtr);
      malloc.free(targetPeerIDPtr);
      malloc.free(signalTypePtr);
      malloc.free(callIDPtr);
      malloc.free(dataJSONPtr);
    }
  }

  /// Set call signal handler (registers incoming signal listener)
  Future<void> setCallSignalHandler() async {
    _loadLibrary();

    Logger.debug('📞 Setting call signal handler...');

    final resultPtr = _setCallSignalHandler!();
    final resultJson = resultPtr.toDartString();
    _freeString!(resultPtr);
    final result = jsonDecode(resultJson) as Map<String, dynamic>;

    if (result.containsKey('error')) {
      throw Exception('Failed to set call signal handler: ${result['error']}');
    }

    Logger.success('Call signal handler registered');
  }

  /// Get pending call signals from Oasis Node
  Future<List<Map<String, dynamic>>> getPendingCallSignals(String nodePeerID) async {
    _loadLibrary();

    Logger.debug('📞 Getting pending call signals from $nodePeerID');

    final nodePeerIDPtr = nodePeerID.toNativeUtf8();

    try {
      final resultPtr = _getPendingCallSignals!(nodePeerIDPtr);
      final resultJson = resultPtr.toDartString();
      _freeString!(resultPtr);
      final result = jsonDecode(resultJson) as Map<String, dynamic>;

      if (result.containsKey('error')) {
        throw Exception('Failed to get pending call signals: ${result['error']}');
      }

      final signals = result['signals'] as List? ?? [];
      return signals.cast<Map<String, dynamic>>();
    } finally {
      malloc.free(nodePeerIDPtr);
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    if (!_initialized) return;

    // Clear connection cache
    _connectionCache.clear();
    
    if (_close != null) {
      _close!();
    }
    _initialized = false;
    _myPeerID = null;
    Logger.debug('👋 P2P Bridge disposed');
  }
}

/// Result from identity generation
class IdentityResult {
  final Uint8List privateKey;
  final String peerID;

  IdentityResult({
    required this.privateKey,
    required this.peerID,
  });
}
