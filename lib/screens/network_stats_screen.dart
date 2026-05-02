import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/message.dart';
import '../providers/services_provider.dart';
import '../utils/top_notification.dart';
import '../utils/logger.dart';

/// Network Statistics Screen
/// 
/// Displays real-time network status and message delivery metrics:
/// - Active node connection details
/// - Available fallback nodes
/// - Message queue status (pending/failed)
/// - Delivery rate and total messages sent
class NetworkStatsScreen extends ConsumerStatefulWidget {
  const NetworkStatsScreen({super.key});

  @override
  ConsumerState<NetworkStatsScreen> createState() => _NetworkStatsScreenState();
}

class _NetworkStatsScreenState extends ConsumerState<NetworkStatsScreen> {
  bool _isLoading = true;
  Timer? _autoRefreshTimer;
  bool _autoRefreshEnabled = true;
  
  // Stats
  String? _activeNodePeerID;
  String? _activeNodeName;
  bool _isMyOwnNode = false;
  int _availableNodesCount = 0;
  int _myNodesCount = 0;
  int _discoveredNodesCount = 0;
  int _blacklistedNodesCount = 0;
  bool _isPublicNetwork = true;
  String _networkMode = 'Public Network';
  DateTime? _connectionStartTime;
  Duration? _connectionUptime;
  int _pendingMessagesCount = 0;
  int _failedMessagesCount = 0;
  int _sentMessagesCount = 0;
  int _deliveredMessagesCount = 0;
  int _totalMessagesCount = 0;
  double _deliveryRate = 0.0;
  List<Map<String, dynamic>> _availableNodesList = [];
  bool _showAllNodes = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    if (_autoRefreshEnabled) {
      _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        if (mounted) {
          _loadStats();
        }
      });
    }
  }

  void _toggleAutoRefresh() {
    setState(() {
      _autoRefreshEnabled = !_autoRefreshEnabled;
      if (_autoRefreshEnabled) {
        _startAutoRefresh();
        showTopNotification(
          context,
          'Auto-refresh enabled - Updates every 15 seconds',
        );
      } else {
        _autoRefreshTimer?.cancel();
        showTopNotification(
          context,
          'Auto-refresh paused - Pull down to refresh manually',
        );
      }
    });
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final p2pService = ref.read(p2pServiceProvider);
      final myNodesService = ref.read(myNodesServiceProvider);
      final bootstrapNodesService = ref.read(bootstrapNodesServiceProvider);
      final networkService = ref.read(networkServiceProvider);
      
      // Get network mode
      _isPublicNetwork = networkService.isPublicNetwork;
      _networkMode = _isPublicNetwork ? 'Public Network' : networkService.activeNetworkId;
      
      // Get node counts
      _myNodesCount = myNodesService.nodes.length;
      _discoveredNodesCount = bootstrapNodesService.nodes.length;
      final blacklistedNodes = await bootstrapNodesService.getBlacklistedNodesWithTTL();
      _blacklistedNodesCount = blacklistedNodes.length;
      
      // Get active node info
      _activeNodePeerID = p2pService.activeBootstrapNode;
      _availableNodesCount = p2pService.availableBootstrapNodes.length;
      
      // Build available nodes list with details
      _availableNodesList.clear();
      for (final nodeAddr in p2pService.availableBootstrapNodes) {
        final peerID = _extractPeerID(nodeAddr);
        bool isMyNode = false;
        String? nodeName;
        
        for (final myNode in myNodesService.nodes) {
          if (_extractPeerID(myNode.multiaddr) == peerID) {
            isMyNode = true;
            nodeName = myNode.name;
            break;
          }
        }
        
        _availableNodesList.add({
          'peerID': peerID,
          'multiaddr': nodeAddr,
          'name': nodeName ?? (isMyNode ? 'My Node' : 'Discovered Node'),
          'isMyNode': isMyNode,
          'isActive': nodeAddr == _activeNodePeerID,
        });
      }
      
      // Check if active node is user's own node
      if (_activeNodePeerID != null) {
        final peerID = _extractPeerID(_activeNodePeerID!);
        for (final myNode in myNodesService.nodes) {
          if (_extractPeerID(myNode.multiaddr) == peerID) {
            _isMyOwnNode = true;
            _activeNodeName = myNode.name;
            if (_connectionStartTime == null) {
              _connectionStartTime = DateTime.now();
            }
            break;
          }
        }
      } else {
        _connectionStartTime = null;
      }
      
      // Calculate uptime
      if (_connectionStartTime != null) {
        _connectionUptime = DateTime.now().difference(_connectionStartTime!);
      } else {
        _connectionUptime = null;
      }
      
      // Get message stats
      final allMessagesResult = await p2pService.storage.getAllMessages();
      if (allMessagesResult.isSuccess) {
        final allMessages = allMessagesResult.valueOrNull ?? [];
        final myPeerID = ref.read(currentPeerIDProvider).valueOrNull;
        
        // Only count outgoing messages (where we are the sender)
        final outgoingMessages = allMessages.where((msg) => msg.senderPeerID == myPeerID).toList();
        
        _totalMessagesCount = outgoingMessages.length;
        _pendingMessagesCount = outgoingMessages.where((msg) => msg.deliveryStatus == DeliveryStatus.pending).length;
        _failedMessagesCount = outgoingMessages.where((msg) => msg.deliveryStatus == DeliveryStatus.failed).length;
        _sentMessagesCount = outgoingMessages.where((msg) => msg.deliveryStatus == DeliveryStatus.sent).length;
        _deliveredMessagesCount = outgoingMessages.where((msg) => msg.deliveryStatus == DeliveryStatus.delivered).length;
        
        final successCount = _sentMessagesCount + _deliveredMessagesCount;
        
        // Calculate delivery rate
        if (_totalMessagesCount > 0) {
          _deliveryRate = (successCount / _totalMessagesCount) * 100;
        }
      }
      
    } catch (e) {
      Logger.warning('Error loading network stats: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _extractPeerID(String multiaddr) {
    final parts = multiaddr.split('/p2p/');
    return parts.length > 1 ? parts.last : '';
  }

  String _formatPeerID(String peerID) {
    if (peerID.length <= 20) return peerID;
    return '${peerID.substring(0, 12)}...${peerID.substring(peerID.length - 8)}';
  }

  String _formatUptime(Duration uptime) {
    final hours = uptime.inHours;
    final minutes = uptime.inMinutes.remainder(60);
    final seconds = uptime.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Statistics'),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_autoRefreshEnabled ? Icons.pause_circle : Icons.play_circle),
            onPressed: _toggleAutoRefresh,
            tooltip: _autoRefreshEnabled ? 'Auto-Refresh: ON (15s)' : 'Auto-Refresh: OFF',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Connection Status Card
                  _buildStatusCard(context),
                  const SizedBox(height: 16),
                  
                  // Network Info Card
                  _buildNetworkInfoCard(context),
                  const SizedBox(height: 16),
                  
                  // Available Nodes Card
                  _buildAvailableNodesCard(context),
                  const SizedBox(height: 16),
                  
                  // Message Queue Card
                  _buildMessageQueueCard(context),
                  const SizedBox(height: 16),
                  
                  // Delivery Stats Card
                  _buildDeliveryStatsCard(context),
                  const SizedBox(height: 16),
                  
                  // Actions Card
                  _buildActionsCard(context),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isConnected = _activeNodePeerID != null;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConnected ? Icons.check_circle : Icons.error,
                  color: isConnected ? Colors.green : Colors.red,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Connection Status',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const Divider(height: 24),
            
            if (isConnected) ...[
              _buildStatRow(
                icon: Icons.dns,
                label: 'Active Node',
                value: _activeNodeName ?? 'Bootstrap Node',
                valueColor: _isMyOwnNode ? Colors.green : Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildStatRow(
                icon: Icons.fingerprint,
                label: 'Peer ID',
                value: _formatPeerID(_extractPeerID(_activeNodePeerID!)),
                isMonospace: true,
                showCopyIcon: true,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _extractPeerID(_activeNodePeerID!)));
                  showTopNotification(
                    context,
                    'Peer ID copied!',
                  );
                },
              ),
              const SizedBox(height: 12),
              if (_connectionUptime != null)
                _buildStatRow(
                  icon: Icons.timer,
                  label: 'Connection Uptime',
                  value: _formatUptime(_connectionUptime!),
                  valueColor: Colors.green,
                ),
            ] else ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.cloud_off,
                        size: 64,
                        color: colorScheme.error.withOpacity(0.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No Node Connected',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add nodes in Settings to connect',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            
            if (_connectionUptime != null) const Divider(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageQueueCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasPendingOrFailed = _pendingMessagesCount > 0 || _failedMessagesCount > 0;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.queue,
                  color: colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Message Queue',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const Divider(height: 24),
            
            _buildStatRow(
              icon: Icons.schedule,
              label: 'Pending',
              value: '$_pendingMessagesCount message${_pendingMessagesCount != 1 ? 's' : ''}',
              valueColor: _pendingMessagesCount > 0 ? Colors.orange : Colors.grey,
            ),
            const SizedBox(height: 12),
            _buildStatRow(
              icon: Icons.warning,
              label: 'Failed',
              value: '$_failedMessagesCount message${_failedMessagesCount != 1 ? 's' : ''}',
              valueColor: _failedMessagesCount > 0 ? Colors.red : Colors.grey,
            ),
            
            if (hasPendingOrFailed) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _retryFailedMessages(context),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry Pending Messages'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryStatsCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics,
                  color: colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Delivery Statistics',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const Divider(height: 24),
            
            _buildStatRow(
              icon: Icons.check_circle,
              label: 'Delivered',
              value: '$_deliveredMessagesCount message${_deliveredMessagesCount != 1 ? 's' : ''}',
              valueColor: Colors.green,
            ),
            const SizedBox(height: 12),
            _buildStatRow(
              icon: Icons.send,
              label: 'Sent (Not Confirmed)',
              value: '$_sentMessagesCount message${_sentMessagesCount != 1 ? 's' : ''}',
              valueColor: Colors.blue,
            ),
            const SizedBox(height: 12),
            _buildStatRow(
              icon: Icons.message,
              label: 'Total Messages',
              value: '$_totalMessagesCount message${_totalMessagesCount != 1 ? 's' : ''}',
            ),
            const SizedBox(height: 12),
            
            // Delivery Rate with Progress Bar
            Row(
              children: [
                Icon(
                  _getDeliveryRateIcon(_deliveryRate),
                  size: 24,
                  color: _getDeliveryRateColor(_deliveryRate),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Delivery Rate',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            '${_deliveryRate.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _getDeliveryRateColor(_deliveryRate),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _deliveryRate / 100,
                          minHeight: 8,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getDeliveryRateColor(_deliveryRate),
                          ),
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
    );
  }

  Widget _buildActionsCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.settings,
                  color: colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Actions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const Divider(height: 24),
            
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Force Reconnect'),
              subtitle: Text(
                'Disconnect and reconnect to node',
                style: TextStyle(color: Colors.grey[600]),
              ),
              onTap: () => _forceReconnect(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    bool isMonospace = false,
    VoidCallback? onTap,
    bool showCopyIcon = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? colorScheme.onSurface,
                  fontFamily: isMonospace ? 'monospace' : null,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(
                showCopyIcon ? Icons.copy : Icons.chevron_right,
                size: 16,
                color: colorScheme.onSurface.withOpacity(0.4),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getDeliveryRateColor(double rate) {
    if (rate >= 90) return Colors.green;
    if (rate >= 70) return Colors.orange;
    return Colors.red;
  }

  IconData _getDeliveryRateIcon(double rate) {
    if (rate >= 90) return Icons.check_circle;
    if (rate >= 70) return Icons.warning;
    return Icons.error;
  }

  Future<void> _retryFailedMessages(BuildContext context) async {
    try {
      showTopNotification(
        context,
        'Retrying pending messages...',
      );
      
      final p2pService = ref.read(p2pServiceProvider);
      await p2pService.retryPendingMessages();
      
      // Reload stats
      await _loadStats();
      
      if (mounted) {
        showTopNotification(
          context,
          'Retry complete! Check message status.',
        );
      }
    } catch (e) {
      if (mounted) {
        showTopNotification(
          context,
          'Retry failed: $e',
          isError: true,
        );
      }
    }
  }

  Future<void> _forceReconnect(BuildContext context) async {
    try {
      showTopNotification(
        context,
        'Reconnecting...',
      );
      
      final p2pService = ref.read(p2pServiceProvider);
      
      // Disconnect (will trigger automatic reconnect)
      await p2pService.reinitialize();
      
      // Reload stats after reconnect attempt
      await Future.delayed(const Duration(seconds: 2));
      await _loadStats();
      
      if (mounted) {
        showTopNotification(
          context,
          'Reconnected!',
        );
      }
    } catch (e) {
      if (mounted) {
        showTopNotification(
          context,
          'Reconnect failed: $e',
          isError: true,
        );
      }
    }
  }

  Widget _buildNetworkInfoCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.public,
                  color: colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'Network Overview',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const Divider(height: 24),
            
            _buildStatRow(
              icon: _isPublicNetwork ? Icons.public : Icons.vpn_lock,
              label: 'Network Mode',
              value: _networkMode,
              valueColor: _isPublicNetwork ? Colors.blue : Colors.purple,
            ),
            const SizedBox(height: 12),
            _buildStatRow(
              icon: Icons.storage,
              label: 'My Private Networks',
              value: '$_myNodesCount',
              valueColor: Colors.green,
            ),
            const SizedBox(height: 12),
            _buildStatRow(
              icon: Icons.cloud_download,
              label: 'Discovered Nodes',
              value: '$_discoveredNodesCount node${_discoveredNodesCount != 1 ? 's' : ''}',
              valueColor: Colors.blue,
            ),
            const SizedBox(height: 12),
            _buildStatRow(
              icon: Icons.block,
              label: 'Blacklisted Nodes',
              value: '$_blacklistedNodesCount node${_blacklistedNodesCount != 1 ? 's' : ''}',
              valueColor: _blacklistedNodesCount > 0 ? Colors.red : Colors.grey,
              onTap: () => _showBlacklistedNodes(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailableNodesCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_queue,
                  color: colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Available Nodes',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  '$_availableNodesCount',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_availableNodesList.length > 3)
                  IconButton(
                    icon: Icon(_showAllNodes ? Icons.expand_less : Icons.expand_more),
                    onPressed: () => setState(() => _showAllNodes = !_showAllNodes),
                  ),
              ],
            ),
            const Divider(height: 24),
            
            if (_availableNodesList.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        Icons.cloud_off,
                        size: 48,
                        color: colorScheme.error.withOpacity(0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No nodes available',
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...(_showAllNodes ? _availableNodesList : _availableNodesList.take(3)).map((node) {
                final isActive = node['isActive'] as bool;
                final isMyNode = node['isMyNode'] as bool;
                final name = node['name'] as String;
                final peerID = node['peerID'] as String;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isActive 
                        ? colorScheme.primaryContainer.withOpacity(0.3)
                        : colorScheme.surfaceContainerHighest.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: isActive ? Border.all(
                        color: colorScheme.primary,
                        width: 2,
                      ) : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isActive)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withOpacity(0.5),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            Icon(
                              isMyNode ? Icons.dns : Icons.cloud,
                              size: 18,
                              color: isMyNode ? Colors.green : Colors.blue,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                name,
                                style: TextStyle(
                                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: peerID));
                            showTopNotification(context, 'Peer ID copied!');
                          },
                          child: Row(
                            children: [
                              const SizedBox(width: 26),
                              Expanded(
                                child: Text(
                                  _formatPeerID(peerID),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.copy,
                                size: 14,
                                color: Colors.grey[400],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            
            if (!_showAllNodes && _availableNodesList.length > 3)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _showAllNodes = true),
                  child: Text('Show ${_availableNodesList.length - 3} more...'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBlacklistedNodes(BuildContext context) async {
    final bootstrapNodesService = ref.read(bootstrapNodesServiceProvider);
    final blacklistedNodes = bootstrapNodesService.getBlacklistedNodesWithTTL();
    
    if (!mounted) return;
    
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
                          SizedBox(height: 4),
                          Text(
                            'Temporarily blocked unreachable nodes',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
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
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.red.shade100,
                                child: const Icon(
                                  Icons.block,
                                  color: Colors.red,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                displayPeerID,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                              subtitle: Text(
                                'Expires in ${remainingHours}h • Blocked ${ageHours}h ago',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 11,
                                ),
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
  }
}
