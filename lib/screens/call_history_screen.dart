import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/call.dart';
import '../providers/services_provider.dart';
import '../utils/logger.dart';

/// Call History Screen - Displays all past calls
/// 
/// Features:
/// - List of all calls with contact names, timestamps, duration
/// - Group by date (Today, Yesterday, Earlier)
/// - Show call direction icon (incoming/outgoing), call state (missed/rejected/completed)
/// - Tap to view details
/// - Swipe to delete
class CallHistoryScreen extends ConsumerStatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  ConsumerState<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends ConsumerState<CallHistoryScreen> {
  List<Call> _calls = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCallHistory();
  }

  Future<void> _loadCallHistory() async {
    setState(() => _isLoading = true);
    
    final storage = ref.read(storageServiceProvider);
    final result = await storage.getAllCalls();
    
    if (result.isSuccess) {
      // Sort by timestamp descending (newest first)
      final calls = result.value;
      calls.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      setState(() {
        _calls = calls;
        _isLoading = false;
      });
      
      Logger.debug('📞 Loaded ${calls.length} calls from history');
    } else {
      Logger.error('❌ Failed to load call history: ${result.error}');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteCall(Call call) async {
    final storage = ref.read(storageServiceProvider);
    final result = await storage.deleteCall(call.id);
    
    if (result.isSuccess) {
      setState(() => _calls.removeWhere((c) => c.id == call.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Call deleted')),
        );
      }
    } else {
      Logger.error('❌ Failed to delete call: ${result.error}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete call: ${result.error}')),
        );
      }
    }
  }

  Future<void> _clearAllHistory() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Call History'),
        content: const Text('Are you sure you want to delete all call history? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      final storage = ref.read(storageServiceProvider);
      final result = await storage.clearCallHistory();
      
      if (result.isSuccess) {
        setState(() => _calls.clear());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Call history cleared')),
          );
        }
      } else {
        Logger.error('❌ Failed to clear call history: ${result.error}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to clear history: ${result.error}')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Call History'),
        actions: [
          if (_calls.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearAllHistory,
              tooltip: 'Clear all history',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _calls.isEmpty
              ? _buildEmptyState()
              : _buildCallList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.call_end,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No call history',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your past calls will appear here',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallList() {
    // Group calls by date
    final grouped = _groupCallsByDate(_calls);
    
    return ListView.builder(
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final group = grouped[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                group['label'] as String,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
            ),
            // Calls in this group
            ...((group['calls'] as List<Call>).map((call) => _buildCallTile(call))),
          ],
        );
      },
    );
  }

  Widget _buildCallTile(Call call) {
    // Get contact name (if exists)
    final contactName = _getContactName(call.contactId);
    
    // Call direction icon
    final directionIcon = call.direction.isIncoming
        ? Icons.call_received
        : Icons.call_made;
    
    // Call state icon color
    Color iconColor;
    switch (call.state) {
      case CallState.ended:
        iconColor = call.direction.isIncoming ? Colors.blue : Colors.green;
        break;
      case CallState.rejected:
        iconColor = Colors.red;
        break;
      case CallState.failed:
        iconColor = Colors.orange;
        break;
      default:
        iconColor = Colors.grey;
    }
    
    // Format duration
    final durationText = call.duration != null
        ? _formatDuration(call.duration!)
        : call.state == CallState.rejected
            ? 'Rejected'
            : call.state == CallState.failed
                ? 'Failed'
                : 'No duration';
    
    // Format time
    final timeText = DateFormat.Hm().format(call.timestamp);
    
    return Dismissible(
      key: Key(call.id),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _deleteCall(call),
      child: ListTile(
        leading: Icon(directionIcon, color: iconColor),
        title: Text(
          contactName ?? call.contactId,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(durationText),
        trailing: Text(
          timeText,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        onTap: () => _showCallDetails(call),
      ),
    );
  }

  String? _getContactName(String contactId) {
    // TODO: Get contact name from contacts provider
    // For now, just return null (will display contactId)
    return null;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  List<Map<String, dynamic>> _groupCallsByDate(List<Call> calls) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final lastWeek = today.subtract(const Duration(days: 7));
    
    final todayCalls = <Call>[];
    final yesterdayCalls = <Call>[];
    final thisWeekCalls = <Call>[];
    final earlierCalls = <Call>[];
    
    for (final call in calls) {
      final callDate = DateTime(
        call.timestamp.year,
        call.timestamp.month,
        call.timestamp.day,
      );
      
      if (callDate == today) {
        todayCalls.add(call);
      } else if (callDate == yesterday) {
        yesterdayCalls.add(call);
      } else if (callDate.isAfter(lastWeek)) {
        thisWeekCalls.add(call);
      } else {
        earlierCalls.add(call);
      }
    }
    
    final groups = <Map<String, dynamic>>[];
    
    if (todayCalls.isNotEmpty) {
      groups.add({'label': 'Today', 'calls': todayCalls});
    }
    if (yesterdayCalls.isNotEmpty) {
      groups.add({'label': 'Yesterday', 'calls': yesterdayCalls});
    }
    if (thisWeekCalls.isNotEmpty) {
      groups.add({'label': 'This Week', 'calls': thisWeekCalls});
    }
    if (earlierCalls.isNotEmpty) {
      groups.add({'label': 'Earlier', 'calls': earlierCalls});
    }
    
    return groups;
  }

  void _showCallDetails(Call call) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Call Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Contact', call.contactId),
            _buildDetailRow('Direction', call.direction.isIncoming ? 'Incoming' : 'Outgoing'),
            _buildDetailRow('State', call.state.toString().split('.').last),
            _buildDetailRow('Time', DateFormat('MMM d, y HH:mm').format(call.timestamp)),
            if (call.duration != null)
              _buildDetailRow('Duration', _formatDuration(call.duration!)),
            _buildDetailRow('Call ID', call.id),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
        ],
      ),
    );
  }
}
