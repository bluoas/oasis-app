import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/services_provider.dart';
import '../widgets/loading_state.dart';
import '../utils/top_notification.dart';
import '../utils/logger.dart';

/// QR Scanner Screen for adding user's own Oasis Nodes
/// 
/// Scans QR codes containing node information in JSON format:
/// Compact format (current):
/// {
///   "t": "oasis_node",
///   "p": "12D3KooW...",
///   "m": "/ip4/192.168.1.100/tcp/4001/p2p/12D3KooW...",
///   "n": "My Home Server" // optional
/// }
/// 
/// Legacy format (also supported):
/// {
///   "type": "oasis_node",
///   "peer_id": "12D3KooW...",
///   "multiaddr": "/ip4/192.168.1.100/tcp/4001/p2p/12D3KooW...",
///   "name": "My Home Server" // optional
/// }
class AddMyNodeScreen extends ConsumerStatefulWidget {
  const AddMyNodeScreen({super.key});

  @override
  ConsumerState<AddMyNodeScreen> createState() => _AddMyNodeScreenState();
}

class _AddMyNodeScreenState extends ConsumerState<AddMyNodeScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;
  bool _scanCompleted = false;
  bool _isTorchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleTorch() async {
    await _controller.toggleTorch();
    setState(() {
      _isTorchOn = !_isTorchOn;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Node QR Code'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: _toggleTorch,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Scanner view
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (!_scanCompleted && !_isProcessing) {
                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  if (barcode.rawValue != null) {
                    _handleScannedCode(barcode.rawValue!);
                    break;
                  }
                }
              }
            },
          ),
          
          // Scan guide overlay
          if (!_scanCompleted)
            _buildScanGuide(),
          
          // Processing indicator
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: LoadingState(
                  message: 'Adding node...',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScanGuide() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
      ),
      child: Column(
        children: [
          const Spacer(),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).primaryColor,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                Icon(Icons.qr_code_scanner, size: 48),
                SizedBox(height: 12),
                Text(
                  'Scan Node QR Code',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Position the QR code from your Oasis Node within the frame',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Future<void> _handleScannedCode(String code) async {
    setState(() {
      _isProcessing = true;
      _scanCompleted = true;
    });

    try {
      // Try to parse as JSON
      final Map<String, dynamic> data = jsonDecode(code);
      
      // Support both compact ("t") and full ("type") keys for backwards compatibility
      final type = data['t'] ?? data['type'];
      if (type != 'oasis_node') {
        throw Exception('Invalid QR code type. Expected "oasis_node".');
      }
      
      // Support both compact ("m") and full ("multiaddr") keys
      final multiaddr = (data['m'] ?? data['multiaddr']) as String?;
      if (multiaddr == null || multiaddr.isEmpty) {
        throw Exception('Missing multiaddr in QR code');
      }
      
      // Support both compact ("n") and full ("name") keys
      final qrName = (data['n'] ?? data['name']) as String?;
      
      // Extract PeerID from multiaddr for default naming
      final peerIDMatch = RegExp(r'/p2p/([^/]+)').firstMatch(multiaddr);
      final peerID = peerIDMatch?.group(1);
      final nodeName = qrName ?? (peerID != null ? 'Node ${peerID.substring(0, 8)}' : 'My Oasis Node');
      
      Logger.info('Adding node to My Nodes (validation will occur on next app start)...');
      
      // Add node directly (P2PService may not be initialized during onboarding)
      final myNodesService = ref.read(myNodesServiceProvider);
      final result = await myNodesService.addNode(
        multiaddr: multiaddr,
        name: nodeName,
      );
      
      if (result.isFailure) {
        throw Exception(result.errorOrNull?.userMessage ?? 'Failed to add node');
      }
      
      Logger.success('Node added successfully! App will connect on next initialization.');
      
      // Success
      if (mounted) {
        Navigator.pop(context, true); // Return success
        
        showTopNotification(
          context,
          '$nodeName added! App will connect on restart.',
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      Logger.error('Error during node validation', e);
      
      if (mounted) {
        // Reset scanner
        setState(() {
          _isProcessing = false;
          _scanCompleted = false;
        });
        
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Invalid QR Code'),
            content: Text(
              'Could not parse node information.\n\n'
              'Error: $e\n\n'
              'Please scan a valid Oasis Node QR code.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Try Again'),
              ),
            ],
          ),
        );
      }
    }
  }
}
