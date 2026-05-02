import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_error.dart';
import '../utils/result.dart';
import '../utils/logger.dart';

/// Service for managing discovered Public Oasis Nodes
/// 
/// Stores Oasis Nodes that were automatically discovered via DHT.
/// These nodes are persisted across app restarts and filtered against a blacklist.
/// Nodes that fail to connect are blacklisted to avoid repeated timeouts.
class BootstrapNodesService {
  // New storage key (renamed from 'user_bootstrap_nodes' for clarity)
  static const String _storageKey = 'discovered_oasis_nodes';
  static const String _legacyStorageKey = 'user_bootstrap_nodes';  // For migration
  static const String _blacklistKey = 'discovered_nodes_blacklist';
  static const Duration _blacklistTTL = Duration(hours: 24);
  
  List<BootstrapNode> _bootstrapNodes = [];
  Map<String, DateTime> _blacklistedNodes = {};
  bool _isInitialized = false;  // Prevent re-initialization
  
  /// Get all discovered nodes (filtered by blacklist)
  List<BootstrapNode> get nodes => List.unmodifiable(_bootstrapNodes);
  
  /// Check if service has any nodes
  bool get hasNodes => _bootstrapNodes.isNotEmpty;
  
  /// Initialize service - load nodes from storage with blacklist filtering
  Future<Result<void, AppError>> initialize() async {
    // Skip if already initialized (prevents overwriting in-memory state)
    if (_isInitialized) {
      Logger.debug('ℹ️  BootstrapNodesService already initialized, skipping...');
      return Success(null);
    }
    
    final result = await resultOfAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      
      // Load blacklist first
      await _loadBlacklist();
      
      // Try new storage key first, then migrate from legacy if needed
      List<String>? nodesJson = prefs.getStringList(_storageKey);
      
      if (nodesJson == null) {
        // Migration: Check for old key
        nodesJson = prefs.getStringList(_legacyStorageKey);
        if (nodesJson != null) {
          Logger.info('🔄 Migrating from legacy storage key...');
          // Will be saved with new key on next save
        }
      }
      
      if (nodesJson != null) {
        // Load and filter against blacklist
        final allNodes = nodesJson
            .map((json) => BootstrapNode.fromJson(jsonDecode(json) as Map<String, dynamic>))
            .toList();
        
        final beforeFilter = allNodes.length;
        _cleanupBlacklist();  // Remove expired blacklist entries first
        
        _bootstrapNodes = allNodes.where((node) {
          return !_blacklistedNodes.containsKey(node.peerID);
        }).toList();
        
        final filteredCount = beforeFilter - _bootstrapNodes.length;
        Logger.info('📦 Loaded ${_bootstrapNodes.length} discovered Oasis Node(s)');
        if (filteredCount > 0) {
          Logger.info('🚫 Filtered out $filteredCount blacklisted node(s)');
        }
        
        // Save with new key if migrated, and save filtered list
        if (filteredCount > 0 || prefs.containsKey(_legacyStorageKey)) {
          await _saveToStorage();
          // Clean up legacy key after successful migration
          await prefs.remove(_legacyStorageKey);
        }
      }
    }, (e, stackTrace) => StorageError(
      message: 'Failed to load discovered nodes: $e',
      type: StorageErrorType.loadFailed,
    ));
    
    // Mark as initialized only if successful
    if (result.isSuccess) {
      _isInitialized = true;
    }
    
    return result;
  }
  
  /// Add a discovered node (e.g., from automatic discovery)
  /// Checks if node is blacklisted before adding
  Future<Result<void, AppError>> addNode({
    required String multiaddr,
    String? name,
  }) async {
    return resultOfAsync(() async {
      // Extract PeerID from multiaddr
      final peerID = _extractPeerID(multiaddr);
      
      // Check if blacklisted
      if (_blacklistedNodes.containsKey(peerID)) {
        Logger.warning('⚠️ Skipping blacklisted node: ${peerID.substring(0, 16)}...');
        throw StorageError(
          message: 'Node is blacklisted (unreachable)',
          type: StorageErrorType.saveFailed,
        );
      }
      
      // Check if already exists
      if (_bootstrapNodes.any((node) => node.peerID == peerID)) {
        Logger.debug('Node already exists: ${peerID.substring(0, 16)}...');
        return;  // Silently skip duplicates
      }
      
      // Create new node
      final node = BootstrapNode(
        peerID: peerID,
        multiaddr: multiaddr,
        name: name ?? 'Oasis Node ${peerID.substring(0, 8)}',
        addedAt: DateTime.now(),
      );
      
      _bootstrapNodes.add(node);
      await _saveToStorage();
      
      Logger.success('Added discovered node: ${node.name}');
    }, (e, stackTrace) => StorageError(
      message: 'Failed to add node: $e',
      type: StorageErrorType.saveFailed,
    ));
  }
  
  /// Blacklist a node that failed to connect
  /// This prevents repeated connection attempts to unreachable nodes
  Future<void> blacklistNode(String peerID) async {
    if (!_blacklistedNodes.containsKey(peerID)) {
      _blacklistedNodes[peerID] = DateTime.now();
      await _saveBlacklist();
      Logger.info('🚫 Blacklisted unreachable node: ${peerID.substring(0, 16)}...');
      
      // Remove from active nodes list
      final hadNode = _bootstrapNodes.any((node) => node.peerID == peerID);
      _bootstrapNodes.removeWhere((node) => node.peerID == peerID);
      if (hadNode) {
        await _saveToStorage();
      }
    }
  }
  
  /// Remove a node from blacklist (e.g., for manual retry)
  Future<void> unblacklistNode(String peerID) async {
    if (_blacklistedNodes.remove(peerID) != null) {
      await _saveBlacklist();
      Logger.info('✅ Removed node from blacklist: ${peerID.substring(0, 16)}...');
    }
  }
  
  /// Remove a discovered node
  Future<Result<void, AppError>> removeNode(String peerID) async {
    return resultOfAsync(() async {
      _bootstrapNodes.removeWhere((node) => node.peerID == peerID);
      await _saveToStorage();
      
      Logger.info('🗑️ Removed node: ${peerID.substring(0, 16)}...');
    }, (e, stackTrace) => StorageError(
      message: 'Failed to remove node: $e',
      type: StorageErrorType.saveFailed,
    ));
  }
  
  /// Update node name
  Future<Result<void, AppError>> updateNodeName(String peerID, String newName) async {
    return resultOfAsync(() async {
      final index = _bootstrapNodes.indexWhere((node) => node.peerID == peerID);
      if (index == -1) {
        throw StorageError(
          message: 'Node not found',
          type: StorageErrorType.loadFailed,
        );
      }
      
      _bootstrapNodes[index] = _bootstrapNodes[index].copyWith(name: newName);
      await _saveToStorage();
      
      Logger.info('✏️ Updated node name: $newName');
    }, (e, stackTrace) => StorageError(
      message: 'Failed to update node: $e',
      type: StorageErrorType.saveFailed,
    ));
  }
  
  /// Get all multiaddrs for P2P connection
  List<String> getMultiaddrs() {
    return _bootstrapNodes.map((node) => node.multiaddr).toList();
  }
  
  /// Get blacklist status (for debugging)
  Map<String, dynamic> getBlacklistStatus() {
    return {
      'count': _blacklistedNodes.length,
      'entries': _blacklistedNodes.map((peerID, timestamp) {
        final age = DateTime.now().difference(timestamp);
        return MapEntry(
          peerID.substring(0, 16),
          '${age.inHours}h ago',
        );
      }),
    };
  }
  
  /// Get all blacklisted nodes with remaining TTL
  List<Map<String, dynamic>> getBlacklistedNodesWithTTL() {
    _cleanupBlacklist(); // Remove expired entries first
    
    final now = DateTime.now();
    return _blacklistedNodes.entries.map((entry) {
      final age = now.difference(entry.value);
      final remainingHours = _blacklistTTL.inHours - age.inHours;
      
      return {
        'peerID': entry.key,
        'blacklistedAt': entry.value,
        'ageHours': age.inHours,
        'remainingHours': remainingHours,
        'shortPeerID': entry.key.substring(0, 16),
      };
    }).toList();
  }
  
  /// Clear entire blacklist
  Future<void> clearBlacklist() async {
    final count = _blacklistedNodes.length;
    _blacklistedNodes.clear();
    await _saveBlacklist();
    Logger.info('🗑️ Cleared $count blacklisted node(s)');
  }
  
  /// Save nodes to persistent storage
  Future<void> _saveToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final nodesJson = _bootstrapNodes
        .map((node) => jsonEncode(node.toJson()))
        .toList();
    await prefs.setStringList(_storageKey, nodesJson);
  }
  
  /// Load blacklist from persistent storage
  Future<void> _loadBlacklist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final blacklistJson = prefs.getString(_blacklistKey);
      
      if (blacklistJson != null) {
        final Map<String, dynamic> data = jsonDecode(blacklistJson);
        _blacklistedNodes = data.map((key, value) {
          return MapEntry(key, DateTime.parse(value as String));
        });
        
        Logger.debug('📋 Loaded ${_blacklistedNodes.length} blacklisted node(s)');
      }
    } catch (e) {
      Logger.warning('⚠️ Failed to load blacklist: $e');
      _blacklistedNodes = {};
    }
  }
  
  /// Save blacklist to persistent storage
  Future<void> _saveBlacklist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _blacklistedNodes.map((key, value) {
        return MapEntry(key, value.toIso8601String());
      });
      await prefs.setString(_blacklistKey, jsonEncode(data));
    } catch (e) {
      Logger.warning('⚠️ Failed to save blacklist: $e');
    }
  }
  
  /// Remove expired entries from blacklist
  void _cleanupBlacklist() {
    final now = DateTime.now();
    final beforeCount = _blacklistedNodes.length;
    
    _blacklistedNodes.removeWhere((peerID, timestamp) {
      final age = now.difference(timestamp);
      return age > _blacklistTTL;
    });
    
    final removed = beforeCount - _blacklistedNodes.length;
    if (removed > 0) {
      Logger.debug('🗑️ Cleaned up $removed expired blacklist entries');
    }
  }
  
  /// Extract PeerID from multiaddr string
  String _extractPeerID(String multiaddr) {
    final parts = multiaddr.split('/p2p/');
    if (parts.length < 2) {
      throw FormatException('Invalid multiaddr format: missing /p2p/ component');
    }
    return parts.last;
  }
}

/// Model for a discovered Oasis Node
/// These nodes are automatically found via DHT and persisted across app restarts
class BootstrapNode {
  final String peerID;
  final String multiaddr;
  final String name;
  final DateTime addedAt;
  
  const BootstrapNode({
    required this.peerID,
    required this.multiaddr,
    required this.name,
    required this.addedAt,
  });
  
  BootstrapNode copyWith({
    String? peerID,
    String? multiaddr,
    String? name,
    DateTime? addedAt,
  }) {
    return BootstrapNode(
      peerID: peerID ?? this.peerID,
      multiaddr: multiaddr ?? this.multiaddr,
      name: name ?? this.name,
      addedAt: addedAt ?? this.addedAt,
    );
  }
  
  Map<String, dynamic> toJson() => {
    'peer_id': peerID,
    'multiaddr': multiaddr,
    'name': name,
    'added_at': addedAt.toIso8601String(),
  };
  
  factory BootstrapNode.fromJson(Map<String, dynamic> json) => BootstrapNode(
    peerID: json['peer_id'] as String,
    multiaddr: json['multiaddr'] as String,
    name: json['name'] as String,
    addedAt: DateTime.parse(json['added_at'] as String),
  );
}
