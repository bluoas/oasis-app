import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

/// Service for managing active network selection
/// 
/// Tracks which network the user is currently using:
/// - "public" = Public Network (DHT-discovered nodes)
/// - KM-Node PeerID = Private Network (specific network)
/// 
/// Extends ChangeNotifier to notify listeners when network changes
class NetworkService extends ChangeNotifier {
  static const String _storageKey = 'active_network_id';
  static const String publicNetworkId = 'public';
  
  String _activeNetworkId = publicNetworkId;
  
  /// Get currently active network ID
  String get activeNetworkId => _activeNetworkId;
  
  /// Check if currently using public network
  bool get isPublicNetwork => _activeNetworkId == publicNetworkId;
  
  /// Initialize service - load active network from storage
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      
      if (stored != null && stored.isNotEmpty) {
        _activeNetworkId = stored;
        Logger.info('📡 Active network loaded from storage: ${isPublicNetwork ? "Public Network" : _activeNetworkId}');
        Logger.debug('   Storage key: $_storageKey');
        Logger.debug('   Loaded value: $stored');
        notifyListeners(); // Notify UI of loaded state
      } else {
        Logger.info('📡 Active network: Public Network (default - nothing stored)');
        Logger.debug('   Storage key: $_storageKey returned null or empty');
      }
    } catch (e) {
      Logger.error('Failed to load active network: $e');
    }
  }
  
  /// Switch to a different network
  Future<void> switchToNetwork(String networkId) async {
    try {
      _activeNetworkId = networkId;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, networkId);
      
      // Verify it was saved
      final saved = prefs.getString(_storageKey);
      if (saved == networkId) {
        Logger.success('✅ Switched to network: ${isPublicNetwork ? "Public Network" : networkId}');
        Logger.debug('   Saved to storage: $_storageKey = $networkId');
        Logger.debug('   Verification: saved value matches');
        
        // Notify all listeners (UI) that network has changed
        notifyListeners();
      } else {
        Logger.error('❌ Network switch failed: storage verification failed');
        Logger.error('   Expected: $networkId, Got: $saved');
      }
    } catch (e) {
      Logger.error('Failed to switch network: $e');
      rethrow;
    }
  }
  
  /// Get display name for active network
  String getActiveNetworkName(Map<String, String> privateNetworkNames) {
    if (isPublicNetwork) {
      return 'Public Network';
    }
    
    return privateNetworkNames[_activeNetworkId] ?? 'Private Network';
  }
}
