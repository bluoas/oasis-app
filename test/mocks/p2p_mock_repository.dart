import 'dart:typed_data';
import '../../lib/services/interfaces/i_p2p_repository.dart';

/// Mock P2P Repository for Testing
/// 
/// Simulates native P2P bridge behavior without FFI/libp2p dependencies
/// Can be configured to simulate success/failure scenarios
class P2PMockRepository implements IP2PRepository {
  bool _isInitialized = false;
  final List<String> _connectedRelays = [];
  final Map<String, List<String>> _dhtProviders = {};
  final Map<String, String> _peerAddresses = {};
  final Map<String, Uint8List> _publicKeys = {};
  
  // Configurable for testing error scenarios
  bool shouldFailInitialize = false;
  bool shouldFailConnectToRelay = false;
  bool shouldFailSendToRelay = false;
  bool shouldFailSendDirect = false;
  bool shouldFailDhtProvide = false;
  bool shouldFailSendCallSignal = false;
  
  // Mock responses
  String? mockSendToRelayResponse;
  List<String>? mockFindProvidersResult;
  String? mockFindPeerResult;
  
  @override
  Future<void> initialize(Uint8List privateKey, List<String> bootstrapPeers, {String? psk}) async {
    if (shouldFailInitialize) {
      throw Exception('Mock: Failed to initialize P2P host');
    }
    
    await Future.delayed(const Duration(milliseconds: 10));
    _isInitialized = true;
  }

  @override
  Future<void> connectToRelay(String multiaddr) async {
    if (!_isInitialized) {
      throw Exception('Mock: P2P host not initialized');
    }
    
    if (shouldFailConnectToRelay) {
      throw Exception('Mock: Failed to connect to relay');
    }
    
    await Future.delayed(const Duration(milliseconds: 20));
    _connectedRelays.add(multiaddr);
  }

  @override
  Future<String> sendToRelay(String peerID, String protocol, String data) async {
    if (!_isInitialized) {
      throw Exception('Mock: P2P host not initialized');
    }
    
    if (shouldFailSendToRelay) {
      throw Exception('Mock: Failed to send to relay');
    }
    
    await Future.delayed(const Duration(milliseconds: 50));
    return mockSendToRelayResponse ?? '{"status": "ok", "data": "mock_response"}';
  }

  @override
  Future<String> findPeer(String peerID) async {
    if (!_isInitialized) {
      throw Exception('Mock: P2P host not initialized');
    }
    
    await Future.delayed(const Duration(milliseconds: 30));
    
    // Return mock address if pre-configured
    if (_peerAddresses.containsKey(peerID)) {
      return _peerAddresses[peerID]!;
    }
    
    return mockFindPeerResult ?? '/ip4/127.0.0.1/tcp/4001/p2p/$peerID';
  }

  @override
  Future<void> sendDirect(String peerID, String protocol, Uint8List data) async {
    if (!_isInitialized) {
      throw Exception('Mock: P2P host not initialized');
    }
    
    if (shouldFailSendDirect) {
      throw Exception('Mock: Failed to send direct');
    }
    
    await Future.delayed(const Duration(milliseconds: 40));
    // Mock implementation - just simulate success
  }

  @override
  Future<void> dhtProvide(String key) async {
    if (!_isInitialized) {
      throw Exception('Mock: P2P host not initialized');
    }
    
    if (shouldFailDhtProvide) {
      throw Exception('Mock: Failed to provide DHT key');
    }
    
    await Future.delayed(const Duration(milliseconds: 100));
    // Mock: Register ourselves as provider
    _dhtProviders.putIfAbsent(key, () => []);
  }

  @override
  Future<List<String>> findProviders(String key, int maxProviders) async {
    if (!_isInitialized) {
      throw Exception('Mock: P2P host not initialized');
    }
    
    await Future.delayed(const Duration(milliseconds: 150));
    
    if (mockFindProvidersResult != null) {
      return mockFindProvidersResult!;
    }
    
    return _dhtProviders[key] ?? [];
  }

  @override
  Future<List<String>> getHealthyNodes(String nodePeerID, String key, int maxProviders) async {
    if (!_isInitialized) {
      throw Exception('Mock: P2P host not initialized');
    }
    
    await Future.delayed(const Duration(milliseconds: 200));
    
    // Mock: Return findProviders result (simulate server-side filtering)
    if (mockFindProvidersResult != null) {
      return mockFindProvidersResult!;
    }
    
    return _dhtProviders[key] ?? [];
  }

  @override
  Future<void> unregisterPeer(String nodePeerID, String userPeerID) async {
    if (!_isInitialized) {
      throw Exception('Mock: P2P host not initialized');
    }
    
    await Future.delayed(const Duration(milliseconds: 100));
    print('🔧 Mock: Unregistered $userPeerID from node $nodePeerID');
  }

  @override
  Future<String> dhtFindPeer(String peerID) async {
    if (!_isInitialized) {
      throw Exception('Mock: P2P host not initialized');
    }
    
    await Future.delayed(const Duration(milliseconds: 80));
    return _peerAddresses[peerID] ?? '';
  }

  @override
  Future<Uint8List> publicKeyFromPeerID(String peerID) async {
    if (!_isInitialized) {
      throw Exception('Mock: P2P host not initialized');
    }
    
    await Future.delayed(const Duration(milliseconds: 10));
    
    if (_publicKeys.containsKey(peerID)) {
      return _publicKeys[peerID]!;
    }
    
    // Return dummy public key (32 bytes)
    return Uint8List.fromList(List.generate(32, (i) => i));
  }

  @override
  Future<Uint8List> sign(Uint8List data) async {
    if (!_isInitialized) {
      throw Exception('Mock: P2P host not initialized');
    }
    
    await Future.delayed(const Duration(milliseconds: 5));
    
    // Return dummy signature (64 bytes for Ed25519)
    return Uint8List.fromList(List.generate(64, (i) => i));
  }
  
  @override
  Future<bool> verify({
    required String peerID,
    required Uint8List data,
    required Uint8List signature,
  }) async {
    if (!_isInitialized) {
      throw Exception('Mock: P2P host not initialized');
    }
    
    await Future.delayed(const Duration(milliseconds: 5));
    
    // Mock: always return true for verification
    // Tests can override this behavior by checking signature structure
    return signature.length == 64;
  }

  @override
  Future<void> sendCallSignal({
    required String nodePeerID,
    required String targetPeerID,
    required String signalType,
    required String callID,
    required Map<String, dynamic> data,
    String? signature,
    int? signatureTimestamp,
  }) async {
    if (!_isInitialized) {
      throw Exception('Mock: P2P host not initialized');
    }
    
    if (shouldFailSendCallSignal) {
      throw Exception('Mock: Failed to send call signal');
    }
    
    await Future.delayed(const Duration(milliseconds: 30));
    // Mock implementation - just simulate success
  }

  @override
  Future<void> close() async {
    await Future.delayed(const Duration(milliseconds: 10));
    _isInitialized = false;
    _connectedRelays.clear();
    _dhtProviders.clear();
    _peerAddresses.clear();
    _publicKeys.clear();
  }

  @override
  Map<String, dynamic> getStatus() {
    return {
      'initialized': _isInitialized,
      'connectedRelays': _connectedRelays.length,
      'dhtProviders': _dhtProviders.length,
    };
  }
  
  // ==================== Test Helper Methods ====================
  
  /// Check if repository is initialized
  bool get isInitialized => _isInitialized;
  
  /// Get list of connected relays (for verification in tests)
  List<String> get connectedRelays => List.unmodifiable(_connectedRelays);
  
  /// Pre-configure peer address for findPeer() calls
  void registerPeer(String peerID, String multiaddr) {
    _peerAddresses[peerID] = multiaddr;
  }
  
  /// Pre-configure public key for publicKeyFromPeerID() calls
  void registerPublicKey(String peerID, Uint8List publicKey) {
    _publicKeys[peerID] = publicKey;
  }
  
  /// Pre-configure DHT providers for findProviders() calls
  void registerProvider(String key, String providerPeerID) {
    _dhtProviders.putIfAbsent(key, () => []);
    _dhtProviders[key]!.add(providerPeerID);
  }
  
  /// Reset all state (useful between tests)
  void reset() {
    _isInitialized = false;
    _connectedRelays.clear();
    _dhtProviders.clear();
    _peerAddresses.clear();
    _publicKeys.clear();
    
    shouldFailInitialize = false;
    shouldFailConnectToRelay = false;
    shouldFailSendToRelay = false;
    shouldFailSendDirect = false;
    shouldFailDhtProvide = false;
    
    mockSendToRelayResponse = null;
    mockFindProvidersResult = null;
    mockFindPeerResult = null;
  }
}
