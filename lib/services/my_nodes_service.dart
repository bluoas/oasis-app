import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_error.dart';
import '../utils/result.dart';
import '../utils/logger.dart';

/// Service for managing user's own Oasis Nodes
/// 
/// Stores and manages nodes that the user owns/operates (e.g., VPS, Raspberry Pi, home server)
/// These nodes are prioritized over public DHT-discovered nodes for message polling
class MyNodesService {
  static const String _storageKey = 'my_oasis_nodes';
  
  List<MyOasisNode> _myNodes = [];
  
  /// Get all user's nodes
  List<MyOasisNode> get nodes => List.unmodifiable(_myNodes);
  
  /// Initialize service - load nodes from storage
  Future<Result<void, AppError>> initialize() async {
    return resultOfAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      final nodesJson = prefs.getStringList(_storageKey);
      
      if (nodesJson != null) {
        _myNodes = nodesJson
            .map((json) => MyOasisNode.fromJson(jsonDecode(json) as Map<String, dynamic>))
            .toList();
        Logger.info('📦 Loaded ${_myNodes.length} My Oasis Node(s)');
      }
    }, (e, stackTrace) => StorageError(
      message: 'Failed to load My Nodes: $e',
      type: StorageErrorType.loadFailed,
    ));
  }
  
  /// Add a new node from QR code data
  Future<Result<void, AppError>> addNode({
    required String multiaddr,
    String? name,
  }) async {
    return resultOfAsync(() async {
      // Extract PeerID from multiaddr
      final peerID = _extractPeerID(multiaddr);
      
      // Check if already exists
      if (_myNodes.any((node) => node.peerID == peerID)) {
        throw StorageError(
          message: 'Node already exists',
          type: StorageErrorType.saveFailed,
        );
      }
      
      // Create new node
      final node = MyOasisNode(
        peerID: peerID,
        multiaddr: multiaddr,
        name: name ?? 'Node ${_myNodes.length + 1}',
        addedAt: DateTime.now(),
      );
      
      _myNodes.add(node);
      await _saveToStorage();
      
      Logger.success('Added My Oasis Node: ${node.name} ($peerID)');
    }, (e, stackTrace) => StorageError(
      message: 'Failed to add node: $e',
      type: StorageErrorType.saveFailed,
    ));
  }
  
  /// Remove a node
  Future<Result<void, AppError>> removeNode(String peerID) async {
    return resultOfAsync(() async {
      _myNodes.removeWhere((node) => node.peerID == peerID);
      await _saveToStorage();
      
      Logger.info('🗑️ Removed My Oasis Node: $peerID');
    }, (e, stackTrace) => StorageError(
      message: 'Failed to remove node: $e',
      type: StorageErrorType.saveFailed,
    ));
  }
  
  /// Update node name
  Future<Result<void, AppError>> updateNodeName(String peerID, String newName) async {
    return resultOfAsync(() async {
      final index = _myNodes.indexWhere((node) => node.peerID == peerID);
      if (index == -1) {
        throw StorageError(
          message: 'Node not found',
          type: StorageErrorType.loadFailed,
        );
      }
      
      _myNodes[index] = _myNodes[index].copyWith(name: newName);
      await _saveToStorage();
      
      Logger.info('Updated node name: $newName');
    }, (e, stackTrace) => StorageError(
      message: 'Failed to update node: $e',
      type: StorageErrorType.saveFailed,
    ));
  }
  
  /// Get multiaddrs for polling
  List<String> getMultiaddrs() {
    return _myNodes.map((node) => node.multiaddr).toList();
  }
  
  /// Check if user has any nodes
  bool get hasNodes => _myNodes.isNotEmpty;
  
  /// Save to SharedPreferences
  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final nodesJson = _myNodes
        .map((node) => jsonEncode(node.toJson()))
        .toList();
    await prefs.setStringList(_storageKey, nodesJson);
  }
  
  /// Extract PeerID from multiaddr
  String _extractPeerID(String multiaddr) {
    final parts = multiaddr.split('/p2p/');
    if (parts.length > 1) {
      return parts.last;
    }
    // Fallback: maybe it's just a PeerID
    return multiaddr;
  }
}

/// Model for user's own Oasis Node
class MyOasisNode {
  final String peerID;
  final String multiaddr;
  final String name;
  final DateTime addedAt;
  final DateTime? lastSeen;
  
  const MyOasisNode({
    required this.peerID,
    required this.multiaddr,
    required this.name,
    required this.addedAt,
    this.lastSeen,
  });
  
  MyOasisNode copyWith({
    String? peerID,
    String? multiaddr,
    String? name,
    DateTime? addedAt,
    DateTime? lastSeen,
  }) {
    return MyOasisNode(
      peerID: peerID ?? this.peerID,
      multiaddr: multiaddr ?? this.multiaddr,
      name: name ?? this.name,
      addedAt: addedAt ?? this.addedAt,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'peer_id': peerID,
    'multiaddr': multiaddr,
    'name': name,
    'added_at': addedAt.toIso8601String(),
    if (lastSeen != null) 'last_seen': lastSeen!.toIso8601String(),
  };
  
  factory MyOasisNode.fromJson(Map<String, dynamic> json) => MyOasisNode(
    peerID: json['peer_id'] as String,
    multiaddr: json['multiaddr'] as String,
    name: json['name'] as String,
    addedAt: DateTime.parse(json['added_at'] as String),
    lastSeen: json['last_seen'] != null 
        ? DateTime.parse(json['last_seen'] as String)
        : null,
  );
}
