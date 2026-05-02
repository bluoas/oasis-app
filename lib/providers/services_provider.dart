import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/p2p_service.dart';
import '../services/storage_service.dart';
import '../services/identity_service.dart';
import '../services/crypto_service.dart';
import '../services/my_nodes_service.dart';
import '../services/bootstrap_nodes_service.dart';
import '../services/call_service.dart';
import '../services/node_discovery_service.dart';
import '../services/private_network_setup_service.dart';
import '../services/network_service.dart';
import '../services/interfaces/i_storage_service.dart';
import '../services/interfaces/i_identity_service.dart';
import '../services/interfaces/i_crypto_service.dart';
import '../services/interfaces/i_p2p_repository.dart';
import '../repositories/p2p_native_repository.dart';
import 'config_provider.dart';
import '../utils/logger.dart';
import '../models/call.dart';

part 'services_provider.g.dart';

/// P2P Repository Provider
/// 
/// Provides the native P2P repository (FFI bridge to libp2p)
/// Can be overridden with mock for testing
@riverpod
IP2PRepository p2pRepository(Ref ref) {
  // Keep provider alive across navigation
  ref.keepAlive();
  
  Logger.debug('🔧 [P2P_REPOSITORY] Creating P2PNativeRepository...');
  
  try {
    final repository = P2PNativeRepository();
    Logger.success('[P2P_REPOSITORY] P2PNativeRepository created successfully');
    
    ref.onDispose(() {
      Logger.debug('🔄 P2PRepository provider disposed');
    });
    
    return repository;
  } catch (e, stackTrace) {
    Logger.error('[P2P_REPOSITORY] FAILED to create P2PNativeRepository', e, stackTrace);
    rethrow;
  }
}

/// Crypto Service Provider
/// 
/// Handles encryption, decryption, and signing operations
/// No dependencies - can be instantiated directly
@riverpod
ICryptoService cryptoService(Ref ref) {
  // Keep provider alive across navigation
  ref.keepAlive();
  
  final service = CryptoService();
  
  ref.onDispose(() {
    Logger.debug('🔄 CryptoService provider disposed');
  });
  
  return service;
}

/// Storage Service Provider
/// 
/// Provides access to local storage operations
/// No dependencies - can be instantiated directly
@riverpod
IStorageService storageService(Ref ref) {
  // Keep provider alive across navigation
  ref.keepAlive();
  
  final service = StorageService();
  
  ref.onDispose(() {
    Logger.debug('🔄 StorageService provider disposed');
  });
  
  return service;
}

/// Identity Service Provider
/// 
/// Manages user identity and cryptographic keys
/// Depends on: CryptoService
@riverpod
IIdentityService identityService(Ref ref) {
  // Keep provider alive across navigation
  ref.keepAlive();
  
  final crypto = ref.watch(cryptoServiceProvider);
  final service = IdentityService(crypto: crypto);
  
  ref.onDispose(() {
    Logger.debug('🔄 IdentityService provider disposed');
  });
  
  return service;
}

/// My Nodes Service Provider
/// 
/// Manages user's own Oasis Nodes (VPS, Raspberry Pi, home server)
/// No dependencies - can be instantiated directly
@riverpod
MyNodesService myNodesService(Ref ref) {
  // Keep provider alive across navigation
  ref.keepAlive();
  
  final service = MyNodesService();
  
  ref.onDispose(() {
    Logger.debug('🔄 MyNodesService provider disposed');
  });
  
  return service;
}

/// Bootstrap Nodes Service Provider
/// 
/// Manages discovered Public Oasis Nodes (auto-discovered via DHT)
/// Nodes are persisted across restarts and filtered by blacklist
/// No dependencies - can be instantiated directly
@riverpod
BootstrapNodesService bootstrapNodesService(Ref ref) {
  // Keep provider alive across navigation
  ref.keepAlive();
  
  final service = BootstrapNodesService();
  
  ref.onDispose(() {
    Logger.debug('🔄 BootstrapNodesService provider disposed');
  });
  
  return service;
}

/// Shared Preferences Provider
/// 
/// Provides access to SharedPreferences for simple key-value storage
/// Used for user settings, display name, etc.
/// Pre-initialized in main() and overridden for synchronous access
@riverpod
SharedPreferences sharedPreferences(Ref ref) {
  throw UnimplementedError('SharedPreferences must be overridden in main()');
}

/// Private Network Setup Service Provider
/// 
/// Manages private network setup state (scanned nodes, network names)
/// Persists data across app sessions using SharedPreferences
/// Depends on: SharedPreferences
@riverpod
PrivateNetworkSetupService privateNetworkSetupService(Ref ref) {
  // Keep provider alive across navigation
  ref.keepAlive();
  
  final prefs = ref.watch(sharedPreferencesProvider);
  final service = PrivateNetworkSetupService(prefs);
  
  ref.onDispose(() {
    Logger.debug('🔄 PrivateNetworkSetupService provider disposed');
  });
  
  return service;
}

/// Network Service Provider
/// 
/// Manages active network selection (Public vs Private Networks)
/// Persists selection across app sessions using SharedPreferences
/// Extends ChangeNotifier to notify listeners when network changes
@riverpod
NetworkService networkService(Ref ref) {
  // Keep provider alive across navigation
  ref.keepAlive();
  
  final service = NetworkService();
  
  ref.onDispose(() {
    Logger.debug('🔄 NetworkService provider disposed');
    service.dispose(); // Properly dispose the ChangeNotifier
  });
  
  return service;
}

/// Current PeerID Provider
/// 
/// Provides the current PeerID, loading it from storage if needed
/// This is a FutureProvider to handle async initialization
@riverpod
Future<String?> currentPeerID(Ref ref) async {
  final identityService = ref.watch(identityServiceProvider);
  
  // If already initialized, return immediately
  if (identityService.peerID != null) {
    return identityService.peerID;
  }
  
  // Otherwise, initialize and return
  final result = await identityService.initialize();
  if (result.isSuccess) {
    return identityService.peerID;
  }
  
  return null;
}

/// P2P Service Provider
/// 
/// Manages the lifecycle of P2PService
/// Depends on: AppConfig, P2PRepository, CryptoService, IdentityService, StorageService, MyNodesService, BootstrapNodesService, NetworkService, PrivateNetworkSetupService
@riverpod
P2PService p2pService(Ref ref) {
  // Keep provider alive across navigation to prevent disposal during polling/async operations
  ref.keepAlive();
  
  final config = ref.watch(appConfigProvider);
  final repository = ref.watch(p2pRepositoryProvider);
  final crypto = ref.watch(cryptoServiceProvider);
  final identity = ref.watch(identityServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  final myNodesService = ref.watch(myNodesServiceProvider);
  final bootstrapNodesService = ref.watch(bootstrapNodesServiceProvider);
  final networkService = ref.watch(networkServiceProvider);
  final privateNetworkSetupService = ref.watch(privateNetworkSetupServiceProvider);
  
  final service = P2PService(
    config: config,
    repository: repository,
    crypto: crypto,
    identity: identity,
    storage: storage,
    myNodesService: myNodesService,
    bootstrapNodesService: bootstrapNodesService,
    networkService: networkService,
    privateNetworkSetupService: privateNetworkSetupService,
  );
  
  // Cleanup when provider is disposed (only on app termination)
  ref.onDispose(() async {
    Logger.debug('🔄 P2PService provider disposed');
    await service.dispose();
  });
  
  return service;
}

/// Node Discovery Service Provider
/// 
/// Provides automatic Oasis Node discovery via DHT
/// Depends on: P2PService
@riverpod
NodeDiscoveryService nodeDiscoveryService(Ref ref) {
  // Keep provider alive across navigation
  ref.keepAlive();
  
  final p2pService = ref.watch(p2pServiceProvider);
  final service = NodeDiscoveryService(p2pService);
  
  ref.onDispose(() {
    Logger.debug('🔄 NodeDiscoveryService provider disposed');
  });
  
  return service;
}

/// Call Service Provider
/// 
/// Manages WebRTC voice/video calls
/// Depends on: P2PRepository, P2PService, IdentityService, StorageService
@riverpod
CallService callService(Ref ref) {
  // Keep provider alive across navigation
  ref.keepAlive();
  
  final repository = ref.watch(p2pRepositoryProvider);
  final p2pService = ref.watch(p2pServiceProvider);
  final identity = ref.watch(identityServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  
  final service = CallService(
    p2pRepository: repository,
    identity: identity,
    storage: storage,
    getActiveNode: () => p2pService.activeBootstrapNode,
    callSignalStream: p2pService.callSignalStream,
    triggerMessagePoll: () => p2pService.pollMessagesManually(),
    enableFastPolling: () => p2pService.enableFastPolling(),
    disableFastPolling: () => p2pService.disableFastPolling(),
  );
  
  // Initialize to subscribe to call signals
  service.initialize();
  
  ref.onDispose(() async {
    Logger.debug('🔄 CallService provider disposed');
    await service.dispose();
  });
  
  return service;
}

/// Current Call Provider
/// 
/// Streams the current active call state
@riverpod
Stream<Call?> currentCall(Ref ref) {
  final callService = ref.watch(callServiceProvider);
  return callService.callStateStream;
}
