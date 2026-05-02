import 'dart:typed_data';
import '../services/interfaces/i_p2p_repository.dart';
import '../services/p2p_bridge.dart';

/// P2P Native Repository - Real FFI implementation
/// 
/// This implementation uses the actual native P2PBridge (FFI to Go libp2p)
/// For testing, use P2PMockRepository instead
class P2PNativeRepository implements IP2PRepository {
  // Lazy initialization - only create bridge when actually needed
  P2PBridge? _bridge;
  P2PBridge get bridge {
    _bridge ??= P2PBridge();
    return _bridge!;
  }
  
  @override
  Future<void> initialize(Uint8List privateKey, List<String> bootstrapPeers, {String? psk}) async {
    return bridge.initialize(privateKey, bootstrapPeers, psk: psk);
  }
  
  @override
  Future<void> connectToRelay(String multiaddr) async {
    return bridge.connectToRelay(multiaddr);
  }
  
  @override
  Future<String> sendToRelay(String peerID, String protocol, String data) async {
    return bridge.sendToRelay(
      relayPeerID: peerID,
      protocol: protocol,
      jsonData: data,
    );
  }
  
  @override
  Future<String> findPeer(String peerID) async {
    final result = await bridge.findPeer(peerID);
    return result ?? '';
  }
  
  @override
  Future<void> sendDirect(String peerID, String protocol, Uint8List data) async {
    return bridge.sendDirect(
      peerID: peerID,
      protocol: protocol,
      data: data,
    );
  }
  
  @override
  Future<void> dhtProvide(String key) async {
    return bridge.dhtProvide(key);
  }
  
  @override
  Future<List<String>> findProviders(String key, int maxProviders) async {
    return bridge.dhtFindProviders(key, maxProviders: maxProviders);
  }
  
  @override
  Future<List<String>> getHealthyNodes(String nodePeerID, String key, int maxProviders) async {
    return bridge.getHealthyNodes(nodePeerID, key, maxProviders: maxProviders);
  }
  
  @override
  Future<void> unregisterPeer(String nodePeerID, String userPeerID) async {
    await bridge.unregisterPeer(nodePeerID, userPeerID);
  }
  
  @override
  Future<String> dhtFindPeer(String peerID) async {
    final result = await bridge.dhtFindPeer(peerID);
    // Return empty string if null or extract multiaddr from result map
    if (result == null) return '';
    if (result.containsKey('multiaddr')) {
      return result['multiaddr'] as String? ?? '';
    }
    return '';
  }
  
  @override
  Future<Uint8List> publicKeyFromPeerID(String peerID) async {
    return P2PBridge.publicKeyFromPeerID(peerID);
  }
  
  @override
  Future<Uint8List> sign(Uint8List data) async {
    return P2PBridge.sign(data);
  }
  
  @override
  Future<bool> verify({
    required String peerID,
    required Uint8List data,
    required Uint8List signature,
  }) async {
    return P2PBridge.verify(
      peerID: peerID,
      data: data,
      signature: signature,
    );
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
    return bridge.sendCallSignal(
      nodePeerID: nodePeerID,
      targetPeerID: targetPeerID,
      signalType: signalType,
      callID: callID,
      data: data,
      signature: signature,
      signatureTimestamp: signatureTimestamp,
    );
  }
  
  @override
  Future<void> close() async {
    return bridge.dispose();
  }
  
  @override
  Map<String, dynamic> getStatus() {
    return {
      'initialized': true,
      'architecture': 'Native P2P via FFI',
    };
  }
}
