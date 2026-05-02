import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/services_provider.dart';

/// Node Status Indicator Widget
/// 
/// Shows current active node connection status in the app bar
/// - Green: Connected to own node
/// - Blue: Connected to friend's/bootstrap node  
/// - Red: No connection
class NodeStatusIndicator extends ConsumerWidget {
  const NodeStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p2pService = ref.watch(p2pServiceProvider);
    final myNodesService = ref.watch(myNodesServiceProvider);
    
    // Get node information
    final nodeInfo = p2pService.getNodeInfo();
    final activeBootstrapNode = nodeInfo['active_bootstrap_node'] as String?;
    
    // Determine node type and status
    final bool isConnected = activeBootstrapNode != null;
    final bool isOwnNode = isConnected && 
        myNodesService.nodes.any((node) => activeBootstrapNode.contains(node.peerID));
    
    // Extract node name if available
    String nodeName = 'Unknown';
    if (isConnected) {
      if (isOwnNode && myNodesService.nodes.isNotEmpty) {
        // Find the node name from My Nodes
        final myNode = myNodesService.nodes.firstWhere(
          (node) => activeBootstrapNode.contains(node.peerID),
          orElse: () => myNodesService.nodes.first,
        );
        nodeName = myNode.name;
      } else {
        // Extract short PeerID for bootstrap nodes
        final peerID = _extractPeerID(activeBootstrapNode);
        nodeName = 'Bootstrap (${peerID.substring(0, 8)}...)';
      }
    }
    
    // Choose color based on status
    final Color statusColor;
    final IconData statusIcon;
    if (!isConnected) {
      statusColor = Colors.red;
      statusIcon = Icons.cloud_off;
    } else if (isOwnNode) {
      statusColor = Colors.green;
      statusIcon = Icons.router;
    } else {
      statusColor = Colors.blue;
      statusIcon = Icons.cloud;
    }
    
    return InkWell(
      onTap: () => _showNodeDetails(context, nodeInfo, isOwnNode, nodeName),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: statusColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              statusIcon,
              size: 16,
              color: statusColor,
            ),
            const SizedBox(width: 6),
            Text(
              isConnected ? (isOwnNode ? 'My Node' : 'Bootstrap') : 'Offline',
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _showNodeDetails(
    BuildContext context,
    Map<String, dynamic> nodeInfo,
    bool isOwnNode,
    String nodeName,
  ) {
    final activeBootstrapNode = nodeInfo['active_bootstrap_node'] as String?;
    final availableNodes = nodeInfo['available_bootstrap_nodes'] as List<dynamic>;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isOwnNode ? Icons.router : Icons.cloud,
              color: isOwnNode ? Colors.green : Colors.blue,
            ),
            const SizedBox(width: 8),
            const Text('Node Status'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Active Node
              const Text(
                'Active Connection:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              if (activeBootstrapNode != null) ...[
                Text(
                  nodeName,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  isOwnNode ? 'Your own Oasis Node' : 'Bootstrap/Friend Node',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _extractPeerID(activeBootstrapNode),
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ] else ...[
                const Text(
                  'No connection',
                  style: TextStyle(color: Colors.red),
                ),
              ],
              
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              
              // Available Nodes
              Text(
                'Available Nodes: ${availableNodes.length}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${availableNodes.length} node(s) configured for messaging and store-and-forward',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
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
  
  String _extractPeerID(String multiaddr) {
    final parts = multiaddr.split('/');
    final p2pIndex = parts.indexWhere((p) => p == 'p2p');
    if (p2pIndex != -1 && p2pIndex + 1 < parts.length) {
      return parts[p2pIndex + 1];
    }
    return 'Unknown';
  }
}
