import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/services_provider.dart';
import '../services/p2p_service.dart';
import '../models/contact.dart';
import '../widgets/loading_state.dart';
import '../utils/top_notification.dart';
import '../utils/logger.dart';

/// Screen für Contact hinzufügen via QR-Code Scan
/// 
/// Scannt QR-Codes mit Contact-Information im JSON-Format:
/// {
///   "type": "oasis_contact",
///   "peer_id": "12D3KooW...",
///   "name": "Alice",
///   "node": "/ip4/.../tcp/4001/p2p/..."
/// }
class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;
  bool _scanCompleted = false;
  bool _isTorchOn = false;

  // Getter for service from Riverpod provider
  P2PService get _p2pService => ref.read(p2pServiceProvider);

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

  Future<void> _pasteFromClipboard() async {
    try {
      // Read clipboard
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text?.trim();
      
      if (text == null || text.isEmpty) {
        if (mounted) {
          showTopNotification(
            context,
            'Clipboard is empty',
            isError: true,
          );
        }
        return;
      }
      
      String decodedJson;
      
      // Detect format and decode
      if (text.startsWith('{')) {
        // Direct JSON (legacy support)
        decodedJson = text;
        Logger.debug('Direct JSON detected');
      } else if (text.startsWith('oasis://add?c=')) {
        // Deep link format (legacy)
        try {
          final base64Part = text.substring('oasis://add?c='.length);
          final decodedBytes = base64Decode(base64Part);
          decodedJson = utf8.decode(decodedBytes);
          Logger.debug('Deep link detected and decoded');
        } catch (e) {
          throw Exception('Invalid deep link format: $e');
        }
      } else {
        // Assume it's Base64 encoded (new default format)
        try {
          final decodedBytes = base64Decode(text);
          decodedJson = utf8.decode(decodedBytes);
          Logger.debug('Base64 contact code decoded');
        } catch (e) {
          throw Exception('Invalid contact code format. Please copy the code from "Share Contact Code" button.');
        }
      }
      
      // Parse and add contact
      await _handleScannedCode(decodedJson);
      
    } catch (e) {
      Logger.error('Error pasting from clipboard', e);
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Invalid Contact Code'),
            content: Text(
              'Could not parse contact code from clipboard.\n\n'
              'Error: $e\n\n'
              'Please make sure you copied the contact code using the "Share Contact Code" button.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Contact'),
        centerTitle: true,
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
                  message: 'Adding contact...',
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
                  'Scan Contact QR Code',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Position your contact\'s QR code within the frame',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          // Paste Link Button (prominent)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            child: GestureDetector(
              onTap: _pasteFromClipboard,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.content_paste,
                      color: Theme.of(context).colorScheme.onPrimary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Paste Contact Code',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
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
      
      // Support both compact ("t") and full ("type") keys
      final type = data['t'] ?? data['type'];
      if (type != 'oasis_contact') {
        throw Exception('Invalid QR code type. Expected "oasis_contact".');
      }
      
      // Support both compact ("p") and full ("peer_id") keys
      final peerID = (data['p'] ?? data['peer_id']) as String?;
      if (peerID == null || peerID.isEmpty) {
        throw Exception('Missing peer_id in QR code');
      }
      
      // Support both compact ("n") and full ("name") keys
      final name = (data['n'] ?? data['name']) as String? ?? 'User ${peerID.substring(peerID.length - 8)}';
      
      // Support both compact ("m") and full ("node") keys for connected node
      final nodeMultiaddr = (data['m'] ?? data['node']) as String?;
      
      Logger.info('Contact scanned: $name ($peerID)');
      if (nodeMultiaddr != null) {
        Logger.info('   Connected to node: ${nodeMultiaddr.split('/').last}');
      }
      
      // Save contact directly via StorageService (works during onboarding)
      // Initialize storage if not already done
      final storageService = ref.read(storageServiceProvider);
      final storageInitResult = await storageService.initialize();
      if (storageInitResult.isFailure) {
        throw Exception('Failed to initialize storage: ${storageInitResult.errorOrNull?.userMessage}');
      }
      
      // Check if contact already exists
      final existingContactResult = await storageService.getContact(peerID);
      if (existingContactResult.isSuccess && existingContactResult.valueOrNull != null) {
        Logger.info('Contact already exists: $name ($peerID)');
        
        if (mounted) {
          Navigator.pop(context); // Close scanner
          
          showTopNotification(
            context,
            '$name is already in your contacts!',
            duration: const Duration(seconds: 3),
          );
        }
        return;
      }
      
      // Create and save contact
      final contact = Contact(
        peerID: peerID,
        displayName: name,  // Use provided name as initial display name
        userName: name,      // And as user name
        addedAt: DateTime.now(),
        connectedNodeMultiaddr: nodeMultiaddr,
        networkId: ref.read(networkServiceProvider).activeNetworkId, // Network separation
      );
      
      final saveResult = await storageService.saveContact(contact);
      if (saveResult.isFailure) {
        throw Exception('Failed to save contact: ${saveResult.errorOrNull?.userMessage}');
      }
      
      Logger.success('Contact saved to storage!');
      
      // CRITICAL FIX: Send key exchange if P2PService is already initialized
      // This ensures contacts added AFTER onboarding can communicate immediately
      var keyExchangeSent = false;
      try {
        await _p2pService.sendKeyExchangeRequest(peerID);
        Logger.success('Key exchange request sent to new contact!');
        keyExchangeSent = true;
      } catch (e) {
        // P2PService not initialized yet (during onboarding)
        // Key exchange will be sent automatically when P2PService initializes
        Logger.info('Key exchange deferred (P2P not ready): $e');
      }
      
      // CRITICAL: Register friend's node as bootstrap (for fully decentralized onboarding)
      // This allows users WITHOUT their own node to connect via friend's node
      if (nodeMultiaddr != null && nodeMultiaddr.isNotEmpty) {
        Logger.debug('Registering friend\'s node as bootstrap...');
        final bootstrapService = ref.read(bootstrapNodesServiceProvider);
        
        // Extract PeerID from multiaddr for naming
        final peerIDMatch = RegExp(r'/p2p/([^/]+)').firstMatch(nodeMultiaddr);
        final nodePeerID = peerIDMatch?.group(1) ?? 'unknown';
        final shortPeerID = nodePeerID.length > 8 ? nodePeerID.substring(0, 8) : nodePeerID;
        
        // Add friend's node as bootstrap node
        final addNodeResult = await bootstrapService.addNode(
          multiaddr: nodeMultiaddr,
          name: '$name\'s Node ($shortPeerID)',
        );
        
        if (addNodeResult.isSuccess) {
          Logger.success('Friend\'s node registered as bootstrap!');
          
          // Only switch if this is a different node than currently active
          final alreadyConnected = _p2pService.activeBootstrapNode == nodeMultiaddr;
          if (alreadyConnected) {
            Logger.info('Already connected to friend\'s node - skipping switch');
          } else {
            try {
              final connectSuccess = await _p2pService.switchToBootstrapNode(nodeMultiaddr);
              if (connectSuccess) {
                Logger.success('Connected to friend\'s node!');
              }
            } catch (e) {
              Logger.info('P2P switch skipped (will retry on app initialization): $e');
              // Not a fatal error - will be attempted again on next app start
            }
          }
        } else {
          Logger.info('Node already registered (${addNodeResult.errorOrNull?.userMessage})');
        }
      }
      
      // Success
      if (mounted) {
        Navigator.pop(context, true); // Return success
        
        final keyMessage = keyExchangeSent
          ? ' Key exchange sent!'
          : '';
        
        showTopNotification(
          context,
          '$name added!$keyMessage',
          duration: const Duration(seconds: 3),
        );
      }
      
      // Note: If key exchange wasn't sent (during onboarding), it will be 
      // automatically sent when P2PService initializes via _sendPendingKeyExchanges()
      
    } catch (e) {
      Logger.error('Error during contact scan', e);
      
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
              'Could not parse contact information.\n\n'
              'Error: $e\n\n'
              'Please scan a valid Oasis Contact QR code.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }
}
