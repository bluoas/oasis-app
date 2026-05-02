/// Environment configuration for different build flavors
enum Environment {
  /// Development environment - local testing with internal servers
  development,
  
  /// Staging environment - pre-production testing
  staging,
  
  /// Production environment - live app with public servers
  production,
}

/// Application configuration that varies by environment
/// 
/// Usage:
/// ```dart
/// // Development
/// final config = AppConfig.development();
/// 
/// // Production
/// final config = AppConfig.production();
/// ```
class AppConfig {
  /// Current environment
  final Environment environment;
  
  /// Bootstrap nodes for DHT discovery
  /// Format: /ip4/IP/tcp/PORT/p2p/PEER_ID or /dnsaddr/DOMAIN/p2p/PEER_ID
  final List<String> bootstrapNodes;
  
  /// Initial list of known Oasis nodes for store-and-forward
  /// Can be empty - will be discovered via DHT
  final List<String> initialOasisNodes;
  
  /// How often to poll for new messages (foreground)
  final Duration messagePollingInterval;
  
  /// How often to check for messages in background (background service)
  final Duration backgroundSyncInterval;
  
  /// Maximum number of messages to keep in memory cache
  final int maxCachedMessages;
  
  /// Connection timeout for relay nodes
  final Duration connectionTimeout;
  
  /// DHT query timeout
  final Duration dhtQueryTimeout;
  
  /// Enable debug logging
  final bool debugLogging;
  
  /// Enable automatic Oasis Node discovery via DHT
  /// If false, users must manually add nodes via QR code (shows onboarding)
  final bool enableAutoDiscovery;
  
  /// List of deprecated/obsolete Oasis Node PeerIDs to filter out
  /// These nodes should be ignored during DHT queries and polling
  final List<String> deprecatedPeerIDs;
  
  const AppConfig({
    required this.environment,
    required this.bootstrapNodes,
    required this.initialOasisNodes,
    required this.messagePollingInterval,
    required this.backgroundSyncInterval,
    required this.maxCachedMessages,
    required this.connectionTimeout,
    required this.dhtQueryTimeout,
    required this.debugLogging,
    required this.enableAutoDiscovery,
    this.deprecatedPeerIDs = const [],
  });
  
  /// Generate hash from node configuration
  /// Changes in bootstrapNodes or deprecatedPeerIDs will change the hash
  /// Used to automatically invalidate cached nodes when config changes
  String get configHash {
    final parts = [
      ...bootstrapNodes,
      ...deprecatedPeerIDs,
    ];
    return parts.join('|').hashCode.toString();
  }
  
  /// Development configuration
  /// - Uses local/internal servers
  /// - Faster polling for quick testing
  /// - Debug logging enabled
  factory AppConfig.development() => const AppConfig(
    environment: Environment.development,
    bootstrapNodes: [
      // IPFS Bootstrap Nodes for Public Network Mode (Phase 1)
      '/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN',
      '/dnsaddr/bootstrap.libp2p.io/p2p/QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa',
      '/dnsaddr/bootstrap.libp2p.io/p2p/QmbLHAnMoJPWSCR5Zhtx6BHJX9KiKNN6tpvbUcqanj75Nb',
      '/dnsaddr/bootstrap.libp2p.io/p2p/QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt',
    ],
    initialOasisNodes: [
      // FULLY DECENTRALIZED: Nodes discovered via DHT automatically
    ],
    messagePollingInterval: Duration(seconds:10), // Conservative polling to prevent connection overload
    backgroundSyncInterval: Duration(minutes: 5),   // Frequent background checks
    maxCachedMessages: 100,
    connectionTimeout: Duration(seconds: 5),  // Fast failover - 5s is enough for most networks
    dhtQueryTimeout: Duration(seconds: 30),  // Mobile networks need more time
    debugLogging: true,
    enableAutoDiscovery: true,  // ENABLED: Public Network Mode for privacy
    deprecatedPeerIDs: [],  // No deprecated nodes
  );
  
  /// Staging configuration
  /// - Uses staging servers  
  /// - Moderate polling for realistic testing
  /// - Debug logging enabled
  factory AppConfig.staging() => const AppConfig(
    environment: Environment.staging,
    bootstrapNodes: [
      // IPFS Bootstrap Nodes for Public Network Mode (Phase 1)
      '/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN',
      '/dnsaddr/bootstrap.libp2p.io/p2p/QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa',
      '/dnsaddr/bootstrap.libp2p.io/p2p/QmbLHAnMoJPWSCR5Zhtx6BHJX9KiKNN6tpvbUcqanj75Nb',
      '/dnsaddr/bootstrap.libp2p.io/p2p/QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt',
    ],
    initialOasisNodes: [],  // Fully decentralized discovery
    messagePollingInterval: Duration(seconds: 60),  // Conservative polling
    backgroundSyncInterval: Duration(minutes: 10),
    maxCachedMessages: 200,
    connectionTimeout: Duration(seconds: 5),  // Fast failover
    dhtQueryTimeout: Duration(seconds: 15),  // Allow more time for connection setup
    debugLogging: true,
    enableAutoDiscovery: true,  // ENABLED: Public Network Mode for privacy
    deprecatedPeerIDs: [],
  );
  
  /// Production configuration
  /// - Fully decentralized P2P network
  /// - Conservative polling to save battery
  /// - Debug logging disabled
  factory AppConfig.production() => const AppConfig(
    environment: Environment.production,
    bootstrapNodes: [
      // IPFS Bootstrap Nodes for Public Network Mode (Phase 1)
      '/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN',
      '/dnsaddr/bootstrap.libp2p.io/p2p/QmQCU2EcMqAqQPR2i9bChDtGNJchTbq5TbXJJ16u19uLTa',
      '/dnsaddr/bootstrap.libp2p.io/p2p/QmbLHAnMoJPWSCR5Zhtx6BHJX9KiKNN6tpvbUcqanj75Nb',
      '/dnsaddr/bootstrap.libp2p.io/p2p/QmcZf59bWwK5XFi76CZX8cbJ4BhTzzA3gU1ZjYZcYW3dwt',
    ],
    initialOasisNodes: [],  // Pure DHT discovery
    messagePollingInterval: Duration(seconds: 10),  // Fast polling for quick message delivery
    backgroundSyncInterval: Duration(minutes: 5),   // Faster message delivery (was 15min)
    maxCachedMessages: 500,
    connectionTimeout: Duration(seconds: 5),  // Fast failover - retry next node quickly
    dhtQueryTimeout: Duration(seconds: 30),  // Mobile networks need more time (was 15s)
    debugLogging: false,
    enableAutoDiscovery: true,  // ENABLED: Public Network Mode for privacy
    deprecatedPeerIDs: [],
  );
  
  /// Check if running in development mode
  bool get isDevelopment => environment == Environment.development;
  
  /// Check if running in staging mode
  bool get isStaging => environment == Environment.staging;
  
  /// Check if running in production mode
  bool get isProduction => environment == Environment.production;
  
  @override
  String toString() {
    return 'AppConfig(environment: $environment, '
        'bootstrapNodes: ${bootstrapNodes.length}, '
        'polling: ${messagePollingInterval.inSeconds}s, '
        'debug: $debugLogging)';
  }
}
