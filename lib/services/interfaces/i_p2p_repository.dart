import 'dart:typed_data';

/// P2P Repository Interface
/// 
/// Abstracts the native P2P bridge (FFI to libp2p Go library)
/// This interface allows us to mock the native layer for testing
/// 
/// Implementations: 
/// - P2PNativeRepository (real FFI bridge)
/// - P2PMockRepository (for tests)
abstract class IP2PRepository {
  /// Initialize libp2p host with identity private key and bootstrap peers
  /// 
  /// [psk] - Pre-Shared Key for private networks (optional, null = public network)
  Future<void> initialize(Uint8List privateKey, List<String> bootstrapPeers, {String? psk});
  
  /// Connect to a relay node (bootstrap or Oasis node)
  Future<void> connectToRelay(String multiaddr);
  
  /// Send data to relay using a specific protocol
  /// 
  /// Returns: response from relay as JSON string
  Future<String> sendToRelay(String peerID, String protocol, String data);
  
  /// Find a peer in the DHT
  /// 
  /// Returns: multiaddress of the peer
  Future<String> findPeer(String peerID);
  
  /// Send data directly to a peer
  Future<void> sendDirect(String peerID, String protocol, Uint8List data);
  
  /// DHT: Announce that we provide a key (e.g., mailbox)
  Future<void> dhtProvide(String key);
  
  /// DHT: Find providers for a key
  /// 
  /// Returns: List of peer multiaddresses
  Future<List<String>> findProviders(String key, int maxProviders);
  
  /// Get healthy providers from an Oasis Node
  /// Asks a specific node to return only reachable providers (server-side filtering)
  /// 
  /// Returns: List of peer IDs that are healthy
  Future<List<String>> getHealthyNodes(String nodePeerID, String key, int maxProviders);
  
  /// Unregister user peer from Oasis Node (when removing node from My Private Networks)
  /// This allows another user to register the node
  Future<void> unregisterPeer(String nodePeerID, String userPeerID);
  
  /// DHT: Find a specific peer
  Future<String> dhtFindPeer(String peerID);
  
  /// Get public key from PeerID
  Future<Uint8List> publicKeyFromPeerID(String peerID);
  
  /// Sign data with host's identity key
  Future<Uint8List> sign(Uint8List data);
  
  /// Verify signature using peer's public key from PeerID
  Future<bool> verify({
    required String peerID,
    required Uint8List data,
    required Uint8List signature,
  });
  
  /// Send call signal (offer/answer/ice/reject/end) to peer via Oasis Node
  Future<void> sendCallSignal({
    required String nodePeerID,
    required String targetPeerID,
    required String signalType,
    required String callID,
    required Map<String, dynamic> data,
    String? signature, // Optional Ed25519 signature (base64) for security
    int? signatureTimestamp, // Unix timestamp used for signature
  });
  
  /// Close the P2P host
  Future<void> close();
  
  /// Get current P2P status
  Map<String, dynamic> getStatus();
}
