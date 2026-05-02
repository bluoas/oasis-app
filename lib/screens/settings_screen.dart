import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/contact.dart';
import '../providers/services_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart';
import 'network_stats_screen.dart';
import 'setup_auth_wizard.dart';
import '../widgets/pin_input_dots.dart';
import '../widgets/pin_pad_widget.dart';
import '../utils/top_notification.dart';
import '../utils/notification_utils.dart';
import '../utils/logger.dart';

/// Settings Screen
/// 
/// Configuration options for the Oasis app:
/// - Network preferences
/// - Identity management
/// - Notification settings
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _vibrationEnabled = true;
  bool _soundEnabled = true;
  bool _contactsChanged = false;
  String _appVersion = 'Loading...';
  String _userName = 'Me';
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
    _loadAppVersion();
    _loadUserName();
  }

  Future<void> _loadUserName() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final savedName = prefs.getString('user_display_name');
      
      if (savedName != null && savedName.isNotEmpty) {
        if (mounted) {
          setState(() {
            _userName = savedName;
          });
        }
      } else {
        // Default name from PeerID (last 8 chars)
        final peerID = await ref.read(currentPeerIDProvider.future);
        
        if (peerID != null && mounted) {
          final defaultName = 'User ${peerID.substring(peerID.length - 8)}';
          setState(() {
            _userName = defaultName;
          });
        }
      }
    } catch (e) {
      Logger.error('Error loading username', e);
    }
  }

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      });
    }
  }

  Future<void> _loadNotificationSettings() async {
    final vibration = await NotificationUtils.isVibrationEnabled();
    final sound = await NotificationUtils.isSoundEnabled();
    if (mounted) {
      setState(() {
        _vibrationEnabled = vibration;
        _soundEnabled = sound;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final peerIDAsync = ref.watch(currentPeerIDProvider);

    return WillPopScope(
      onWillPop: () async {
        // Return the contacts changed flag when navigating back
        Navigator.of(context).pop(_contactsChanged);
        return false; // Prevent default pop
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
      ),
      body: ListView(
        children: [
          // Identity Section
          _buildSectionHeader('Identity'),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('User Name'),
            subtitle: Text(
              _userName,
              style: TextStyle(color: Colors.grey[600]),
            ),
            trailing: const Icon(Icons.edit),
            onTap: _editUserName,
          ),
          const Divider(height: 1),
          peerIDAsync.when(
            data: (peerID) {
              // Format peer ID: show first 12 and last 8 characters
              final displayPeerID = peerID != null && peerID.length > 24
                  ? '${peerID.substring(0, 12)}...${peerID.substring(peerID.length - 8)}'
                  : (peerID ?? 'Not initialized');
              
              return ListTile(
                leading: const Icon(Icons.fingerprint),
                title: const Text('Peer ID'),
                subtitle: Text(
                  displayPeerID,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: peerID != null ? () {
                    Clipboard.setData(ClipboardData(text: peerID));
                    showTopNotification(context, 'Peer ID copied!');
                  } : null,
                ),
              );
            },
            loading: () => const ListTile(
              leading: Icon(Icons.fingerprint),
              title: Text('Peer ID'),
              subtitle: Text('Loading...'),
            ),
            error: (error, stack) => ListTile(
              leading: const Icon(Icons.error, color: Colors.red),
              title: const Text('Peer ID'),
              subtitle: Text('Error: $error'),
            ),
          ),
          const Divider(),

          // Network Section
          _buildSectionHeader('Network'),
          ListTile(
            leading: const Icon(Icons.hub),
            title: const Text('IPFS Infrastructure Nodes'),
            subtitle: Text(
              'Public DHT backbone nodes (read-only)',
              style: TextStyle(color: Colors.grey[600]),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showIPFSInfrastructureNodesDialog(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Public Network Nodes'),
            subtitle: Text(
              'Random node per app start for privacy',
              style: TextStyle(color: Colors.grey[600]),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showUserBootstrapNodesDialog(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.orange),
            title: const Text('Blacklisted Nodes'),
            subtitle: Text(
              'Unreachable nodes (24h timeout)',
              style: TextStyle(color: Colors.grey[600]),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showBlacklistedNodesDialog(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.cloud),
            title: const Text('My Private Networks'),
            subtitle: Text(
              'Manage your own relay/storage nodes',
              style: TextStyle(color: Colors.grey[600]),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showMyNodesDialog(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('Network Statistics'),
            subtitle: Text(
              'View connection status and message delivery stats',
              style: TextStyle(color: Colors.grey[600]),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NetworkStatsScreen(),
              ),
            ),
          ),

          const Divider(),

          // Privacy Section
          _buildSectionHeader('Privacy'),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Blocked Contacts'),
            subtitle: Text(
              'Manage blocked contacts',
              style: TextStyle(color: Colors.grey[600]),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showBlockedContactsDialog(context),
          ),

          const Divider(),

          // Notifications Section
          _buildSectionHeader('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Vibrate on incoming messages'),
            subtitle: Text(
              'Feel a vibration when you receive new messages',
              style: TextStyle(color: Colors.grey[600]),
            ),
            value: _vibrationEnabled,
            onChanged: (value) async {
              await NotificationUtils.setVibrationEnabled(value);
              setState(() {
                _vibrationEnabled = value;
              });
              if (mounted) {
                showTopNotification(
                  context,
                  value ? 'Vibration enabled' : 'Vibration disabled',
                );
                // Give immediate feedback
                if (value) {
                  await NotificationUtils.vibrateForIncomingMessage();
                }
              }
            },
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active),
            title: const Text('Message sound'),
            subtitle: Text(
              'Play sound for new messages',
              style: TextStyle(color: Colors.grey[600]),
            ),
            value: _soundEnabled,
            onChanged: (value) async {
              await NotificationUtils.setSoundEnabled(value);
              setState(() {
                _soundEnabled = value;
              });
              if (mounted) {
                showTopNotification(
                  context,
                  value ? 'Sound enabled' : 'Sound disabled',
                );
                // Give immediate feedback
                if (value) {
                  await NotificationUtils.playSoundForIncomingMessage();
                }
              }
            },
          ),

          const Divider(),

          // Security Section
          _buildSectionHeader('Security'),
          _buildAppLockToggle(),
          
          const Divider(),

          // Theme Section
          _buildSectionHeader('Appearance'),
          _buildThemeSelector(),
          
          const Divider(),

          // About Section
          _buildSectionHeader('About'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.info_outline,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Version',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _appVersion,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(
                      height: 1,
                      color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.architecture_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Architecture',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Pure P2P with DHT-based discovery',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ── Danger Zone ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              'Danger Zone',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red.withOpacity(0.5), width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text(
                'Reset Identity',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Permanently deletes your keys, all contacts and messages',
                style: TextStyle(color: Colors.red[300], fontSize: 12),
              ),
              trailing: const Icon(Icons.warning_amber_rounded, color: Colors.red),
              onTap: () => _confirmResetIdentity(context),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
      ), // Close Scaffold
    ); // Close WillPopScope
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _editUserName() async {
    _nameController.text = _userName;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Center(child: Text('Edit User Name')),
        content: TextField(
          controller: _nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter your name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            final trimmedValue = value.trim();
            if (trimmedValue.isEmpty) {
              Navigator.pop(context);
              return;
            }
            
            // Check for reserved name (case-insensitive, ignore spaces)
            final normalizedName = trimmedValue.toLowerCase().replaceAll(' ', '');
            if (normalizedName == 'oasiskeymanager') {
              Navigator.pop(context);
              showTopNotification(
                context,
                'This name is reserved for system use',
                isError: true,
              );
              return;
            }
            
            Navigator.pop(context);
            _saveUserName(trimmedValue);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final newName = _nameController.text.trim();
              if (newName.isEmpty) {
                Navigator.pop(context);
                return;
              }
              
              // Check for reserved name (case-insensitive, ignore spaces)
              final normalizedName = newName.toLowerCase().replaceAll(' ', '');
              if (normalizedName == 'oasiskeymanager') {
                Navigator.pop(context);
                showTopNotification(
                  context,
                  'This name is reserved for system use',
                  isError: true,
                );
                return;
              }
              
              Navigator.pop(context);
              _saveUserName(newName);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveUserName(String newName) async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString('user_display_name', newName);
      
      if (mounted) {
        setState(() {
          _userName = newName;
        });
        
        // Show success notification
        showTopNotification(
          context,
          'User name updated',
        );
        
        // Broadcast profile update to all contacts
        final p2pService = ref.read(p2pServiceProvider);
        
        // Send profile update to notify contacts of name change
        await p2pService.sendProfileUpdate(
          userName: newName,
          profileImagePath: null,
        );
      }
    } catch (e) {
      Logger.error('Error saving username', e);
      if (mounted) {
        showTopNotification(
          context,
          'Failed to save name',
          isError: true,
        );
      }
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildThemeSelector() {
    final themeMode = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);

    return Column(
      children: [
        ListTile(
          leading: Icon(
            themeMode == ThemeMode.dark
                ? Icons.dark_mode
                : themeMode == ThemeMode.light
                    ? Icons.light_mode
                    : Icons.brightness_auto,
          ),
          title: const Text('Theme Mode'),
          subtitle: Text(
            themeMode == ThemeMode.dark
                ? 'Dark'
                : themeMode == ThemeMode.light
                    ? 'Light'
                    : 'System',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Expanded(
                child: _buildThemeButton(
                  context: context,
                  label: 'Light',
                  icon: Icons.light_mode,
                  isSelected: themeMode == ThemeMode.light,
                  onTap: () => themeNotifier.setLightMode(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildThemeButton(
                  context: context,
                  label: 'Dark',
                  icon: Icons.dark_mode,
                  isSelected: themeMode == ThemeMode.dark,
                  onTap: () => themeNotifier.setDarkMode(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildThemeButton(
                  context: context,
                  label: 'System',
                  icon: Icons.brightness_auto,
                  isSelected: themeMode == ThemeMode.system,
                  onTap: () => themeNotifier.setSystemMode(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildThemeButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.primary.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmResetIdentity(BuildContext context) async {
    // Step 1: Explain consequences
    final step1 = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Reset Identity?'),
          ],
        ),
        content: const Text(
          'This will permanently DELETE:\n\n'
          '• Your cryptographic identity (Peer ID + keys)\n'
          '• All messages\n'
          '• All contacts\n\n'
          'Contacts will no longer be able to reach you and you will need to re-exchange keys with everyone.\n\n'
          'This action CANNOT be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('I understand, continue'),
          ),
        ],
      ),
    );

    if (step1 != true || !mounted) return;

    // Step 2: Require typing DELETE
    final deleteController = TextEditingController();
    final step2 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Confirm deletion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Type DELETE to confirm:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: deleteController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'DELETE',
                  border: const OutlineInputBorder(),
                  errorText: deleteController.text.isNotEmpty &&
                          deleteController.text != 'DELETE'
                      ? 'Must be exactly DELETE'
                      : null,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: deleteController.text == 'DELETE'
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('DELETE IDENTITY'),
            ),
          ],
        ),
      ),
    );

    deleteController.dispose();

    if (step2 != true || !mounted) return;

    if (mounted) {
      try {
        final identityService = ref.read(identityServiceProvider);
        final p2pService = ref.read(p2pServiceProvider);
        final storageService = ref.read(storageServiceProvider);

        // Delete identity
        final deleteResult = await identityService.deleteIdentity();
        if (deleteResult.isFailure) {
          throw Exception('Failed to delete identity: ${deleteResult.errorOrNull?.userMessage}');
        }

        // Clear storage
        final clearResult = await storageService.clearAll();
        if (clearResult.isFailure) {
          throw Exception('Failed to clear storage: ${clearResult.errorOrNull?.userMessage}');
        }

        // Reinitialize
        await p2pService.reinitialize();

        if (mounted) {
          showTopNotification(
            context,
            'Identity reset complete!',
          );
        }
      } catch (e) {
        if (mounted) {
          showTopNotification(
            context,
            'Reset failed: $e',
            isError: true,
          );
        }
      }
    }
  }

  Future<void> _showMyNodesDialog(BuildContext context) async {
    final privateNetworkSetupService = ref.read(privateNetworkSetupServiceProvider);
    final networks = privateNetworkSetupService.getAllNetworks();
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: networks.isEmpty ? 0.5 : 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
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
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Private Networks',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Your private networks',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              
              // Network list or empty state
              Expanded(
                child: networks.isEmpty
                    ? _buildEmptyNodesState(context)
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: networks.length,
                        itemBuilder: (context, index) {
                          final network = networks[index];
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.blue.withOpacity(0.3),
                              ),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.blue.withOpacity(0.05),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.shield,
                                  color: Colors.blue,
                                  size: 24,
                                ),
                              ),
                              title: Text(
                                network.networkName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    '${network.nodeCount} ${network.nodeCount == 1 ? 'node' : 'nodes'}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Created ${_formatDate(network.createdAt)}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _confirmRemovePrivateNetwork(
                                  context,
                                  network.networkId,
                                  network.networkName,
                                  network.multiaddr,
                                ),
                              ),
                              onTap: () => _showNetworkDetails(context, network),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyNodesState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_open_outlined,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 24),
            const Text(
              'No Private Network',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'You haven\'t created or joined a private network yet.\n\nCreate your own at joinoasis.io',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }

  void _showNetworkDetails(BuildContext context, dynamic network) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(network.networkName),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Node:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                network.networkId,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                network.multiaddr,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemovePrivateNetwork(
    BuildContext context,
    String networkId,
    String networkName,
    String nodeMultiaddr,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Private Network?'),
        content: Text(
          'Remove "$networkName"?\n\n'
          'This will disconnect from the node and remove all network data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final p2pService = ref.read(p2pServiceProvider);
      final privateNetworkSetupService = ref.read(privateNetworkSetupServiceProvider);
      
      // Show loading indicator
      if (mounted) {
        showTopNotification(
          context,
          'Removing network...',
          duration: const Duration(seconds: 3),
        );
      }
      
      // Disconnect from the network node
      try {
        await p2pService.disconnectAndRemoveNode(nodeMultiaddr);
      } catch (e) {
        Logger.warning('Failed to disconnect from node: $e');
      }
      
      // Remove network data
      await privateNetworkSetupService.removeNetwork(networkId);
      
      if (mounted) {
        Navigator.pop(context);
        showTopNotification(
          context,
          '"$networkName" removed',
        );
        // Reopen dialog to show updated list
        _showMyNodesDialog(context);
      }
    }
  }


  Future<void> _showIPFSInfrastructureNodesDialog(BuildContext context) async {
    final p2pService = ref.read(p2pServiceProvider);
    final nodeInfo = p2pService.getNodeInfo();
    
    final configBootstrapNodes = (nodeInfo['bootstrap_nodes'] as List<dynamic>?)?.cast<String>() ?? [];
    final connectedNodes = (nodeInfo['connected_nodes'] as List<dynamic>?)?.cast<String>() ?? [];
    final activeBootstrapNode = nodeInfo['active_bootstrap_node'] as String?;
    
    // Build list with only config nodes (IPFS infrastructure)
    final nodesList = <Map<String, dynamic>>[];
    
    for (final multiaddr in configBootstrapNodes) {
      final peerID = _extractPeerID(multiaddr);
      final isConnected = connectedNodes.any((addr) => addr.contains(peerID));
      // Check if active by comparing PeerID (handles both full multiaddr and /p2p/{peerID} format)
      final isActive = activeBootstrapNode != null && 
                       (activeBootstrapNode == multiaddr || activeBootstrapNode.contains(peerID));
      
      nodesList.add({
        'peer_id': peerID,
        'multiaddr': multiaddr,
        'connected': isConnected,
        'active': isActive,
      });
    }
    
    // Sort: active first, then connected, then others
    nodesList.sort((a, b) {
      if (a['active'] != b['active']) return (b['active'] as bool) ? 1 : -1;
      if (a['connected'] != b['connected']) return (b['connected'] as bool) ? 1 : -1;
      return 0;
    });
    
    if (!context.mounted) return;
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
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
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'IPFS Infrastructure Nodes',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Public DHT backbone nodes (read-only)',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Node list
              Expanded(
                child: nodesList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cloud_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No infrastructure nodes configured',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: nodesList.length,
                        itemBuilder: (context, index) {
                          final node = nodesList[index];
                          final peerID = node['peer_id'] as String;
                          final multiaddr = node['multiaddr'] as String;
                          final isConnected = node['connected'] as bool;
                          final isActive = node['active'] as bool;
                          
                          final borderColor = isActive
                              ? Colors.blue.withOpacity(0.5)
                              : (isConnected
                                  ? Colors.green.withOpacity(0.3)
                                  : Colors.grey.withOpacity(0.3));
                          final bgColor = isActive
                              ? Colors.blue.withOpacity(0.1)
                              : (isConnected
                                  ? Colors.green.withOpacity(0.05)
                                  : Colors.grey.withOpacity(0.05));
                          final iconColor = isActive
                              ? Colors.blue
                              : (isConnected ? Colors.green : Colors.grey);
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: borderColor),
                              borderRadius: BorderRadius.circular(12),
                              color: bgColor,
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: iconColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.hub,
                                  color: iconColor,
                                  size: 24,
                                ),
                              ),
                              title: Text(
                                peerID.length > 30 
                                    ? '${peerID.substring(0, 30)}...'
                                    : peerID,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'IPFS',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[700],
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (isActive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Active',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.blue,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      if (isConnected)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Connected',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: multiaddr));
                                showTopNotification(
                                  context,
                                  'Node address copied!',
                                  duration: const Duration(seconds: 1),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showUserBootstrapNodesDialog(BuildContext context) async {
    final p2pService = ref.read(p2pServiceProvider);
    final nodeInfo = p2pService.getNodeInfo();
    final bootstrapNodesService = ref.read(bootstrapNodesServiceProvider);
    
    // Store the settings screen context for later use
    final settingsScreenContext = context;
    
    // Initialize bootstrap nodes service if not yet done
    if (bootstrapNodesService.nodes.isEmpty) {
      final initResult = await bootstrapNodesService.initialize();
      if (initResult.isFailure && context.mounted) {
        showTopNotification(
          context,
          'Failed to load user bootstrap nodes',
          isError: true,
        );
      }
    }
    
    final userBootstrapNodes = bootstrapNodesService.nodes;
    final connectedNodes = (nodeInfo['connected_nodes'] as List<dynamic>?)?.cast<String>() ?? [];
    final deprecatedNodes = (nodeInfo['deprecated_peer_ids'] as List<dynamic>?)?.cast<String>() ?? [];
    final activeBootstrapNode = nodeInfo['active_bootstrap_node'] as String?;
    
    // Build list with only user-added nodes
    final nodesList = <Map<String, dynamic>>[];
    
    // Add user-added nodes (deletable)
    for (final node in userBootstrapNodes) {
      final peerID = node.peerID;
      final isConnected = connectedNodes.any((addr) => addr.contains(peerID));
      final isDeprecated = deprecatedNodes.contains(peerID);
      // Check if active by comparing PeerID (handles both full multiaddr and /p2p/{peerID} format)
      final isActive = activeBootstrapNode != null && 
                       (activeBootstrapNode == node.multiaddr || activeBootstrapNode.contains(peerID));
      
      nodesList.add({
        'peer_id': peerID,
        'multiaddr': node.multiaddr,
        'name': node.name,
        'connected': isConnected,
        'deprecated': isDeprecated,
        'active': isActive,
      });
    }
    
    // Sort: active first, then connected, then others
    nodesList.sort((a, b) {
      if (a['active'] != b['active']) return (b['active'] as bool) ? 1 : -1;
      if (a['connected'] != b['connected']) return (b['connected'] as bool) ? 1 : -1;
      return 0;
    });
    
    if (!context.mounted) return;
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
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
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Public Network Nodes',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Auto-discovered nodes for relay connections',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'Discover more nodes',
                      onPressed: () async {
                        // Close the bottom sheet first
                        Navigator.of(context).pop();
                        
                        // Wait a frame for dialog to fully close
                        await Future.delayed(const Duration(milliseconds: 50));
                        
                        // Trigger discovery with the SETTINGS SCREEN context, not the bottom sheet context
                        if (settingsScreenContext.mounted) {
                          await _triggerNodeDiscovery(settingsScreenContext);
                        } else {
                          Logger.warning('⚠️ Settings screen context not mounted after closing bottom sheet');
                        }
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Node list
              Expanded(
                child: nodesList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.cloud_off,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No bootstrap nodes configured',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: nodesList.length,
                        itemBuilder: (context, index) {
                          final node = nodesList[index];
                          final peerID = node['peer_id'] as String;
                          final multiaddr = node['multiaddr'] as String;
                          final nodeName = node['name'] as String?;
                          final isConnected = node['connected'] as bool;
                          final isDeprecated = node['deprecated'] as bool;
                          final isActive = node['active'] as bool;
                          
                          // Format peer ID: show first 12 and last 8 characters
                          final displayPeerID = peerID.length > 24
                              ? '${peerID.substring(0, 12)}...${peerID.substring(peerID.length - 8)}'
                              : peerID;
                          
                          // Determine colors based on status (active nodes get blue highlight)
                          final borderColor = isActive
                              ? Colors.blue.withOpacity(0.5)
                              : (isDeprecated 
                                  ? Colors.red.withOpacity(0.3)
                                  : (isConnected
                                      ? Colors.green.withOpacity(0.3)
                                      : Colors.grey.withOpacity(0.3)));
                          final bgColor = isActive
                              ? Colors.blue.withOpacity(0.1)
                              : (isDeprecated
                                  ? Colors.red.withOpacity(0.05)
                                  : (isConnected
                                      ? Colors.green.withOpacity(0.05)
                                      : Colors.grey.withOpacity(0.05)));
                          final iconColor = isActive
                              ? Colors.blue
                              : (isDeprecated
                                  ? Colors.red
                                  : (isConnected ? Colors.green : Colors.grey));
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: borderColor),
                              borderRadius: BorderRadius.circular(12),
                              color: bgColor,
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: iconColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.dns,
                                  color: iconColor,
                                  size: 24,
                                ),
                              ),
                              title: Text(
                                nodeName ?? displayPeerID,
                                style: TextStyle(
                                  fontFamily: nodeName != null ? null : 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDeprecated ? Colors.red : null,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (nodeName != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      displayPeerID,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontFamily: 'monospace',
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      if (isActive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Active',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.blue,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      if (isConnected)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Connected',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      if (isDeprecated)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Deprecated',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: multiaddr));
                                showTopNotification(
                                  context,
                                  'Node address copied!',
                                  duration: const Duration(seconds: 1),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
              
              // Info text about automatic management
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Automatic Management',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Nodes are discovered automatically via DHT\n'
                      '• Random node selected on each app start for privacy\n'
                      '• Unreachable nodes are temporarily blocked (24h)\n'
                      '• System failover ensures continuous connectivity',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        height: 1.5,
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

  /// Trigger node discovery from Settings UI
  Future<void> _triggerNodeDiscovery(BuildContext context) async {
    // Store reference to know if we opened a dialog
    bool dialogShown = false;
    
    try {
      // Show loading dialog
      Logger.info('🔄 [Discovery UI] Opening loading dialog...');
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Discovering nodes...'),
            ],
          ),
        ),
      );
      dialogShown = true;
      Logger.info('✅ [Discovery UI] Loading dialog opened (dialogShown=true)');

      final nodeDiscoveryService = ref.read(nodeDiscoveryServiceProvider);
      final bootstrapNodesService = ref.read(bootstrapNodesServiceProvider);
      final p2pService = ref.read(p2pServiceProvider);
      
      // Initialize P2P if not already done (needed for DHT queries)
      if (p2pService.getStatus()['is_initialized'] != true) {
        Logger.info('🌐 Initializing P2P for discovery...');
        await p2pService.initialize();
        
        // Wait for DHT to bootstrap
        await Future.delayed(const Duration(seconds: 5));
      }
      
      // Discover nodes
      Logger.info('🔍 Starting node discovery from Settings...');
      final discoveryResult = await nodeDiscoveryService.discoverNodes(forceRefresh: true);
      
      Logger.info('📊 [Discovery UI] Discovery completed, processing results...');
      
      // Add top 3 discovered nodes
      int addedCount = 0;
      if (discoveryResult.isSuccess && discoveryResult.value.isNotEmpty) {
        Logger.info('🔄 [Discovery UI] Adding nodes (${discoveryResult.value.length} found)...');
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
      }
      
      Logger.success('✅ Added $addedCount new node(s) from Settings');
      
      // Close loading dialog FIRST before showing any other UI
      Logger.info('🔄 [Discovery UI] Attempting to close loading dialog (context.mounted=${context.mounted}, dialogShown=$dialogShown)');
      if (context.mounted && dialogShown) {
        Navigator.of(context).pop();
        dialogShown = false;
        Logger.info('✅ [Discovery UI] Loading dialog closed successfully');
      } else {
        Logger.warning('⚠️ [Discovery UI] Cannot close dialog - context.mounted=${context.mounted}, dialogShown=$dialogShown');
      }
      
      // Small delay to ensure dialog is fully closed
      Logger.debug('⏳ [Discovery UI] Waiting 100ms for dialog to fully close...');
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Then show feedback and reopen node list
      Logger.info('🔄 [Discovery UI] Preparing to show feedback (context.mounted=${context.mounted})');
      if (!context.mounted) {
        Logger.warning('⚠️ [Discovery UI] Context not mounted, aborting feedback');
        return;
      }
      
      if (discoveryResult.isFailure || discoveryResult.value.isEmpty) {
        Logger.warning('⚠️ Discovery failed or found no nodes');
        showTopNotification(
          context,
          'No new nodes found',
          isError: true,
        );
        Logger.info('📢 [Discovery UI] Showed "no nodes" notification');
        return;
      }
      
      if (addedCount > 0) {
        Logger.info('📢 [Discovery UI] Showing success notification for $addedCount nodes');
        showTopNotification(
          context,
          'Added $addedCount new node(s)',
        );
        // Reopen dialog with updated list
        Logger.info('🔄 [Discovery UI] Reopening node list dialog...');
        await _showUserBootstrapNodesDialog(context);
        Logger.info('✅ [Discovery UI] Node list dialog opened');
      } else {
        Logger.info('📢 [Discovery UI] All nodes already added, showing notification');
        showTopNotification(
          context,
          'All discovered nodes already added',
        );
      }
      
      Logger.info('✅ [Discovery UI] Discovery flow completed successfully');
    } catch (e) {
      Logger.error('❌ Discovery failed from Settings', e);
      
      // Close loading dialog if it's still open
      Logger.info('🔄 [Discovery UI] Error occurred, attempting to close loading dialog (context.mounted=${context.mounted}, dialogShown=$dialogShown)');
      if (context.mounted && dialogShown) {
        Navigator.of(context).pop();
        dialogShown = false;
        Logger.info('✅ [Discovery UI] Loading dialog closed after error');
      }
      
      if (context.mounted) {
        showTopNotification(
          context,
          'Discovery failed: $e',
          isError: true,
        );
        Logger.info('📢 [Discovery UI] Showed error notification');
      }
    }
  }

  /// Show blacklisted nodes dialog with management options
  Future<void> _showBlacklistedNodesDialog(BuildContext context) async {
    final bootstrapNodesService = ref.read(bootstrapNodesServiceProvider);
    final blacklistedNodes = bootstrapNodesService.getBlacklistedNodesWithTTL();
    
    if (!context.mounted) return;
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
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
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Blacklisted Nodes',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Temporarily blocked unreachable nodes',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    if (blacklistedNodes.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_sweep, size: 18),
                        label: const Text('Clear All'),
                        onPressed: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Clear Blacklist'),
                              content: const Text(
                                'Remove all nodes from blacklist? They will be available for connection again.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  child: const Text('Clear All'),
                                ),
                              ],
                            ),
                          );
                          
                          if (confirmed == true) {
                            await bootstrapNodesService.clearBlacklist();
                            if (context.mounted) {
                              Navigator.of(context).pop(); // Close dialog
                              showTopNotification(
                                context,
                                'Blacklist cleared',
                              );
                            }
                          }
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Node list
              Expanded(
                child: blacklistedNodes.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle,
                              size: 64,
                              color: Colors.green[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No blacklisted nodes',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'All nodes are available',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: blacklistedNodes.length,
                        itemBuilder: (context, index) {
                          final node = blacklistedNodes[index];
                          final peerID = node['peerID'] as String;
                          final remainingHours = node['remainingHours'] as int;
                          final ageHours = node['ageHours'] as int;
                          
                          // Format: show first 12 and last 8 characters
                          final displayPeerID = peerID.length > 24
                              ? '${peerID.substring(0, 12)}...${peerID.substring(peerID.length - 8)}'
                              : peerID;
                          
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.block,
                                        color: Colors.orange[700],
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          displayPeerID,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${remainingHours}h left',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.orange[700],
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Blacklisted ${ageHours}h ago (unreachable)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          Clipboard.setData(ClipboardData(text: peerID));
                                          showTopNotification(
                                            context,
                                            'Peer ID copied!',
                                            duration: const Duration(seconds: 1),
                                          );
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.copy,
                                                color: Theme.of(context).colorScheme.primary,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Copy ID',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () async {
                                          await bootstrapNodesService.unblacklistNode(peerID);
                                          if (context.mounted) {
                                            Navigator.of(context).pop(); // Close dialog
                                            showTopNotification(
                                              context,
                                              'Node removed from blacklist',
                                            );
                                            // Reopen dialog with updated list
                                            await _showBlacklistedNodesDialog(context);
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: Colors.red.withOpacity(0.3),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.restore,
                                                color: Colors.red,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 6),
                                              const Text(
                                                'Remove',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.red,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              
              // Info text
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'About Blacklist',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Unreachable nodes are automatically blacklisted\n'
                      '• Blacklist expires after 24 hours\n'
                      '• Prevents repeated connection timeouts\n'
                      '• Remove manually if node is back online',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                        height: 1.5,
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

  String _extractPeerID(String multiaddr) {
    final parts = multiaddr.split('/p2p/');
    return parts.length > 1 ? parts.last : multiaddr;
  }

  Future<void> _showBlockedContactsDialog(BuildContext context) async {
    final storageService = ref.read(storageServiceProvider);
    final p2pService = ref.read(p2pServiceProvider);
    final networkService = ref.read(networkServiceProvider);
    
    // Load blocked contacts
    final activeNetworkId = networkService.activeNetworkId;
    final result = await storageService.getContactsForNetwork(activeNetworkId);
    final blockedContacts = result.isSuccess
        ? (result.valueOrNull ?? []).where((c) => c.isBlocked).toList()
        : <Contact>[];
    
    blockedContacts.sort((a, b) => a.displayName.compareTo(b.displayName));
    
    if (!mounted) return;
    
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
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
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Blocked Contacts',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Contacts you have blocked',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Content
              Expanded(
                child: blockedContacts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.block_outlined,
                              size: 80,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No blocked contacts',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Contacts you block will appear here',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: blockedContacts.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final contact = blockedContacts[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.grey.shade400,
                              child: Text(
                                contact.displayName.isNotEmpty
                                    ? contact.displayName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            title: Text(
                              contact.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.grey,
                              ),
                            ),
                            subtitle: const Text(
                              'Blocked',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            trailing: OutlinedButton.icon(
                              onPressed: () async {
                                try {
                                  await p2pService.unblockContact(contact.peerID);
                                  if (context.mounted) {
                                    Navigator.pop(context, true); // Return true to indicate change
                                    showTopNotification(
                                      context,
                                      '${contact.displayName} unblocked',
                                    );
                                  }
                                } catch (e) {
                                  Logger.error('Error unblocking contact', e);
                                  if (context.mounted) {
                                    showTopNotification(
                                      context,
                                      'Failed to unblock contact: $e',
                                      isError: true,
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.check_circle_outline, size: 18),
                              label: const Text('Unblock'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green,
                                side: BorderSide(color: Colors.green.withOpacity(0.5)),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    
    // If a contact was changed, update the flag
    if (changed == true) {
      setState(() {
        _contactsChanged = true;
      });
    }
  }

  // ==================== APP LOCK ====================
  
  Widget _buildAppLockToggle() {
    final isEnabled = ref.watch(isAuthEnabledProvider);
    
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.lock),
          title: const Text('App Lock'),
          subtitle: Text(
            isEnabled 
                ? 'App is protected with PIN/Password'
                : 'Protect your app with PIN or Password',
            style: TextStyle(color: Colors.grey[600]),
          ),
          value: isEnabled,
          onChanged: (value) async {
            if (value) {
              // Aktivieren → Setup Screen zeigen
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SetupAuthWizard(),
                ),
              );
              // Refresh state
              await ref.read(authStateProviderProvider.notifier).refreshEnabled();
              setState(() {});
            } else {
              // Deaktivieren → Bestätigung
              await _confirmDisableAppLock();
            }
          },
        ),
        
        // Zusätzliche Optionen wenn aktiviert
        if (isEnabled) ...[
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Change PIN/Password'),
            subtitle: Text(
              'Update your app lock credentials',
              style: TextStyle(color: Colors.grey[600]),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SetupAuthWizard(isChangeMode: true),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
  
  Future<void> _confirmDisableAppLock() async {
    final authService = ref.read(authServiceProvider);
    
    // Schritt 1: Authentifizierung erforderlich
    final verified = await _verifyCurrentAuth();
    if (verified != true) return;
    
    // Schritt 2: Bestätigung nach erfolgreicher Authentifizierung
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable App Lock?'),
        content: const Text(
          'Your app will no longer require PIN/Password to unlock.\n\n'
          'You can enable it again anytime in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      final success = await authService.disableAuth();
      
      if (success) {
        await ref.read(authStateProviderProvider.notifier).refreshEnabled();
        if (mounted) {
          showTopNotification(
            context,
            'App Lock disabled',
          );
          setState(() {});
        }
      } else {
        if (mounted) {
          showTopNotification(
            context,
            'Failed to disable App Lock',
            isError: true,
          );
        }
      }
    }
  }
  
  /// Zeigt Dialog zur Verifizierung des aktuellen PIN/Passworts
  Future<bool?> _verifyCurrentAuth() async {
    final authService = ref.read(authServiceProvider);
    final authType = await authService.getAuthType();
    final isPin = authType == 'pin';
    final pinLength = isPin ? await authService.getPinLength() : null;
    
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _VerifyAuthDialog(
        isPin: isPin,
        pinLength: pinLength,
        onVerify: (input) async {
          final result = await authService.verifyAuth(input);
          return result.success;
        },
      ),
    );
  }
  
}

/// Dialog zur Verifizierung des aktuellen PIN/Passworts
class _VerifyAuthDialog extends StatefulWidget {
  final bool isPin;
  final int? pinLength;
  final Future<bool> Function(String) onVerify;

  const _VerifyAuthDialog({
    required this.isPin,
    required this.pinLength,
    required this.onVerify,
  });

  @override
  State<_VerifyAuthDialog> createState() => _VerifyAuthDialogState();
}

class _VerifyAuthDialogState extends State<_VerifyAuthDialog> {
  final _passwordController = TextEditingController();
  String _pinInput = '';
  String _errorMessage = '';
  bool _isVerifying = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleVerification(String input) async {
    if (_isVerifying) return;

    setState(() {
      _isVerifying = true;
      _errorMessage = '';
    });

    try {
      final success = await widget.onVerify(input);

      if (!mounted) return;

      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _errorMessage = 'Incorrect ${widget.isPin ? 'PIN' : 'password'}';
          _isVerifying = false;
          if (widget.isPin) {
            _pinInput = '';
          } else {
            _passwordController.clear();
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Verification failed';
        _isVerifying = false;
      });
    }
  }

  void _handlePinInput(String digit) {
    if (_pinInput.length < (widget.pinLength ?? 4)) {
      setState(() {
        _pinInput += digit;
      });

      // Auto-verify when complete
      if (_pinInput.length == (widget.pinLength ?? 4)) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && _pinInput.length == (widget.pinLength ?? 4)) {
            _handleVerification(_pinInput);
          }
        });
      }
    }
  }

  void _handleBackspace() {
    if (_pinInput.isNotEmpty) {
      setState(() {
        _pinInput = _pinInput.substring(0, _pinInput.length - 1);
        _errorMessage = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock,
                size: 32,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              'Verify ${widget.isPin ? 'PIN' : 'Password'}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              'Enter your current ${widget.isPin ? 'PIN' : 'password'} to continue',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // PIN or Password Input
            if (widget.isPin) ...[
              // PIN Dots
              PinInputDots(
                pinLength: _pinInput.length,
                maxLength: widget.pinLength ?? 4,
                filledColor: _errorMessage.isNotEmpty
                    ? Colors.red
                    : theme.colorScheme.primary,
                emptyColor: Colors.grey[300]!,
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 14,
                  ),
                ),
              ],
              const SizedBox(height: 24),

              // PIN Pad
              PinPadWidget(
                onNumberTap: _handlePinInput,
                onBackspaceTap: _handleBackspace,
                showCheckButton: false,
              ),
            ] else ...[
              // Password Field
              TextField(
                controller: _passwordController,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Enter password',
                  errorText: _errorMessage.isNotEmpty ? _errorMessage : null,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty) {
                    _handleVerification(value);
                  }
                },
              ),
              const SizedBox(height: 24),

              // Verify Button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isVerifying
                      ? null
                      : () {
                          if (_passwordController.text.isNotEmpty) {
                            _handleVerification(_passwordController.text);
                          }
                        },
                  child: _isVerifying
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify'),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Cancel Button
            TextButton(
              onPressed: _isVerifying
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
