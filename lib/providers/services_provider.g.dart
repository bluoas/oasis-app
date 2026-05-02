// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'services_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$p2pRepositoryHash() => r'68db46012afcf7bcaf88c083e9c604dc5983f335';

/// P2P Repository Provider
///
/// Provides the native P2P repository (FFI bridge to libp2p)
/// Can be overridden with mock for testing
///
/// Copied from [p2pRepository].
@ProviderFor(p2pRepository)
final p2pRepositoryProvider = AutoDisposeProvider<IP2PRepository>.internal(
  p2pRepository,
  name: r'p2pRepositoryProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$p2pRepositoryHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef P2pRepositoryRef = AutoDisposeProviderRef<IP2PRepository>;
String _$cryptoServiceHash() => r'5a3adc48bc655cf9cfa87c33c262366ea6b01401';

/// Crypto Service Provider
///
/// Handles encryption, decryption, and signing operations
/// No dependencies - can be instantiated directly
///
/// Copied from [cryptoService].
@ProviderFor(cryptoService)
final cryptoServiceProvider = AutoDisposeProvider<ICryptoService>.internal(
  cryptoService,
  name: r'cryptoServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$cryptoServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CryptoServiceRef = AutoDisposeProviderRef<ICryptoService>;
String _$storageServiceHash() => r'9ae1e203b84e16e9e9447528b3dd8e98e2cb12d4';

/// Storage Service Provider
///
/// Provides access to local storage operations
/// No dependencies - can be instantiated directly
///
/// Copied from [storageService].
@ProviderFor(storageService)
final storageServiceProvider = AutoDisposeProvider<IStorageService>.internal(
  storageService,
  name: r'storageServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$storageServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef StorageServiceRef = AutoDisposeProviderRef<IStorageService>;
String _$identityServiceHash() => r'fd750a4c6697d412d2007428afdad4719e15f0c5';

/// Identity Service Provider
///
/// Manages user identity and cryptographic keys
/// Depends on: CryptoService
///
/// Copied from [identityService].
@ProviderFor(identityService)
final identityServiceProvider = AutoDisposeProvider<IIdentityService>.internal(
  identityService,
  name: r'identityServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$identityServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef IdentityServiceRef = AutoDisposeProviderRef<IIdentityService>;
String _$myNodesServiceHash() => r'bf76340a8d508a763dd783b999653105fc4d22fb';

/// My Nodes Service Provider
///
/// Manages user's own Oasis Nodes (VPS, Raspberry Pi, home server)
/// No dependencies - can be instantiated directly
///
/// Copied from [myNodesService].
@ProviderFor(myNodesService)
final myNodesServiceProvider = AutoDisposeProvider<MyNodesService>.internal(
  myNodesService,
  name: r'myNodesServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$myNodesServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef MyNodesServiceRef = AutoDisposeProviderRef<MyNodesService>;
String _$bootstrapNodesServiceHash() =>
    r'e09b574ec2eaf67e34a853fa85e3b47839aee665';

/// Bootstrap Nodes Service Provider
///
/// Manages discovered Public Oasis Nodes (auto-discovered via DHT)
/// Nodes are persisted across restarts and filtered by blacklist
/// No dependencies - can be instantiated directly
///
/// Copied from [bootstrapNodesService].
@ProviderFor(bootstrapNodesService)
final bootstrapNodesServiceProvider =
    AutoDisposeProvider<BootstrapNodesService>.internal(
      bootstrapNodesService,
      name: r'bootstrapNodesServiceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$bootstrapNodesServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef BootstrapNodesServiceRef =
    AutoDisposeProviderRef<BootstrapNodesService>;
String _$sharedPreferencesHash() => r'940761540263eccda2ffd9c4a3ba7f41cdeeef83';

/// Shared Preferences Provider
///
/// Provides access to SharedPreferences for simple key-value storage
/// Used for user settings, display name, etc.
/// Pre-initialized in main() and overridden for synchronous access
///
/// Copied from [sharedPreferences].
@ProviderFor(sharedPreferences)
final sharedPreferencesProvider =
    AutoDisposeProvider<SharedPreferences>.internal(
      sharedPreferences,
      name: r'sharedPreferencesProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$sharedPreferencesHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef SharedPreferencesRef = AutoDisposeProviderRef<SharedPreferences>;
String _$privateNetworkSetupServiceHash() =>
    r'e638d3c29468f249ba8edeb5ee44d33ef93369e6';

/// Private Network Setup Service Provider
///
/// Manages private network setup state (scanned nodes, network names)
/// Persists data across app sessions using SharedPreferences
/// Depends on: SharedPreferences
///
/// Copied from [privateNetworkSetupService].
@ProviderFor(privateNetworkSetupService)
final privateNetworkSetupServiceProvider =
    AutoDisposeProvider<PrivateNetworkSetupService>.internal(
      privateNetworkSetupService,
      name: r'privateNetworkSetupServiceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$privateNetworkSetupServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef PrivateNetworkSetupServiceRef =
    AutoDisposeProviderRef<PrivateNetworkSetupService>;
String _$networkServiceHash() => r'ab622a457ab29e2577f138a499ccdb5367a42a08';

/// Network Service Provider
///
/// Manages active network selection (Public vs Private Networks)
/// Persists selection across app sessions using SharedPreferences
/// Extends ChangeNotifier to notify listeners when network changes
///
/// Copied from [networkService].
@ProviderFor(networkService)
final networkServiceProvider = AutoDisposeProvider<NetworkService>.internal(
  networkService,
  name: r'networkServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$networkServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NetworkServiceRef = AutoDisposeProviderRef<NetworkService>;
String _$currentPeerIDHash() => r'1cc3a6666c5f676409d4b51a07ce81b97b2594c7';

/// Current PeerID Provider
///
/// Provides the current PeerID, loading it from storage if needed
/// This is a FutureProvider to handle async initialization
///
/// Copied from [currentPeerID].
@ProviderFor(currentPeerID)
final currentPeerIDProvider = AutoDisposeFutureProvider<String?>.internal(
  currentPeerID,
  name: r'currentPeerIDProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currentPeerIDHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CurrentPeerIDRef = AutoDisposeFutureProviderRef<String?>;
String _$p2pServiceHash() => r'efd30cb58b6738723325be70bee101ae88c5b192';

/// P2P Service Provider
///
/// Manages the lifecycle of P2PService
/// Depends on: AppConfig, P2PRepository, CryptoService, IdentityService, StorageService, MyNodesService, BootstrapNodesService, NetworkService, PrivateNetworkSetupService
///
/// Copied from [p2pService].
@ProviderFor(p2pService)
final p2pServiceProvider = AutoDisposeProvider<P2PService>.internal(
  p2pService,
  name: r'p2pServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$p2pServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef P2pServiceRef = AutoDisposeProviderRef<P2PService>;
String _$nodeDiscoveryServiceHash() =>
    r'fb408fd3454de8fb315d6859af513978aa1dfbe2';

/// Node Discovery Service Provider
///
/// Provides automatic Oasis Node discovery via DHT
/// Depends on: P2PService
///
/// Copied from [nodeDiscoveryService].
@ProviderFor(nodeDiscoveryService)
final nodeDiscoveryServiceProvider =
    AutoDisposeProvider<NodeDiscoveryService>.internal(
      nodeDiscoveryService,
      name: r'nodeDiscoveryServiceProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$nodeDiscoveryServiceHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef NodeDiscoveryServiceRef = AutoDisposeProviderRef<NodeDiscoveryService>;
String _$callServiceHash() => r'ac97b3c47b6d6ab74e3b4bbc469229f3a391fd0e';

/// Call Service Provider
///
/// Manages WebRTC voice/video calls
/// Depends on: P2PRepository, P2PService, IdentityService, StorageService
///
/// Copied from [callService].
@ProviderFor(callService)
final callServiceProvider = AutoDisposeProvider<CallService>.internal(
  callService,
  name: r'callServiceProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$callServiceHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CallServiceRef = AutoDisposeProviderRef<CallService>;
String _$currentCallHash() => r'616df95fd92a091357b27986674b69f6298059b6';

/// Current Call Provider
///
/// Streams the current active call state
///
/// Copied from [currentCall].
@ProviderFor(currentCall)
final currentCallProvider = AutoDisposeStreamProvider<Call?>.internal(
  currentCall,
  name: r'currentCallProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$currentCallHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef CurrentCallRef = AutoDisposeStreamProviderRef<Call?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
