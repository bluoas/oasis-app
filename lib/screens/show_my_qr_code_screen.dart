import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/services_provider.dart';
import '../services/network_service.dart';
import '../utils/top_notification.dart';
import '../utils/logger.dart';
import 'create_private_network_screen.dart';

/// Screen zeigt den eigenen QR-Code zum Scannen durch andere User
/// 
/// Enthält:
/// - Eigene PeerID
/// - Eigenen Namen
/// - Aktuell verbundenen Oasis Node
class ShowMyQrCodeScreen extends ConsumerStatefulWidget {
  const ShowMyQrCodeScreen({super.key});

  @override
  ConsumerState<ShowMyQrCodeScreen> createState() => _ShowMyQrCodeScreenState();
}

class _ShowMyQrCodeScreenState extends ConsumerState<ShowMyQrCodeScreen> {
  
  // Feature flag for network switching UI (temporary disabled)
  static const bool _enableNetworkSwitching = false;
  
  String _userName = '';
  String? _profileImagePath;

  // Private network data (null when on public network)
  String? _psk;
  String? _privateMultiaddr;
  String? _privateNetworkName;
  
  // Network service instance to avoid using ref in dispose
  NetworkService? _networkService;

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadProfileImage();
    _loadPrivateNetworkData();
    
    // Listen for network changes
    _networkService = ref.read(networkServiceProvider);
    _networkService?.addListener(_onNetworkChanged);
  }

  @override
  void dispose() {
    // Remove network listener (safe to use cached instance)
    _networkService?.removeListener(_onNetworkChanged);
    super.dispose();
  }

  /// Called when network changes
  void _onNetworkChanged() {
    // Reload private network data (or clear it if switched to public)
    _loadPrivateNetworkData();
  }

  Future<void> _loadPrivateNetworkData() async {
    final networkService = ref.read(networkServiceProvider);
    
    // If public network, clear private network data
    if (networkService.isPublicNetwork) {
      if (mounted) {
        setState(() {
          _psk = null;
          _privateMultiaddr = null;
          _privateNetworkName = null;
        });
      }
      return;
    }

    // Load private network data
    final activeNetworkId = networkService.activeNetworkId;
    final privateNetworkService = ref.read(privateNetworkSetupServiceProvider);
    final network = privateNetworkService.getNetwork(activeNetworkId);
    if (network == null) {
      // Network not found, clear data
      if (mounted) {
        setState(() {
          _psk = null;
          _privateMultiaddr = null;
          _privateNetworkName = null;
        });
      }
      return;
    }

    const secureStorage = FlutterSecureStorage();
    final psk = await secureStorage.read(key: 'psk_network_$activeNetworkId');

    if (mounted) {
      setState(() {
        _psk = psk;
        _privateMultiaddr = network.multiaddr;
        _privateNetworkName = network.networkName;
      });
    }
  }

  Future<void> _loadUserName() async {
    // Try to load saved user name from SharedPreferences
    final prefs = ref.read(sharedPreferencesProvider);
    final savedName = prefs.getString('user_display_name');
    
    if (savedName != null && savedName.isNotEmpty) {
      setState(() {
        _userName = savedName;
      });
    } else {
      // Default name from PeerID (last 8 chars)
      final peerIDAsync = ref.read(currentPeerIDProvider);
      peerIDAsync.when(
        data: (peerID) {
          if (peerID != null) {
            final defaultName = 'User ${peerID.substring(peerID.length - 8)}';
            setState(() {
              _userName = defaultName;
            });
          }
        },
        loading: () {},
        error: (_, __) {},
      );
    }
  }

  /// Load profile image path from SharedPreferences
  Future<void> _loadProfileImage() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final relativePath = prefs.getString('profile_image_path');
      
      if (relativePath != null && relativePath.isNotEmpty) {
        // Handle both absolute and relative paths
        if (relativePath.startsWith('/')) {
          // Absolute path
          final file = File(relativePath);
          if (await file.exists()) {
            setState(() {
              _profileImagePath = relativePath;
            });
          }
        } else {
          // Relative path - reconstruct from ApplicationSupportDirectory
          final appSupportDir = await getApplicationSupportDirectory();
          final fullPath = '${appSupportDir.path}/$relativePath';
          final file = File(fullPath);
          
          if (await file.exists()) {
            setState(() {
              _profileImagePath = fullPath;
            });
          }
        }
      }
    } catch (e) {
      Logger.warning('Error loading profile image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final peerIDAsync = ref.watch(currentPeerIDProvider);
    final p2pService = ref.read(p2pServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: _enableNetworkSwitching
            ? _buildTitleWithNetwork('My QR Code')
            : const Text('My QR Code'),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
      ),
      body: peerIDAsync.when(
        data: (peerID) {
          if (peerID == null) {
            return const Center(
              child: Text('Error: PeerID not available'),
            );
          }

          // Determine whether we're on a private network
          final isPrivateNetwork = _psk != null && _privateMultiaddr != null;

          String? activeNode;
          if (isPrivateNetwork) {
            // On private network: always use the private node's multiaddr
            activeNode = _privateMultiaddr;
          } else {
            // On public network: Use CURRENTLY CONNECTED node (CRITICAL for key exchange!)
            // This ensures that when someone scans the QR code, the key exchange
            // is stored on the same node that this user is polling from.
            activeNode = p2pService.activeBootstrapNode;

            if (activeNode != null) {
              Logger.info('✅ Using currently connected node in QR code');
            } else {
              Logger.warning('⚠️ No active node connection - QR code may not work for key exchange!');
            }
          }

          final displayName = _userName.isNotEmpty ? _userName : 'User ${peerID.substring(peerID.length - 8)}';

          // Create QR data in compact JSON format
          final qrData = {
            't': 'oasis_contact',  // type (compact)
            'p': peerID,            // peer_id (compact)
            'n': displayName,       // name (compact)
            if (activeNode != null) 'm': activeNode,  // node multiaddr (compact)
            if (isPrivateNetwork) 'k': _psk!,         // PSK (private network only)
            if (isPrivateNetwork && _privateNetworkName != null)
              'net': _privateNetworkName!,             // network name (private network only)
          };

          final qrString = jsonEncode(qrData);
          
          // Debug: Log QR content
          Logger.debug('QR Code generated:');
          Logger.debug('   PeerID: $peerID');
          Logger.debug('   Name: $displayName');
          Logger.debug('   Node: ${activeNode ?? 'NONE - NO NODE AVAILABLE!'}');
          Logger.debug('   Private: $isPrivateNetwork${isPrivateNetwork ? ' (${_privateNetworkName ?? 'unnamed'})' : ''}');
          Logger.debug('   QR JSON: $qrString');

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // QR Code
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // Profile Avatar
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                          backgroundImage: _profileImagePath != null ? FileImage(File(_profileImagePath!)) : null,
                          child: _profileImagePath == null
                              ? Text(
                                  _userName.isNotEmpty ? _userName[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    fontSize: 40,
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 12),
                        // Username below Profile Avatar
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: QrImageView(
                            data: qrString,
                            version: QrVersions.auto,
                            size: 280,
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          isPrivateNetwork
                              ? 'Scan to add & join ${_privateNetworkName ?? 'Private Network'}'
                              : 'Scan to add ${_userName.isNotEmpty ? _userName : 'me'}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Copy Contact Code Button
                GestureDetector(
                  onTap: () async {
                    // Just copy the Base64 code (without oasis:// prefix)
                    // This works everywhere: WhatsApp, Telegram, Email, SMS
                    final base64Data = base64Encode(utf8.encode(qrString));
                    
                    await Clipboard.setData(ClipboardData(text: base64Data));
                    
                    if (mounted) {
                      showTopNotification(
                        context,
                        'Contact code copied!\nShare it via messenger, then receiver can paste it in "Add Contact".',
                        duration: const Duration(seconds: 3),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.share,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Share Contact Code',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Error loading PeerID: $error'),
        ),
      ),
    );
  }

  Widget _buildTitleWithNetwork(String title) {
    final networkService = ref.watch(networkServiceProvider);
    final privateNetworkSetupService = ref.watch(privateNetworkSetupServiceProvider);
    
    // Get network names map
    final networks = privateNetworkSetupService.getAllNetworks();
    final networkNames = {for (var n in networks) n.networkId: n.networkName};
    
    final activeNetworkName = networkService.getActiveNetworkName(networkNames);
    
    return InkWell(
      onTap: () => _showNetworkSelectorDialog(context),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  networkService.isPublicNetwork ? Icons.public : Icons.shield,
                  size: 12,
                  color: networkService.isPublicNetwork ? Colors.blue : Colors.green,
                ),
                const SizedBox(width: 4),
                Text(
                  activeNetworkName,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_drop_down,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNetworkSelectorDialog(BuildContext context) async {
    // Save scaffold context for notifications after dialog closes
    final scaffoldContext = context;
    
    final networkService = ref.read(networkServiceProvider);
    final privateNetworkSetupService = ref.read(privateNetworkSetupServiceProvider);
    final p2pService = ref.read(p2pServiceProvider);
    
    final networks = privateNetworkSetupService.getAllNetworks();
    final currentNetworkId = networkService.activeNetworkId;
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Select Network',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          tooltip: 'Create Private Network',
                          onPressed: () async {
                            Navigator.pop(context);
                            await Navigator.push<bool>(
                              scaffoldContext,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const CreatePrivateNetworkScreen(),
                              ),
                            );
                            if (mounted) {
                              // Reload private network data
                              await _loadPrivateNetworkData();
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose which network to connect to',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              
              // Network list
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Public Network option
                    _buildNetworkOption(
                      context: context,
                      networkId: 'public',
                      networkName: 'Public Network',
                      icon: Icons.public,
                      iconColor: Colors.blue,
                      description: 'Connect to random discovered nodes',
                      isActive: currentNetworkId == 'public',
                      onTap: () async {
                        Navigator.pop(context);
                        
                        // Show loading dialog during network switch
                        if (!mounted) return;
                        showDialog(
                          context: scaffoldContext,
                          barrierDismissible: false,
                          builder: (context) => PopScope(
                            canPop: false,
                            child: Center(
                              child: Card(
                                margin: const EdgeInsets.all(32),
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const CircularProgressIndicator(),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Switching to Public Network...',
                                        style: TextStyle(fontSize: 16),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Connecting to bootstrap nodes',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                        
                        try {
                          await networkService.switchToNetwork('public');
                          
                          // Reinitialize P2P with public network
                          await p2pService.reinitialize();
                          
                          if (mounted) {
                            Navigator.of(scaffoldContext).pop(); // Close loading dialog
                            showTopNotification(
                              scaffoldContext,
                              'Switched to Public Network',
                            );
                            
                            // Reload data
                            await _loadPrivateNetworkData();
                          }
                        } catch (e) {
                          if (mounted) {
                            Navigator.of(scaffoldContext).pop(); // Close loading dialog
                            showTopNotification(
                              scaffoldContext,
                              'Failed to switch network: $e',
                            );
                          }
                        }
                      },
                    ),
                    
                    // Divider between Public and Private
                    if (networks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'PRIVATE NETWORKS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                    
                    // Private Networks
                    ...networks.map((network) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildNetworkOption(
                        context: context,
                        networkId: network.networkId,
                        networkName: network.networkName,
                        icon: Icons.shield,
                        iconColor: Colors.green,
                        description: '${network.nodeCount} ${network.nodeCount == 1 ? 'node' : 'nodes'}',
                        isActive: currentNetworkId == network.networkId,
                        onTap: () async {
                          Navigator.pop(context);
                          
                          // Show loading dialog during network switch
                          if (!mounted) return;
                          showDialog(
                            context: scaffoldContext,
                            barrierDismissible: false,
                            builder: (context) => PopScope(
                              canPop: false,
                              child: Center(
                                child: Card(
                                  margin: const EdgeInsets.all(32),
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const CircularProgressIndicator(),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Switching to ${network.networkName}...',
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Connecting with PSK authentication',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                          
                          try {
                            await networkService.switchToNetwork(network.networkId);
                            
                            // Reinitialize P2P with private network
                            await p2pService.reinitialize();
                            
                            if (mounted) {
                              Navigator.of(scaffoldContext).pop(); // Close loading dialog
                              showTopNotification(
                                scaffoldContext,
                                'Switched to ${network.networkName}',
                              );
                              
                              // Reload data
                              await _loadPrivateNetworkData();
                            }
                          } catch (e) {
                            if (mounted) {
                              Navigator.of(scaffoldContext).pop(); // Close loading dialog
                              showTopNotification(
                                scaffoldContext,
                                'Failed to switch network: $e',
                              );
                            }
                          }
                        },
                      ),
                    )),
                    
                    // Empty state if no private networks
                    if (networks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 48,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No Private Networks',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Join or create a private network to see it here',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkOption({
    required BuildContext context,
    required String networkId,
    required String networkName,
    required IconData icon,
    required Color iconColor,
    required String description,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isActive ? iconColor.withOpacity(0.5) : Colors.grey.withOpacity(0.3),
          width: isActive ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
        color: isActive ? iconColor.withOpacity(0.1) : Colors.transparent,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Text(
          networkName,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
          ),
        ),
        subtitle: Text(
          description,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: isActive
            ? Icon(Icons.check_circle, color: iconColor, size: 24)
            : Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 24),
        onTap: isActive ? null : onTap,
      ),
    );
  }
}
