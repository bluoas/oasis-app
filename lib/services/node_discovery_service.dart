import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_error.dart';
import '../utils/logger.dart';
import '../utils/result.dart';
import 'p2p_service.dart';

/// Automatic Oasis Node discovery service using DHT
/// 
/// Discovers available Oasis Nodes in the network without requiring QR scanning.
/// Uses IPFS DHT to find nodes that announced themselves via "/oasis-node/nodes"
class NodeDiscoveryService {
  final P2PService _p2pService;
  
  // Discovery state
  List<DiscoveredNode> _discoveredNodes = [];
  bool _isDiscovering = false;
  DateTime? _lastDiscoveryTime;
  
  // Blacklist for unreachable nodes
  Map<String, DateTime> _blacklistedNodes = {};
  static const String _blacklistKey = 'node_discovery_blacklist';
  static const Duration _blacklistTTL = Duration(hours: 24);
  
  // Discovery configuration
  static const int _maxNodesToDiscover = 20;
  static const int _maxActiveNodes = 5; // Maximum nodes to use after filtering
  static const Duration _discoveryTimeout = Duration(seconds: 30);
  static const Duration _minDiscoveryInterval = Duration(minutes: 5);
  
  NodeDiscoveryService(this._p2pService) {
    _loadBlacklist();
  }
  
  /// Get list of discovered nodes
  List<DiscoveredNode> get discoveredNodes => List.unmodifiable(_discoveredNodes);
  
  /// Check if discovery is currently running
  bool get isDiscovering => _isDiscovering;
  
  /// Get time of last discovery attempt
  DateTime? get lastDiscoveryTime => _lastDiscoveryTime;
  
  /// Discover available Oasis Nodes via DHT
  /// 
  /// Returns a list of discovered nodes with their multiaddrs.
  /// Performs health checks to filter out unreachable nodes.
  Future<Result<List<DiscoveredNode>, AppError>> discoverNodes({
    bool forceRefresh = false,
  }) async {
    return resultOfAsync(() async {
      // Check if discovery is already running
      if (_isDiscovering) {
        Logger.info('🔍 Discovery already in progress, skipping...');
        return _discoveredNodes;
      }
      
      // Check if we should skip discovery (too soon since last attempt)
      if (!forceRefresh && _lastDiscoveryTime != null) {
        final timeSinceLastDiscovery = DateTime.now().difference(_lastDiscoveryTime!);
        if (timeSinceLastDiscovery < _minDiscoveryInterval) {
          Logger.info('🔍 Using cached discovery results (${timeSinceLastDiscovery.inMinutes}m ago)');
          return _discoveredNodes;
        }
      }
      
      _isDiscovering = true;
      _lastDiscoveryTime = DateTime.now();
      
      Logger.info('🔍 Starting automatic Oasis Node discovery via DHT...');
      
      try {
        // Query DHT for Oasis Nodes
        // Nodes announce themselves with key "/oasis-node/nodes"
        final peerIDsResult = await _p2pService.dhtFindProviders(
          '/oasis-node/nodes',
          maxProviders: _maxNodesToDiscover,
        ).timeout(_discoveryTimeout);
        
        if (peerIDsResult.isFailure) {
          throw peerIDsResult.error;
        }
        
        final peerIDs = peerIDsResult.value;
        
        if (peerIDs.isEmpty) {
          Logger.warning('⚠️  No Oasis Nodes found in DHT (network might be empty or DHT not bootstrapped yet)');
          _discoveredNodes = [];
          return _discoveredNodes;
        }
        
        Logger.success('🎯 Found ${peerIDs.length} potential Oasis Node(s) in DHT');
        
        // Convert PeerIDs to DiscoveredNode objects
        _discoveredNodes = peerIDs.map((peerID) {
          return DiscoveredNode(
            peerID: peerID,
            discoveredAt: DateTime.now(),
          );
        }).toList();
        
        Logger.success('✅ Discovery completed: ${_discoveredNodes.length} node(s) discovered');
        
        // Filter blacklisted nodes (cleanup expired entries first)
        _cleanupBlacklist();
        final beforeFilter = _discoveredNodes.length;
        _discoveredNodes = _discoveredNodes.where((node) {
          return !_blacklistedNodes.containsKey(node.peerID);
        }).toList();
        final blacklistedCount = beforeFilter - _discoveredNodes.length;
        if (blacklistedCount > 0) {
          Logger.info('🚫 Filtered out $blacklistedCount blacklisted node(s)');
        }
        
        if (_discoveredNodes.isEmpty) {
          Logger.warning('⚠️  All discovered nodes are blacklisted! Clearing blacklist...');
          await _clearBlacklist();
          // Restore nodes for this attempt
          _discoveredNodes = peerIDs.map((peerID) {
            return DiscoveredNode(
              peerID: peerID,
              discoveredAt: DateTime.now(),
            );
          }).toList();
        }
        
        // Filter for compatible nodes (parallel pre-check)
        Logger.info('🔍 Checking transport compatibility for ${_discoveredNodes.length} nodes...');
        final compatibleNodes = await filterCompatibleNodes(_discoveredNodes);
        _discoveredNodes = compatibleNodes;
        
        final compatibleCount = compatibleNodes.where((n) => n.isCompatible == true).length;
        Logger.success('✅ Found $compatibleCount/${peerIDs.length} compatible nodes (TCP/IPv4)');
        
        // Limit to maximum active nodes
        if (_discoveredNodes.length > _maxActiveNodes) {
          final prioritized = _discoveredNodes.where((n) => n.isCompatible == true).toList()
            ..addAll(_discoveredNodes.where((n) => n.isCompatible != true));
          _discoveredNodes = prioritized.take(_maxActiveNodes).toList();
          Logger.info('📊 Limited to $_maxActiveNodes active nodes (from $compatibleCount compatible)');
        }
        
        return _discoveredNodes;
      } catch (e, stackTrace) {
        Logger.error('❌ Node discovery failed', e, stackTrace);
        throw NetworkError(
          message: 'Failed to discover Oasis Nodes: $e',
          type: NetworkErrorType.dhtQueryFailed,
        );
      } finally {
        _isDiscovering = false;
      }
    }, (e, stackTrace) {
      if (e is AppError) return e;
      return NetworkError(
        message: 'Node discovery error: $e',
        type: NetworkErrorType.unknown,
      );
    });
  }
  
  /// Select a random node from discovered nodes
  /// 
  /// This distributes load across the network and avoids dependency on single nodes.
  /// Prioritizes compatible nodes (TCP/IPv4) over incompatible ones.
  DiscoveredNode? selectRandomNode() {
    if (_discoveredNodes.isEmpty) {
      Logger.warning('⚠️  No discovered nodes available for selection');
      return null;
    }
    
    // First try to select from compatible nodes only
    final compatibleNodes = _discoveredNodes.where((n) => n.isCompatible == true).toList();
    
    if (compatibleNodes.isNotEmpty) {
      final shuffled = List<DiscoveredNode>.from(compatibleNodes)..shuffle();
      final selected = shuffled.first;
      Logger.info('🎲 Selected random compatible node: ${selected.peerID}');
      return selected;
    }
    
    // Fallback: If no compatible nodes, try any node
    Logger.warning('⚠️  No compatible nodes found, selecting from all');
    final shuffled = List<DiscoveredNode>.from(_discoveredNodes)..shuffle();
    final selected = shuffled.first;
    
    Logger.info('🎲 Selected random node (unverified): ${selected.peerID}');
    return selected;
  }
  
  /// Select multiple random nodes for redundancy
  /// Prioritizes compatible nodes (TCP/IPv4) over incompatible ones
  List<DiscoveredNode> selectRandomNodes(int count) {
    if (_discoveredNodes.isEmpty) {
      return [];
    }
    
    // First try to select from compatible nodes only
    final compatibleNodes = _discoveredNodes.where((n) => n.isCompatible == true).toList();
    
    if (compatibleNodes.isNotEmpty) {
      final shuffled = List<DiscoveredNode>.from(compatibleNodes)..shuffle();
      final selected = shuffled.take(count).toList();
      Logger.info('🎲 Selected ${selected.length} compatible node(s) from ${compatibleNodes.length} compatible');
      return selected;
    }
    
    // Fallback: If no compatible nodes, select from all
    Logger.warning('⚠️  No compatible nodes found, selecting from all');
    final shuffled = List<DiscoveredNode>.from(_discoveredNodes)..shuffle();
    final selected = shuffled.take(count).toList();
    
    Logger.info('🎲 Selected ${selected.length} node(s) (unverified) from ${_discoveredNodes.length} available');
    return selected;
  }
  
  /// Clear discovery cache
  void clearCache() {
    _discoveredNodes.clear();
    _lastDiscoveryTime = null;
    Logger.info('🗑️  Discovery cache cleared');
  }
  
  /// Filter nodes for transport compatibility (parallel pre-check)
  /// 
  /// Queries DHT for each node's multiaddrs and checks if TCP/IPv4 is available.
  /// Returns nodes with isCompatible flag set and multiaddrs populated.
  Future<List<DiscoveredNode>> filterCompatibleNodes(List<DiscoveredNode> nodes) async {
    if (nodes.isEmpty) return [];
    
    try {
      // Parallel DHT FindPeer queries for all nodes
      final futures = nodes.map((node) async {
        try {
          // Query DHT for this peer's addresses
          final result = await _p2pService.dhtFindPeerAddresses(node.peerID);
          
          if (result == null || result.isEmpty) {
            Logger.warning('⚠️  No addresses found for ${node.peerID.substring(0, 16)}...');
            return DiscoveredNode(
              peerID: node.peerID,
              discoveredAt: node.discoveredAt,
              multiaddrs: [],
              isCompatible: false,
            );
          }
          
          // Check if any address is TCP/IPv4 compatible
          final hasCompatible = result.any(_isTransportCompatible);
          
          if (hasCompatible) {
            Logger.success('✅ ${node.peerID.substring(0, 16)}... has compatible transport');
          } else {
            Logger.warning('⏭️  ${node.peerID.substring(0, 16)}... only has incompatible transports');
          }
          
          return DiscoveredNode(
            peerID: node.peerID,
            discoveredAt: node.discoveredAt,
            multiaddrs: result,
            isCompatible: hasCompatible,
          );
        } catch (e) {
          Logger.warning('❌ Failed to check ${node.peerID.substring(0, 16)}...: $e');
          return DiscoveredNode(
            peerID: node.peerID,
            discoveredAt: node.discoveredAt,
            multiaddrs: [],
            isCompatible: false,
          );
        }
      }).toList();
      
      // Wait for all queries to complete (parallel)
      final results = await Future.wait(futures);
      
      // Blacklist nodes that are unreachable or incompatible
      for (final node in results) {
        if (node.isCompatible == false || (node.multiaddrs?.isEmpty ?? true)) {
          await _addToBlacklist(node.peerID);
        }
      }
      
      return results;
    } catch (e) {
      Logger.error('❌ Transport filtering failed: $e');
      return nodes; // Return original nodes on error
    }
  }
  
  /// Check if a multiaddr has compatible transport (TCP on IPv4 or IPv6)
  /// 
  /// iOS requires TCP transport. QUIC, WebSocket may not work reliably.
  bool _isTransportCompatible(String multiaddr) {
    final hasTcp = multiaddr.contains('/tcp/');
    final hasIpOrDns = multiaddr.contains('/ip4/') || 
                       multiaddr.contains('/ip6/') || 
                       multiaddr.contains('/dns/') ||
                       multiaddr.contains('/dns4/') ||
                       multiaddr.contains('/dns6/');
    
    // Reject non-TCP transports
    final hasQuic = multiaddr.contains('/quic');
    final hasUdp = multiaddr.contains('/udp/');
    final hasWs = multiaddr.contains('/ws/') || multiaddr.contains('/wss/');
    
    return hasIpOrDns && hasTcp && !hasQuic && !hasUdp && !hasWs;
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
        
        // Cleanup expired entries
        _cleanupBlacklist();
        
        Logger.info('📋 Loaded ${_blacklistedNodes.length} blacklisted node(s)');
      }
    } catch (e) {
      Logger.warning('⚠️  Failed to load blacklist: $e');
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
      Logger.warning('⚠️  Failed to save blacklist: $e');
    }
  }
  
  /// Add a node to blacklist
  Future<void> _addToBlacklist(String peerID) async {
    if (!_blacklistedNodes.containsKey(peerID)) {
      _blacklistedNodes[peerID] = DateTime.now();
      await _saveBlacklist();
      Logger.debug('🚫 Blacklisted unreachable node: ${peerID.substring(0, 16)}...');
    }
  }
  
  /// Remove expired entries from blacklist
  void _cleanupBlacklist() {
    final now = DateTime.now();
    _blacklistedNodes.removeWhere((peerID, timestamp) {
      final age = now.difference(timestamp);
      return age > _blacklistTTL;
    });
  }
  
  /// Clear entire blacklist
  Future<void> _clearBlacklist() async {
    _blacklistedNodes.clear();
    await _saveBlacklist();
    Logger.info('🗑️  Blacklist cleared');
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
}

/// Represents a discovered Oasis Node
class DiscoveredNode {
  final String peerID;
  final DateTime discoveredAt;
  final String? multiaddr;  // Optional - may be resolved later
  final List<String>? multiaddrs;  // All multiaddrs from DHT FindPeer
  final bool? isCompatible;  // Has TCP/IPv4 transport
  
  DiscoveredNode({
    required this.peerID,
    required this.discoveredAt,
    this.multiaddr,
    this.multiaddrs,
    this.isCompatible,
  });
  
  @override
  String toString() => 'DiscoveredNode(peerID: $peerID, compatible: ${isCompatible ?? '?'}, discovered: ${discoveredAt.toIso8601String()})';
}
