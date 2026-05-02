import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'providers/config_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/services_provider.dart';
import 'providers/auth_provider.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/auth_lock_screen.dart';
import 'utils/logger.dart';
import 'utils/debug_shared_prefs.dart';

/// Main entry point
/// 
/// Automatically selects configuration based on build mode:
/// - Debug build (`flutter run`): Development config
/// - Release build (`flutter run --release`): Production config
void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Auto-select config based on build mode
  final config = kDebugMode 
      ? AppConfig.development()
      : AppConfig.production();
  
  // Pre-initialize SharedPreferences for synchronous access
  final sharedPrefs = await SharedPreferences.getInstance();
  Logger.info('📦 SharedPreferences initialized');
  
  // Debug: Print all SharedPreferences on app start (in debug mode only)
  if (kDebugMode) {
    Logger.info('🐛 Debug mode - Inspecting SharedPreferences...');
    await DebugSharedPrefs.printAll();
    await DebugSharedPrefs.test();
  }
  
  runApp(
    ProviderScope(
      overrides: [
        // Override config provider with development config
        appConfigProvider.overrideWithValue(config),
        // Override SharedPreferences provider with pre-initialized instance
        sharedPreferencesProvider.overrideWith((ref) => sharedPrefs),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final config = ref.watch(appConfigProvider);

    return MaterialApp(
      title: config.isDevelopment ? 'Oasis (DEV)' : 'Oasis',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const AuthGate(),
    );
  }
}

/// Auth Gate - Prüft ob App-Lock aktiv ist und zeigt ggf. Lock Screen
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProviderProvider);
    
    // Wenn Auth nicht aktiviert ist → direkt zur InitializationScreen
    if (!authState.isEnabled) {
      return const InitializationScreen();
    }
    
    // Wenn Auth aktiviert ist, aber noch nicht authentifiziert → Lock Screen
    if (!authState.isAuthenticated) {
      return AuthLockScreen(
        onUnlocked: () {
          // Nach erfolgreicher Authentifizierung wird setState() in AuthLockScreen
          // den Provider updaten, was einen Rebuild triggert
        },
      );
    }
    
    // Authentifiziert → zur InitializationScreen
    return const InitializationScreen();
  }
}

/// Initialization screen - Sets up P2P services before showing home
class InitializationScreen extends ConsumerStatefulWidget {
  const InitializationScreen({super.key});

  @override
  ConsumerState<InitializationScreen> createState() => _InitializationScreenState();
}

class _InitializationScreenState extends ConsumerState<InitializationScreen> {
  String _status = 'Initializing P2P...';
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      Logger.debug('🚀 === Starting P2P Initialization ===');
      
      // Get ALL services from Riverpod providers BEFORE any async operations
      // This prevents "Cannot use ref after widget was disposed" errors
      final myNodesService = ref.read(myNodesServiceProvider);
      final bootstrapNodesService = ref.read(bootstrapNodesServiceProvider);
      final networkService = ref.read(networkServiceProvider);
      final storageService = ref.read(storageServiceProvider);
      final p2pService = ref.read(p2pServiceProvider);
      final nodeDiscoveryService = ref.read(nodeDiscoveryServiceProvider);
      // TODO(coming-soon): Re-enable CallService eager init when call feature ships
      // ref.read(callServiceProvider);
      
      // Initialize network service first to load active network selection
      await networkService.initialize();
      
      // Check if user has any nodes configured (first-time setup check)
      if (!mounted) return;
      setState(() => _status = 'Checking configuration...');
      Logger.debug('🔍 Checking if nodes are configured...');
      
      await myNodesService.initialize();
      await bootstrapNodesService.initialize();
      
      // Get node status before onboarding check
      final hasMyNodes = myNodesService.hasNodes;
      
      // Check if user has completed onboarding (either by adding own node OR joining a friend)
      final hasBootstrapNodes = bootstrapNodesService.hasNodes;
      
      // Also check if user has any contacts (from "Join a friend" onboarding path)
      await storageService.initialize(); // Ensure storage is initialized before checking contacts
      final contactsResult = await storageService.getAllContacts();
      final hasContacts = contactsResult.isSuccess && 
                          contactsResult.valueOrNull != null && 
                          contactsResult.valueOrNull!.isNotEmpty;
      
      Logger.success('Setup status: MyNodes=$hasMyNodes, Bootstrap=$hasBootstrapNodes, Contacts=$hasContacts');
      
      // SIMPLE: If user hasn't configured anything → Show onboarding
      // User-configured means: Own nodes, discovered Oasis nodes (auto-found), or Contacts (from "Join a friend")
      // Note: Config bootstrap (IPFS) doesn't count - it's just infrastructure
      if (!hasMyNodes && !hasBootstrapNodes && !hasContacts) {
        Logger.info('📝 Fresh install detected (no user-configured nodes/contacts) → Showing onboarding');
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const OnboardingScreen()),
          );
        }
        return;
      }
      
      // User has completed onboarding - now check node count for Public Network
      // Offer discovery if too low (only for users who already completed onboarding)
      if (networkService.isPublicNetwork && !hasMyNodes) {
        final nodeCount = bootstrapNodesService.nodes.length;
        
        // Critical: Only 0-1 nodes (high risk of connection failure)
        if (nodeCount < 2) {
          if (!mounted) return;
          
          final shouldDiscover = await _showLowNodeCountDialog(
            context,
            nodeCount: nodeCount,
          );
          
          if (shouldDiscover) {
            if (mounted) {
              setState(() => _status = 'Discovering nodes...');
            }
            final discovered = await _performNodeDiscovery(
              nodeDiscoveryService: nodeDiscoveryService,
              bootstrapNodesService: bootstrapNodesService,
              p2pService: p2pService,
            );
            
            if (!discovered && nodeCount == 0) {
              // Failed to discover and no nodes at all - force onboarding
              Logger.warning('⚠️ No nodes available and discovery failed → Showing onboarding');
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                );
              }
              return;
            }
          } else if (nodeCount == 0) {
            // User skipped discovery but has 0 nodes - can't continue
            Logger.warning('⚠️ User skipped discovery with 0 nodes → Showing onboarding');
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              );
            }
            return;
          }
        }
        // 2+ nodes = all good, no dialog needed
      }
      
      Logger.success('Setup complete - continuing with P2P initialization...');
      
      // p2pService already defined at the top
      // storage already initialized above when checking contacts
      
      if (!mounted) return;
      setState(() => _status = 'Setting up storage...');
      Logger.success('Step 1: Storage already initialized');
      await Future.delayed(const Duration(milliseconds: 100));

      if (!mounted) return;
      setState(() => _status = 'Loading identity...');
      Logger.debug('🔑 Step 2: Loading identity...');
      await Future.delayed(const Duration(milliseconds: 100));

      // P2P might already be initialized from auto-discovery above
      if (p2pService.getStatus()['is_initialized'] != true) {
        if (!mounted) return;
        setState(() => _status = 'Starting P2P node...');
        Logger.debug('🌐 Step 3: Starting P2P node...');
        // Give UI time to render BEFORE blocking initialize() call
        await Future.delayed(const Duration(milliseconds: 300));
        await p2pService.initialize();
      }

      // TODO(coming-soon): Re-enable CallService init when call feature ships
      // if (!mounted) return;
      // setState(() => _status = 'Initializing call service...');
      // Logger.debug('📞 Step 3.5: Initializing call service...');

      if (!mounted) return;
      setState(() => _status = 'Joining DHT network...');
      Logger.debug('📡 Step 4: Joining DHT network...');
      await Future.delayed(const Duration(milliseconds: 100));

      // Get final status
      final status = p2pService.getStatus();
      if (!mounted) return;
      setState(() {
        _status = 'Ready! ${status['architecture']}';
      });

      Logger.success('=== P2P Initialization Complete ===');
      Logger.info('📊 Final Status: $status');
      
      // Brief delay to show "Ready" status before navigation
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Navigate to home screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    } catch (e, stackTrace) {
      Logger.error('INITIALIZATION ERROR', e, stackTrace);
      
      if (mounted) {
        setState(() {
          _status = 'Initialization failed: $e';
          _hasError = true;
        });
      }
    }
  }

  /// Show dialog when node count is critically low - offer discovery
  Future<bool> _showLowNodeCountDialog(
    BuildContext context, {
    required int nodeCount,
  }) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: nodeCount > 0, // Can dismiss if at least 1 node exists
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.warning_amber,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Low Node Count'),
        content: Text(
          nodeCount == 0
              ? 'You have no Oasis Nodes configured.\n\nWould you like to discover available nodes now?'
              : 'You only have 1 Oasis Node configured. For better reliability and privacy, we recommend discovering more nodes.',
          textAlign: TextAlign.center,
        ),
        actions: [
          if (nodeCount > 0)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Continue Anyway'),
            ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.search),
            label: const Text('Discover Nodes'),
          ),
        ],
      ),
    ) ?? false;
  }

  /// Perform node discovery and add discovered nodes
  Future<bool> _performNodeDiscovery({
    required nodeDiscoveryService,
    required bootstrapNodesService,
    required p2pService,
  }) async {
    try {
      // Services passed as parameters to avoid ref.read() after disposal
      
      // Initialize P2P if not already done (needed for DHT queries)
      if (p2pService.getStatus()['is_initialized'] != true) {
        Logger.info('🌐 Initializing P2P for discovery...');
        await p2pService.initialize();
        
        // Wait for DHT to bootstrap
        await Future.delayed(const Duration(seconds: 5));
      }
      
      // Discover nodes
      Logger.info('🔍 Starting node discovery...');
      final discoveryResult = await nodeDiscoveryService.discoverNodes(forceRefresh: true);
      
      if (discoveryResult.isFailure || discoveryResult.value.isEmpty) {
        Logger.warning('⚠️ Discovery failed or found no nodes');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No nodes found. Please try again later.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return false;
      }
      
      // Add top 3 discovered nodes
      int addedCount = 0;
      for (final node in discoveryResult.value.take(3)) {
        final multiaddrs = node.multiaddrs;
        if (multiaddrs != null && multiaddrs.isNotEmpty) {
          final multiaddr = multiaddrs.firstWhere(
            (addr) => addr.contains('/tcp/'),
            orElse: () => multiaddrs.first,
          );
          
          final result = await bootstrapNodesService.addNode(
            multiaddr: multiaddr,
            name: 'Public Node ${node.peerID.substring(0, 8)}',
          );
          
          if (result.isSuccess) {
            addedCount++;
          }
        }
      }
      
      Logger.success('✅ Added $addedCount new node(s)');
      
      if (mounted && addedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Added $addedCount new node(s)'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      return addedCount > 0;
    } catch (e) {
      Logger.error('❌ Discovery failed', e);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Discovery failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset(
                'assets/images/logo.png',
                width: 180,
                height: 180,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    _hasError ? Icons.error_outline : Icons.cloud_sync,
                    size: 180,
                    color: _hasError
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  );
                },
              ),
              const SizedBox(height: 32),

              // Title
              Text(
                'Oasis',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Private, decentralized messaging',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
              ),
              const SizedBox(height: 48),

              // Status
              if (!_hasError) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
              ],

              Text(
                _status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _hasError 
                      ? Theme.of(context).colorScheme.error 
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),

              // Retry button on error
              if (_hasError) ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    if (mounted) {
                      setState(() {
                        _hasError = false;
                        _status = 'Retrying...';
                      });
                      _initialize();
                    }
                  },
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

}
