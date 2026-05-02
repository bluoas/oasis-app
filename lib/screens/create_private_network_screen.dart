import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/services_provider.dart';
import '../services/p2p_service.dart';
import '../services/private_network_setup_service.dart';
import '../utils/top_notification.dart';
import '../utils/logger.dart';

/// Screen for creating a new private network by scanning an Oasis Node
/// running in PSK mode.
///
/// Expected QR code format from Oasis Node (PSK mode):
/// {
///   "type": "oasis_node_psk",
///   "peer_id": "12D3KooW...",
///   "multiaddr": "/ip4/.../tcp/.../p2p/...",
///   "psk": "<hex or base64 psk>",
///   "name": "My Node"  // optional
/// }
class CreatePrivateNetworkScreen extends ConsumerStatefulWidget {
  const CreatePrivateNetworkScreen({super.key});

  @override
  ConsumerState<CreatePrivateNetworkScreen> createState() =>
      _CreatePrivateNetworkScreenState();
}

class _CreatePrivateNetworkScreenState
    extends ConsumerState<CreatePrivateNetworkScreen> {
  final _nameController = TextEditingController();
  final _scannerController = MobileScannerController();
  final _nameFocusNode = FocusNode();

  String? _scannedPeerId;
  String? _scannedMultiaddr;
  String? _scannedPsk;
  String? _scannedNodeName;
  bool _isCreating = false;
  bool _scannerActive = true;
  bool _hasName = false;
  bool _networkCreated = false; // Track if network was successfully created
  
  // Cache P2PService reference to avoid using ref in dispose()
  late final P2PService _p2pService;

  @override
  void initState() {
    super.initState();
    
    // Cache service reference before widget can be disposed
    _p2pService = ref.read(p2pServiceProvider);
    
    // Pause message polling while scanning to avoid timeout errors
    // from unreachable nodes blocking the scanner experience
    _p2pService.pausePolling();
    
    _nameController.addListener(() {
      final valid = _nameController.text.trim().isNotEmpty;
      if (valid != _hasName) {
        setState(() => _hasName = valid);
      }
    });
  }

  @override
  void dispose() {
    // Resume polling if user exits without creating network
    // (if network was created, reinitialize() already restarted polling)
    if (!_networkCreated) {
      _p2pService.startPolling();
    }
    
    _nameController.dispose();
    _scannerController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (!_scannerActive) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;
    _processQRCode(barcode!.rawValue!);
  }

  void _processQRCode(String code) {
    try {
      final data = jsonDecode(code) as Map<String, dynamic>;
      final type = (data['t'] ?? data['type']) as String?;

      if (type != 'oasis_node' && type != 'oasis_node_psk') {
        Logger.warning('QR type "$type" is not a valid Oasis Node – ignoring');
        return;
      }

      final multiaddr = (data['m'] ?? data['multiaddr']) as String?;
      final psk = (data['k'] ?? data['psk']) as String?;
      final name = (data['n'] ?? data['name']) as String?;

      // Extract peer_id from multiaddr (/p2p/<peerID> suffix)
      final peerIdMatch = RegExp(r'/p2p/([^/]+)$').firstMatch(multiaddr ?? '');
      final peerId = (data['p'] ?? data['peer_id'] as String?) ?? peerIdMatch?.group(1);

      if (peerId == null || multiaddr == null || psk == null) {
        Logger.error('PSK QR code missing required fields (peer_id, multiaddr or psk/k)');
        if (mounted) {
          showTopNotification(
            context,
            'Invalid QR code – missing peer_id, multiaddr or PSK key',
            isError: true,
          );
        }
        return;
      }

      setState(() {
        _scannedPeerId = peerId;
        _scannedMultiaddr = multiaddr;
        _scannedPsk = psk;
        _scannedNodeName = name;
        _scannerActive = false;
      });

      Logger.info('✅ PSK Node scanned: ${name ?? peerId}');
    } catch (e) {
      Logger.error('Failed to parse PSK QR code: $e');
    }
  }

  void _rescan() {
    setState(() {
      _scannedPeerId = null;
      _scannedMultiaddr = null;
      _scannedPsk = null;
      _scannedNodeName = null;
      _scannerActive = true;
    });
  }

  bool get _canCreate =>
      _scannedPeerId != null && _nameController.text.trim().isNotEmpty;

  Future<void> _createNetwork() async {
    if (!_canCreate || _isCreating) return;
    setState(() => _isCreating = true);

    try {
      final networkId = _scannedPeerId!;
      final networkName = _nameController.text.trim();

      // 1. Store PSK in secure storage (same key pattern as before)
      const secureStorage = FlutterSecureStorage();
      await secureStorage.write(
        key: 'psk_network_$networkId',
        value: _scannedPsk!,
      );
      Logger.info('🔒 PSK stored in secure storage for network $networkId');

      // 2. Save network metadata
      final service = ref.read(privateNetworkSetupServiceProvider);
      await service.addNetwork(PrivateNetwork(
        networkId: networkId,
        networkName: networkName,
        multiaddr: _scannedMultiaddr!,
        createdAt: DateTime.now().toUtc(),
      ));

      // 3. Switch to the new network and reinitialize P2P
      final networkService = ref.read(networkServiceProvider);
      await networkService.switchToNetwork(networkId);

      await _p2pService.reinitialize();

      Logger.success('✅ Private network "$networkName" created and connected');
      
      // Mark as created so dispose() doesn't resume polling
      _networkCreated = true;

      if (mounted) {
        Navigator.of(context).pop(true);
        showTopNotification(
          context,
          'Private network "$networkName" created!',
        );
      }
    } catch (e) {
      Logger.error('Failed to create private network: $e');
      if (mounted) {
        showTopNotification(
          context,
          'Failed to create network: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nodeScanned = _scannedPeerId != null;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('Create Private Network'),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
      ),
      body: Stack(
        children: [
          // ── Full-body scanner ───────────────────────────────────────────
          if (!nodeScanned)
            MobileScanner(
              controller: _scannerController,
              onDetect: _handleBarcode,
            ),

          // ── Confirmed node view ─────────────────────────────────────────
          if (nodeScanned)
            _buildScannedConfirmation(isDark),

          // ── Scan guide overlay (only while scanning) ────────────────────
          if (!nodeScanned)
            _buildScanGuide(isDark),

          // ── Bottom panel: name field + status + create button ───────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            bottom: keyboardHeight,
            child: _buildBottomPanel(isDark, nodeScanned),
          ),
        ],
      ),
    );
  }

  Widget _buildScanGuide(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
      ),
      child: Column(
        children: [
          const Spacer(),
          Center(
            child: Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Scan your Oasis Node QR code\n(PSK mode)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 220), // space for bottom panel
        ],
      ),
    );
  }

  Widget _buildBottomPanel(bool isDark, bool nodeScanned) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.grey[900]!.withOpacity(0.97)
            : Colors.white.withOpacity(0.97),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step indicator
          Row(
            children: [
              Icon(
                nodeScanned ? Icons.check_circle : Icons.qr_code_scanner,
                size: 16,
                color: nodeScanned
                    ? Colors.green
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  nodeScanned
                      ? 'Node scanned – ${_scannedNodeName ?? _shortId(_scannedPeerId!)}'
                      : 'Point camera at node QR code…',
                  style: TextStyle(
                    fontSize: 13,
                    color: nodeScanned
                        ? Colors.green
                        : (isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ),
              ),
              if (nodeScanned)
                TextButton(
                  onPressed: _rescan,
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  child: const Text('Rescan'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Name field
          TextField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Network Name',
              hintText: 'e.g. Home, Office, Family',
              prefixIcon: const Icon(Icons.shield_outlined),
              filled: true,
              fillColor: isDark
                  ? Colors.grey[800]!.withOpacity(0.4)
                  : Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: Colors.grey.withOpacity(0.25),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Create button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canCreate && !_isCreating ? _createNetwork : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
                elevation: 0,
              ),
              child: _isCreating
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Create Network',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _shortId(String peerId) {
    if (peerId.length <= 16) return peerId;
    return '${peerId.substring(0, 8)}…${peerId.substring(peerId.length - 6)}';
  }

  Widget _buildScannedConfirmation(bool isDark) {
    return Positioned.fill(
      child: Container(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 240),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.green, size: 72),
              const SizedBox(height: 20),
              Text(
                _scannedNodeName ?? 'Oasis Node',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _shortId(_scannedPeerId!),
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'PSK secured ✓',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.green.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
