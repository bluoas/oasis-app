import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart'; // For InitializationScreen
import '../providers/services_provider.dart';

/// Simplified onboarding screen shown on first app launch
/// 
/// Automatically discovers and connects to public Oasis nodes via DHT.
/// No manual setup required - just tap to get started.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              
              // Logo
              Image.asset(
                'assets/images/logo.png',
                width: 150,
                height: 150,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.wb_sunny_outlined,
                    size: 150,
                    color: Theme.of(context).colorScheme.primary,
                  );
                },
              ),
              const SizedBox(height: 32),

              // Welcome Title
              Text(
                'Welcome to Oasis',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),

              // Subtitle
              Text(
                'Private, decentralized messaging',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
              ),
              
              const Spacer(),

              // Main CTA Button
              FilledButton.icon(
                onPressed: () => _joinPublicNetwork(context, ref),
                icon: const Icon(Icons.rocket_launch),
                label: const Text('Get Started'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Info text
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.security,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Privacy through traffic mixing',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.wifi_tethering,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Connects automatically to public nodes',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Setup takes 30-60 seconds',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
  
  /// Join public network via auto-discovery
  void _joinPublicNetwork(BuildContext context, WidgetRef ref) async {
    // Show loading dialog with better design
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated loading indicator
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    strokeWidth: 6,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 24),
                
                // Title
                Text(
                  'Connecting to Oasis',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                
                // Description
                const Text(
                  'Discovering public nodes via DHT...\nThis may take 30-60 seconds',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    try {
      // CRITICAL: Delete old identity if exists (prevents key conflicts after reinstall)
      // When onboarding screen is shown, all contacts are gone → old identity is useless
      // A fresh identity prevents encryption key mismatches with old keys
      final identityService = ref.read(identityServiceProvider);
      await identityService.deleteIdentity();
      
      // Step 1: Initialize P2P Service (will generate NEW identity)
      final p2pService = ref.read(p2pServiceProvider);
      await p2pService.initialize();
      
      // Step 2: Wait for DHT to bootstrap (critical for discovery!)
      await Future.delayed(const Duration(seconds: 10));
      
      // Step 3: Start automatic node discovery
      final nodeDiscoveryService = ref.read(nodeDiscoveryServiceProvider);
      final discoveryResult = await nodeDiscoveryService.discoverNodes(forceRefresh: true);
      
      if (discoveryResult.isFailure || discoveryResult.value.isEmpty) {
        throw Exception('No public Oasis Nodes found in DHT. Please try again later.');
      }
      
      // Step 4: Connect to a random discovered node (for privacy & load distribution)
      final randomNode = nodeDiscoveryService.selectRandomNode();
      if (randomNode == null) {
        throw Exception('No compatible nodes found');
      }
      
      final connected = await p2pService.connectToDiscoveredNode(randomNode.peerID);
      
      if (!connected) {
        // Try other discovered nodes as fallback
        bool anyConnected = false;
        for (final node in discoveryResult.value) {
          if (node.peerID != randomNode.peerID) {
            if (await p2pService.connectToDiscoveredNode(node.peerID)) {
              anyConnected = true;
              break;
            }
          }
        }
        
        if (!anyConnected) {
          throw Exception('Failed to connect to any discovered node');
        }
      }
      
      // Step 5: Save discovered nodes as bootstrap nodes
      // This ensures onboarding won't show again on next app start
      final bootstrapService = ref.read(bootstrapNodesServiceProvider);
      for (final node in discoveryResult.value.take(3)) {
        // Save top 3 nodes
        final multiaddrs = node.multiaddrs;
        if (multiaddrs != null && multiaddrs.isNotEmpty) {
          final multiaddr = multiaddrs.firstWhere(
            (addr) => addr.contains('/tcp/'),
            orElse: () => multiaddrs.first,
          );
          
          await bootstrapService.addNode(
            multiaddr: multiaddr,
            name: 'Public Node ${node.peerID.substring(0, 8)}',
          );
        }
      }
      
      // Step 6: Close loading dialog and navigate to home
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const InitializationScreen()),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        
        // Show error with retry option
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.error_outline, size: 48, color: Colors.red),
            title: const Text('Connection Failed'),
            content: Text(
              'Could not connect to Oasis network.\n\n$e',
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _joinPublicNetwork(context, ref);
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      }
    }
  }
}
