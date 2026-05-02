import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

/// Service for managing private networks created by scanning PSK-enabled
/// Oasis Nodes. Each network corresponds to exactly one node.
///
/// Data stored per network (indexed by node peer_id = networkId):
///   - networkName  : user-chosen label
///   - multiaddr    : the node's multiaddr (bootstrap peer)
///   - createdAt    : ISO-8601 timestamp
///
/// PSK is stored separately in flutter_secure_storage under
/// 'psk_network_{networkId}' (same key pattern used by P2PService).
class PrivateNetworkSetupService {
  static const String _storageKey = 'private_networks_v2';

  final SharedPreferences _prefs;

  // In-memory map: networkId → PrivateNetwork
  Map<String, PrivateNetwork> _networks = {};

  PrivateNetworkSetupService(this._prefs) {
    _load();
  }

  void _load() {
    try {
      final json = _prefs.getString(_storageKey);
      if (json == null) return;

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      _networks = decoded.map((id, value) {
        final m = value as Map<String, dynamic>;
        return MapEntry(
          id,
          PrivateNetwork(
            networkId: id,
            networkName: m['network_name'] as String,
            multiaddr: m['multiaddr'] as String,
            createdAt: DateTime.parse(m['created_at'] as String),
          ),
        );
      });
      Logger.info('📡 Loaded ${_networks.length} private network(s)');
    } catch (e) {
      Logger.error('Failed to load private networks: $e');
    }
  }

  Future<void> _save() async {
    try {
      final data = _networks.map((id, n) => MapEntry(id, {
            'network_name': n.networkName,
            'multiaddr': n.multiaddr,
            'created_at': n.createdAt.toIso8601String(),
          }));
      await _prefs.setString(_storageKey, jsonEncode(data));
    } catch (e) {
      Logger.error('Failed to save private networks: $e');
    }
  }

  // ── Public API ────────────────────────────────────────────────────────

  List<PrivateNetwork> getAllNetworks() {
    final list = _networks.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  PrivateNetwork? getNetwork(String networkId) => _networks[networkId];

  /// Returns the bootstrap multiaddr for [networkId], or null if not found.
  String? getBootstrapMultiaddr(String networkId) =>
      _networks[networkId]?.multiaddr;

  Future<void> addNetwork(PrivateNetwork network) async {
    _networks[network.networkId] = network;
    await _save();
    Logger.info('✅ Private network "${network.networkName}" saved');
  }

  Future<void> removeNetwork(String networkId) async {
    _networks.remove(networkId);
    await _save();
    Logger.info('🗑️ Private network $networkId removed');
  }

  Future<void> clearAll() async {
    _networks.clear();
    await _prefs.remove(_storageKey);
    Logger.info('🗑️ All private networks cleared');
  }
}

/// Represents a private network backed by a single PSK-enabled Oasis Node.
class PrivateNetwork {
  final String networkId;   // = node peer_id
  final String networkName;
  final String multiaddr;   // bootstrap multiaddr of the node
  final DateTime createdAt;

  /// Always 1 – kept for UI compatibility.
  int get nodeCount => 1;

  const PrivateNetwork({
    required this.networkId,
    required this.networkName,
    required this.multiaddr,
    required this.createdAt,
  });
}
