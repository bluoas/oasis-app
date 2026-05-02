import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mime/mime.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import '../config/app_config.dart';
import '../models/message.dart';
import '../models/contact.dart';
import '../models/chat.dart';
import '../models/app_error.dart';
import '../utils/result.dart';
import 'interfaces/i_p2p_repository.dart';
import 'interfaces/i_crypto_service.dart';
import 'interfaces/i_identity_service.dart';
import 'interfaces/i_storage_service.dart';
import 'my_nodes_service.dart';
import 'bootstrap_nodes_service.dart';
import 'network_service.dart';
import 'private_network_setup_service.dart';
import 'dnsaddr_resolver.dart';
import 'p2p_bridge.dart';
import '../utils/logger.dart';

/// P2P Service - Pure P2P Communication (No "Own Node" concept)
/// 
/// Architecture:
/// 1. Direct P2P via DHT when both peers online
/// 2. Store-and-Forward via any available Oasis Node when offline
/// 3. DHT-based Mailbox Discovery (no hardcoded nodes)
/// 4. E2E Encryption (X25519)
/// 
/// Key Concepts:
/// - No "Own Node" - user connects to ANY available Oasis Node
/// - DHT FindProviders to discover messages: "/oasis-mailbox/{peerID}"
/// - Nodes announce when they have messages for a peer
/// - Fully decentralized - no node configuration required
class P2PService {
  // Dependencies injected via constructor
  final AppConfig _config;
  final IP2PRepository _repository;
  final ICryptoService _crypto;
  final IIdentityService _identity;
  final IStorageService _storage;
  final MyNodesService? _myNodesService;
  final BootstrapNodesService? _bootstrapNodesService;
  final NetworkService? _networkService;
  final PrivateNetworkSetupService? _privateNetworkSetupService;
  final Uuid _uuid;

  // Singleton pattern removed - now managed by Riverpod
  P2PService({
    required AppConfig config,
    required IP2PRepository repository,
    required ICryptoService crypto,
    required IIdentityService identity,
    required IStorageService storage,
    MyNodesService? myNodesService,
    BootstrapNodesService? bootstrapNodesService,
    NetworkService? networkService,
    PrivateNetworkSetupService? privateNetworkSetupService,
    Uuid? uuid,
  })  : _config = config,
        _repository = repository,
        _crypto = crypto,
        _identity = identity,
        _storage = storage,
        _myNodesService = myNodesService,
        _bootstrapNodesService = bootstrapNodesService,
        _networkService = networkService,
        _privateNetworkSetupService = privateNetworkSetupService,
        _uuid = uuid ?? const Uuid();

  Timer? _pollingTimer;
  Timer? _bootstrapReconnectTimer;
  bool _initialized = false;
  bool _isPolling = false; // Prevent overlapping polls
  
  // Adaptive polling for fast call signaling
  bool _fastPollingEnabled = false; // When true, polls every 1s instead of config interval
  
  // Bootstrap node connection management (optimized for single active connection)
  String? _activeBootstrapNode; // Currently active bootstrap node (multiaddr)
  List<String> _availableBootstrapNodes = []; // Fallback nodes
  Map<String, int> _nodeHealthScores = {}; // PeerID -> consecutive failures
  int _maxConsecutiveFailures = 3; // Failover threshold

  // Stream Controller für neue Nachrichten (für UI)
  final _messageStreamController = StreamController<Message>.broadcast();
  Stream<Message> get messageStream => _messageStreamController.stream;

  // Public getters for network stats
  IStorageService get storage => _storage;
  String? get activeBootstrapNode => _activeBootstrapNode;
  List<String> get availableBootstrapNodes => List.unmodifiable(_availableBootstrapNodes);

  // Stream Controller für Chat-Updates (neue Kontakte, KEY_EXCHANGE, etc.)
  final _chatUpdateStreamController = StreamController<void>.broadcast();
  Stream<void> get chatUpdateStream => _chatUpdateStreamController.stream;

  // Stream Controller für eingehende Call Signale
  final _callSignalStreamController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get callSignalStream => _callSignalStreamController.stream;

  /// Trigger a chat update notification
  /// Used when chat data changes (e.g., messages deleted, contact updated)
  void triggerChatUpdate() {
    _chatUpdateStreamController.add(null);
  }

  /// Initialize P2P Service
  Future<void> initialize() async {
    if (_initialized) return;

    if (_config.debugLogging) {
      Logger.info('Initializing P2P Service (Pure P2P - No Own Node)...');
      Logger.info('   Environment: ${_config.environment}');
      Logger.info('   Bootstrap nodes: ${_config.bootstrapNodes.length}');
      Logger.info('   Polling interval: ${_config.messagePollingInterval.inSeconds}s');
    }

    // 1. Initialize sub-services
    final storageResult = await _storage.initialize();
    if (storageResult.isFailure) {
      throw Exception('Failed to initialize storage: ${storageResult.errorOrNull?.userMessage}');
    }
    
    final identityResult = await _identity.initialize();
    if (identityResult.isFailure) {
      throw Exception('Failed to initialize identity: ${identityResult.errorOrNull?.userMessage}');
    }

    // 2. Check network mode BEFORE DNS resolution
    final activeNetworkId = _networkService?.activeNetworkId;
    final isPublicNetwork = _networkService?.isPublicNetwork ?? true;
    
    // 3. Resolve bootstrap peers ONLY for Public Network
    // Private Network uses only Private Network nodes (loaded later)
    List<String> resolvedBootstrapPeers = [];
    
    if (isPublicNetwork) {
      // Public Network: Resolve /dnsaddr/ to TCP-compatible addresses
      // This is critical for iOS where /dnsaddr/ DNS TXT resolution doesn't work
      if (_config.debugLogging) {
        Logger.debug('🌐 Public Network: Resolving bootstrap peers from config...');
        Logger.debug('   Config has ${_config.bootstrapNodes.length} bootstrap entries');
      }
      
      resolvedBootstrapPeers = await DnsaddrResolver.resolveBootstrapPeers(
        _config.bootstrapNodes,
      );
      
      if (_config.debugLogging) {
        Logger.success('Resolved ${resolvedBootstrapPeers.length} TCP-compatible bootstrap peers');
        for (int i = 0; i < resolvedBootstrapPeers.length && i < 5; i++) {
          Logger.debug('   [$i] ${resolvedBootstrapPeers[i]}');
        }
        if (resolvedBootstrapPeers.length > 5) {
          Logger.debug('   ... and ${resolvedBootstrapPeers.length - 5} more');
        }
      }
    } else {
      // Private Network: Skip public bootstrap DNS resolution
      if (_config.debugLogging) {
        Logger.debug('🔒 Private Network: Skipping public bootstrap DNS resolution');
      }
    }

    // 4. Load PSK if in Private Network mode
    String? psk;
    
    if (!isPublicNetwork && activeNetworkId != null) {
      // Private Network Mode: Try to load PSK from secure storage
      // Each network has its own PSK: psk_network_{networkId}
      try {
        final secureStorage = const FlutterSecureStorage();
        final pskKey = 'psk_network_$activeNetworkId';
        psk = await secureStorage.read(key: pskKey);
        
        if (psk != null && psk.isNotEmpty) {
          Logger.success('🔐 Loaded PSK from secure storage for Private Network');
          Logger.debug('   Network ID: ${activeNetworkId.substring(0, 16)}...');
          Logger.debug('   PSK Key: $pskKey');
          Logger.debug('   PSK Length: ${psk.length} chars');
        } else {
          Logger.warning('⚠️  Private Network selected but no PSK found in storage');
          Logger.warning('   PSK Key: $pskKey');
          Logger.warning('   This may prevent connection to private network nodes');
        }
      } catch (e) {
        Logger.error('❌ Failed to load PSK from secure storage: $e');
      }
    }

    // 5. Load Private Network nodes BEFORE libp2p initialization
    // These will be used as bootstrap nodes instead of public IPFS nodes
    List<String> privateNetworkBootstrapPeers = [];
    
    if (!isPublicNetwork && activeNetworkId != null && _privateNetworkSetupService != null) {
      final multiaddr = _privateNetworkSetupService.getBootstrapMultiaddr(activeNetworkId);
      if (multiaddr != null && multiaddr.isNotEmpty) {
        privateNetworkBootstrapPeers = [multiaddr];
        if (_config.debugLogging) {
          Logger.success('🔒 Private Network bootstrap node: $multiaddr');
        }
      } else {
        Logger.warning('⚠️  Private Network active but no node multiaddr found');
      }
    }

    // 6. Initialize libp2p host with appropriate bootstrap peers (and PSK if private network)
    // Public Network: Use resolved public IPFS bootstrap nodes
    // Private Network: Use Private Network nodes only
    final bootstrapPeersForInit = !isPublicNetwork && privateNetworkBootstrapPeers.isNotEmpty
        ? privateNetworkBootstrapPeers
        : resolvedBootstrapPeers;
    
    if (_identity.privateKey == null) {
      throw Exception('No identity private key available');
    }
    
    await _repository.initialize(_identity.privateKey!, bootstrapPeersForInit, psk: psk);
    
    if (_config.debugLogging) {
      Logger.success('libp2p host initialized with ${bootstrapPeersForInit.length} bootstrap peers');
      if (psk != null) {
        Logger.success('   🔒 Private Network Mode with PSK enabled');
      }
    }

    // 7. Connect to ONE bootstrap node (sequential failover, not parallel)
    // Optimization: Single active connection instead of all nodes in parallel
    // Benefits: 66% less network traffic, better battery life, faster polling
    
    // NETWORK SELECTION: Filter nodes based on active network (Public vs Private)
    final activeNetworkIdForNodes = _networkService?.activeNetworkId;
    final isPublicNetworkForNodes = _networkService?.isPublicNetwork ?? true;
    
    // PRIORITY 1: Load nodes based on network mode
    List<String> myOasisNodes = [];
    
    if (!isPublicNetworkForNodes && activeNetworkIdForNodes != null && _privateNetworkSetupService != null) {
      final multiaddr = _privateNetworkSetupService.getBootstrapMultiaddr(activeNetworkIdForNodes);
      if (multiaddr != null && multiaddr.isNotEmpty && _isValidMultiaddr(multiaddr)) {
        myOasisNodes = [multiaddr];
        if (_config.debugLogging) {
          Logger.info('🔒 Private Network: $activeNetworkIdForNodes');
          Logger.info('   Node: $multiaddr');
        }
      }
    } else if (_myNodesService != null && !isPublicNetworkForNodes) {
      // Fallback: Try MyNodesService (for user-deployed relay infrastructure)
      final myNodesInitResult = await _myNodesService.initialize();
      if (myNodesInitResult.isSuccess && _myNodesService.hasNodes) {
        myOasisNodes = _myNodesService.getMultiaddrs()
            .where((addr) => _isValidMultiaddr(addr))
            .toList();
        
        if (_config.debugLogging) {
          Logger.info('Loaded ${myOasisNodes.length} My Oasis Node(s) from MyNodesService');
        }
      }
    }
    
    // PRIORITY 2: Combine config bootstrap nodes + discovered Oasis nodes
    final configBootstrapNodes = _config.bootstrapNodes;
    List<String> userBootstrapNodes = [];
    
    // Load discovered Oasis nodes if service exists (ONLY for Public Network)
    if (_bootstrapNodesService != null && isPublicNetworkForNodes) {
      final initResult = await _bootstrapNodesService.initialize();
      if (initResult.isSuccess && _bootstrapNodesService.hasNodes) {
        userBootstrapNodes = _bootstrapNodesService.getMultiaddrs()
            .where((addr) => _isValidMultiaddr(addr))  // Filter out localhost, etc
            .toList();
        if (_config.debugLogging) {
          Logger.info('Loaded ${userBootstrapNodes.length} discovered Oasis node(s)');
        }
      }
    }
    
    // CRITICAL: Separate IPFS Bootstrap (for DHT only) from Oasis Nodes (for Relay)
    // - IPFS Bootstrap is handled automatically by Go-layer (p2p_c.go)
    // - configBootstrapNodes should NOT be connected as Relay (they don't support /oasis-node/*)
    // - Only myOasisNodes and userBootstrapNodes are actual Oasis Relays
    
    // Combine only OASIS nodes (not IPFS bootstrap!)
    // Deduplicate by PeerID: same physical node may appear in multiple lists
    final seenPeerIDs = <String>{};
    final allPeers = <String>[];
    for (final peer in [...myOasisNodes, ...userBootstrapNodes]) {
      final peerID = extractPeerIDFromMultiaddr(peer);
      if (seenPeerIDs.add(peerID)) {
        allPeers.add(peer);
      }
    }
    
    // Store ALL nodes for reference
    // Private Network: Only store Private Network nodes (no public IPFS)
    // Public Network: Include public IPFS bootstrap for auto-discovery reference
    if (isPublicNetworkForNodes) {
      _availableBootstrapNodes = List.from([...allPeers, ...configBootstrapNodes]);
    } else {
      _availableBootstrapNodes = List.from(allPeers);
    }
    
    // Randomize node order for privacy and load balancing
    // Each app start connects to a random node instead of always the first one
    allPeers.shuffle();
    
    if (_config.debugLogging) {
      Logger.info('Connecting to Oasis Nodes (IPFS bootstrap runs automatically in Go-layer)...');
      if (isPublicNetworkForNodes) {
        Logger.info('   🌐 Public Network Mode');
        Logger.info('   Discovered Oasis nodes: ${userBootstrapNodes.length}');
      } else {
        Logger.info('   🔒 Private Network Mode');
        Logger.info('   My Private Networks nodes: ${myOasisNodes.length} 🟢 PRIORITY');
      }
      if (isPublicNetworkForNodes) {
        Logger.info('   IPFS Bootstrap (Go-layer): ${configBootstrapNodes.length} (not connected as Relay)');
      }
      Logger.info('   Total Oasis nodes to connect: ${allPeers.length}');
      Logger.info('   🎲 Node order randomized for privacy');
    }
    _nodeHealthScores.clear();
    
    // Try to connect to first available Oasis Node (if any configured)
    // Note: If no Oasis Nodes configured yet, this is OK - auto-discovery will find them
    bool connected = false;
    bool connectedToMyNode = false;
    
    if (allPeers.isEmpty) {
      if (_config.debugLogging) {
        Logger.info('No Oasis Nodes configured yet (normal for first start)');
        Logger.info('   → DHT is bootstrapping automatically via IPFS (Go-layer)');
        Logger.info('   → Auto-discovery will find Oasis Nodes after DHT is ready');
      }
    } else {
      for (int i = 0; i < allPeers.length; i++) {
        final peer = allPeers[i];
        final isMyOasisNode = i < myOasisNodes.length;

        try {
          await _repository.connectToRelay(peer)
              .timeout(_config.connectionTimeout);

          if (_config.debugLogging) {
            Logger.success('Connected to: ${peer.split('/').last}${isMyOasisNode ? ' (My Oasis Node 🟢)' : ''}');
          }

          _activeBootstrapNode = peer;
          _nodeHealthScores[extractPeerIDFromMultiaddr(peer)] = 0;
          connected = true;
          connectedToMyNode = isMyOasisNode;
          break;
        } catch (e) {
          if (_config.debugLogging) {
            Logger.warning('⚠️ Failed: ${peer.split('/').last} - trying next...');
          }
          
          // Blacklist failed discovered nodes (not user's own nodes)
          // This prevents repeated timeouts on future app starts
          if (!isMyOasisNode && _bootstrapNodesService != null && isPublicNetworkForNodes) {
            final peerID = extractPeerIDFromMultiaddr(peer);
            await _bootstrapNodesService.blacklistNode(peerID);
          }
        }
      }
    }
    
    if (!connected && allPeers.isNotEmpty) {
      Logger.warning('Oasis Nodes configured but unreachable at startup');
      Logger.info('Will retry connection every 30 seconds...');
      _startBootstrapReconnectTimer();
    } else if (connected) {
      if (_config.debugLogging) {
        Logger.success('Active node connected: ${_activeBootstrapNode!.split('/').last}');
        Logger.info('   Fallback nodes available: ${_availableBootstrapNodes.length - 1}');
      }
      _bootstrapReconnectTimer?.cancel();
      _bootstrapReconnectTimer = null;

      // OPTIMIZED: Only try FIRST "My Node" if we landed on bootstrap instead
      // Rationale: Already have working connection - no need to try ALL nodes
      // This prevents 30-180s delays when user has multiple offline "My Nodes"
      if (!connectedToMyNode && myOasisNodes.isNotEmpty) {
        Future.delayed(const Duration(seconds: 2), () async {
          final firstMyNode = myOasisNodes.first;
          final peerID = extractPeerIDFromMultiaddr(firstMyNode);
          
          // Single quick attempt with short timeout (3s)
          try {
            await _repository.connectToRelay(firstMyNode)
                .timeout(const Duration(seconds: 3));
            _activeBootstrapNode = firstMyNode;
            _nodeHealthScores[peerID] = 0;
            if (_config.debugLogging) {
              Logger.success('Switched to My Oasis Node: ${firstMyNode.split('/').last}');
            }
          } catch (_) {
            // No problem - bootstrap connection works fine
            if (_config.debugLogging) {
              Logger.debug('My Oasis Node not reachable, using bootstrap (works fine)');
            }
          }
        });
      }
    }

    // 5. Note: Client does NOT announce own mailbox to DHT!
    //    Reason: Would cause self-discovery issues during polling.
    //    Architecture: Simple client-server model - app only talks to connected node
    Logger.info('📬 Message retrieval: Polling from active node every 30s');

    // 6. Start message polling from active node only
    _startPolling();

    // 7. Clean old nonces
    final cleanResult = await _storage.cleanOldNonces();
    if (cleanResult.isFailure) {
      Logger.warning('Failed to clean old nonces: ${cleanResult.errorOrNull?.userMessage}');
    }

    _initialized = true;
    Logger.success('P2P Service initialized');
    Logger.info('   PeerID: ${_identity.peerID}');
    Logger.info('   Architecture: Pure P2P with DHT-based message discovery');
    
    // 9. Send key-exchange requests for contacts without public keys
    // This handles contacts added during onboarding or contacts that haven't completed key exchange
    await _sendPendingKeyExchanges();
    
    // 10. Retry sending any pending messages (including key exchanges created above)
    // This ensures messages created during onboarding are sent after first connect
    if (_activeBootstrapNode != null) {
      retryPendingMessages().catchError((e) {
        print('⚠️ Background retry of pending messages failed: $e');
        // Non-fatal, messages stay pending for next retry
      });
    }
  }

  /// Reinitialize P2P Service after identity reset
  Future<void> reinitialize() async {
    print('🔄 Reinitializing P2P Service...');
    
    // Stop polling and reconnect timers
    _pollingTimer?.cancel();
    _bootstrapReconnectTimer?.cancel();
    _bootstrapReconnectTimer = null;
    
    // Close old P2P host
    await _repository.close();
    
    // Reset connection state so the old node is not used during the new initialization
    _activeBootstrapNode = null;
    _availableBootstrapNodes = [];
    _nodeHealthScores.clear();
    
    // Reset flag to allow initialization
    _initialized = false;
    
    // Reinitialize
    await initialize();
    
    print('✅ P2P Service reinitialized');
  }

  /// Pause polling (for identity reset)
  void pausePolling() {
    print('⏸️ Pausing message polling...');
    _pollingTimer?.cancel();
    _bootstrapReconnectTimer?.cancel();
    _bootstrapReconnectTimer = null;
  }

  /// Resume/start polling after it was paused
  void startPolling() {
    print('▶️ Starting/resuming message polling...');
    _startPolling();
  }

  /// Send audio message to recipient
  /// 
  /// Flow:
  /// 1. Read audio file and encode as base64
  /// 2. Encrypt using X25519
  /// Send audio message to recipient
  /// 
  /// Audio format: AAC (M4A) at 64 kbps / 22 kHz (optimized for voice)
  /// - 30 seconds ≈ 120 KB raw → ~180 KB encrypted → ~250 KB final message
  /// - Stays well under relay node message size limits
  /// 
  /// 1. Read audio file and validate size
  /// 2. Encrypt with recipient's X25519 public key
  /// 3. Send via relay with audio metadata (including waveform visualization data)
  Future<void> sendAudioMessage({
    required String recipientPeerID,
    required String audioPath,
    required Duration duration,
    required List<double> waveform,
    String? replyToMessageId,
    String? replyToPreviewText,
    ContentType? replyToContentType,
  }) async {
    if (!_initialized) throw StateError('Not initialized');

    print('🎵 Sending audio message to $recipientPeerID (${duration.inSeconds}s)');

    // 1. Get recipient contact
    final contactResult = await _storage.getContact(recipientPeerID);
    if (contactResult.isFailure) {
      throw Exception('Failed to get contact');
    }
    
    final contact = contactResult.valueOrNull;
    if (contact?.publicKey == null || contact!.publicKey!.length != 32) {
      throw Exception('No X25519 encryption key for recipient $recipientPeerID. Exchange keys first!');
    }

    // 2. Read and validate audio file
    final audioFile = File(audioPath);
    if (!await audioFile.exists()) {
      throw Exception('Audio file not found: $audioPath');
    }
    
    final audioBytes = await audioFile.readAsBytes();
    final audioSizeKB = (audioBytes.length / 1024).round();
    print('   Audio size: ${audioSizeKB}KB');

    // Validate file size (unencrypted)
    // With 64 kbps encoding: 5 min max = ~2.4 MB, so 5MB limit is safe
    // After encryption, final message will be ~35% larger
    if (audioBytes.length > 5 * 1024 * 1024) {
      throw Exception('Audio file too large (max 5MB): ${audioSizeKB}KB');
    }
    
    // Extract relative path (iOS container path changes on restart)
    // Store only: audio/audio_123.m4a instead of full path
    final appSupportDir = await getApplicationSupportDirectory();
    final relativePath = audioPath.replaceFirst('${appSupportDir.path}/', '');
    print('   Storing relative path: $relativePath');
    
    // 3. Encrypt audio (encode as base64 string first)
    final audioBase64 = base64Encode(audioBytes);
    final encryptResult = await _crypto.encrypt(
      plaintext: audioBase64,
      recipientPublicKey: contact.publicKey!,
      senderPrivateKey: _identity.encryptionPrivateKey!,
    );
    
    if (encryptResult.isFailure) {
      print('❌ Audio encryption failed: ${encryptResult.errorOrNull?.userMessage}');
      throw Exception('Failed to encrypt audio: ${encryptResult.errorOrNull?.message}');
    }

    // 4. Create message with audio metadata
    final nonceResult = _crypto.generateNonce();
    if (nonceResult.isFailure) {
      throw Exception('Nonce generation failed');
    }
    
    final message = Message(
      id: _uuid.v4(),
      senderPeerID: _identity.peerID!,
      targetPeerID: recipientPeerID,
      timestamp: DateTime.now().toUtc(),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
      ciphertext: encryptResult.valueOrNull!,
      signature: Uint8List(0), // temp
      nonce: nonceResult.valueOrNull!,
      senderPublicKey: _identity.encryptionPublicKey!,
      targetHomeNode: contact.connectedNodeMultiaddr,
      senderHomeNode: _activeBootstrapNode,
      contentType: ContentType.audio,
      contentMeta: {
        'duration': duration.inSeconds.toString(),
        'size': audioBytes.length.toString(),
        'format': 'm4a',
        'mime_type': 'audio/m4a',
        'bitrate': '64000',  // 64 kbps AAC
        'sample_rate': '22050', // 22 kHz
        'waveform': jsonEncode(waveform), // Real-time recorded amplitude data for visualization
      },
      replyToMessageId: replyToMessageId,
      replyToPreviewText: replyToPreviewText,
      replyToContentType: replyToContentType,
      plaintext: relativePath, // Store RELATIVE path (iOS container changes on restart)
      isRead: true, // Own sent messages are already "read"
      deliveryStatus: DeliveryStatus.pending,
      networkId: _networkService?.activeNetworkId ?? 'public', // Network separation
    );

    // 5. Sign
    final signResult = await _identity.sign(utf8.encode(message.signableData));
    if (signResult.isFailure) {
      print('❌ Failed to sign audio message: ${signResult.errorOrNull?.userMessage}');
      throw Exception('Signature failed');
    }
    final signedMessage = message.copyWith(signature: signResult.valueOrNull!);

    // 6. Save locally before sending
    print('💾 Saving audio message locally...');
    final saveResult = await _storage.saveMessage(signedMessage);
    if (saveResult.isFailure) {
      print('⚠️ Failed to save audio message: ${saveResult.errorOrNull?.userMessage}');
      throw Exception('Failed to save audio message: ${saveResult.errorOrNull?.message}');
    }

    // 7. Send via relay
    print('📦 Sending audio message via relay...');
    try {
      await _sendViaRelay(signedMessage);
      
      // Success! Update status to sent
      final sentMessage = signedMessage.copyWith(deliveryStatus: DeliveryStatus.sent);
      await _storage.saveMessage(sentMessage);
      print('✅ Audio message sent');
      
      // Trigger chat update so HomeScreen refreshes Chats tab
      triggerChatUpdate();
    } catch (e) {
      // Mark as failed
      final failedMessage = signedMessage.copyWith(deliveryStatus: DeliveryStatus.failed);
      await _storage.saveMessage(failedMessage);
      
      // Still trigger update to show failed message in UI
      triggerChatUpdate();
      
      rethrow;
    }
  }

  /// Send image message with E2E encryption
  /// 
  /// Features:
  /// - Validates file size (max 10MB)
  /// - Compresses large images
  /// - Encrypts image bytes
  /// - Stores metadata (width, height, mime_type)
  /// 
  /// Throws:
  /// - Exception if recipient has no encryption key
  /// - Exception if image file is too large or invalid
  Future<void> sendImageMessage({
    required String recipientPeerID,
    required String imagePath,
    String? caption,
    String? replyToMessageId,
    String? replyToPreviewText,
    ContentType? replyToContentType,
  }) async {
    if (!_initialized) throw StateError('Not initialized');

    print('🖼️ Sending image message to $recipientPeerID');

    // 1. Get recipient contact
    final contactResult = await _storage.getContact(recipientPeerID);
    if (contactResult.isFailure) {
      throw Exception('Failed to get contact');
    }
    
    final contact = contactResult.valueOrNull;
    if (contact?.publicKey == null || contact!.publicKey!.length != 32) {
      throw Exception('No X25519 encryption key for recipient $recipientPeerID. Exchange keys first!');
    }

    // 2. Read and validate image file
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw Exception('Image file not found: $imagePath');
    }
    
    // Detect MIME type
    final mimeType = lookupMimeType(imagePath) ?? 'image/jpeg';
    print('   MIME type: $mimeType');
    
    // Validate MIME type (security: only allow images)
    if (!mimeType.startsWith('image/')) {
      throw Exception('Invalid file type. Only images are allowed.');
    }
    
    final allowedTypes = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
    if (!allowedTypes.contains(mimeType)) {
      throw Exception('Unsupported image format: $mimeType');
    }

    // 3. Load and optionally compress image
    var imageBytes = await imageFile.readAsBytes();
    var imageSizeKB = (imageBytes.length / 1024).round();
    print('   Original size: ${imageSizeKB}KB');

    // Decode image to get dimensions
    img.Image? decodedImage = img.decodeImage(imageBytes);
    if (decodedImage == null) {
      throw Exception('Failed to decode image');
    }
    
    final originalWidth = decodedImage.width;
    final originalHeight = decodedImage.height;
    print('   Dimensions: ${originalWidth}x$originalHeight');

    // Compress if image is too large
    const maxSizeBytes = 10 * 1024 * 1024; // 10 MB absolute max
    const targetSizeBytes = 400 * 1024; // 400 KB target (to stay under relay limits after encryption)
    
    if (imageBytes.length > maxSizeBytes) {
      throw Exception('Image too large (${(imageBytes.length / (1024 * 1024)).toStringAsFixed(1)} MB). Max: 10 MB');
    }
    
    // Compress if > 400KB or dimensions > 1280px
    if (imageBytes.length > targetSizeBytes || originalWidth > 1280 || originalHeight > 1280) {
      print('   Compressing image...');
      
      // Resize if too large
      if (originalWidth > 1280 || originalHeight > 1280) {
        decodedImage = img.copyResize(
          decodedImage,
          width: originalWidth > originalHeight ? 1280 : null,
          height: originalHeight > originalWidth ? 1280 : null,
          interpolation: img.Interpolation.linear,
        );
      }
      
      // Re-encode with compression
      if (mimeType == 'image/png') {
        imageBytes = Uint8List.fromList(img.encodePng(decodedImage, level: 9)); // Max compression
      } else {
        // Convert to JPEG for better compression
        imageBytes = Uint8List.fromList(img.encodeJpg(decodedImage, quality: 70)); // Lower quality for smaller size
      }
      
      imageSizeKB = (imageBytes.length / 1024).round();
      print('   Compressed size: ${imageSizeKB}KB (${decodedImage.width}x${decodedImage.height})');
      
      // If still too large, compress more aggressively
      if (imageBytes.length > targetSizeBytes * 1.2) {
        print('   Still too large, applying aggressive compression...');
        imageBytes = Uint8List.fromList(img.encodeJpg(decodedImage, quality: 60));
        imageSizeKB = (imageBytes.length / 1024).round();
        print('   Final size: ${imageSizeKB}KB');
      }
    }

    // 4. Save encrypted image to local storage
    final appSupportDir = await getApplicationSupportDirectory();
    final imagesDir = Directory('${appSupportDir.path}/images/encrypted');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    
    final messageId = _uuid.v4();
    final fileExtension = path.extension(imagePath).isEmpty ? '.jpg' : path.extension(imagePath);
    final encryptedImagePath = '${imagesDir.path}/img_$messageId$fileExtension';
    
    // Save original (unencrypted) image for sender
    await File(encryptedImagePath).writeAsBytes(imageBytes);
    
    // Store relative path (iOS container changes on restart)
    final relativePath = encryptedImagePath.replaceFirst('${appSupportDir.path}/', '');
    print('   Stored at: $relativePath');
    
    // 5. Encrypt image bytes
    final imageBase64 = base64Encode(imageBytes);
    final encryptResult = await _crypto.encrypt(
      plaintext: imageBase64,
      recipientPublicKey: contact.publicKey!,
      senderPrivateKey: _identity.encryptionPrivateKey!,
    );
    
    if (encryptResult.isFailure) {
      print('❌ Image encryption failed: ${encryptResult.errorOrNull?.userMessage}');
      throw Exception('Failed to encrypt image: ${encryptResult.errorOrNull?.message}');
    }

    // 6. Create message with image metadata
    final nonceResult = _crypto.generateNonce();
    if (nonceResult.isFailure) {
      throw Exception('Nonce generation failed');
    }
    
    final message = Message(
      id: messageId,
      senderPeerID: _identity.peerID!,
      targetPeerID: recipientPeerID,
      timestamp: DateTime.now().toUtc(),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
      ciphertext: encryptResult.valueOrNull!,
      signature: Uint8List(0), // temp
      nonce: nonceResult.valueOrNull!,
      senderPublicKey: _identity.encryptionPublicKey!,
      targetHomeNode: contact.connectedNodeMultiaddr,
      senderHomeNode: _activeBootstrapNode,
      contentType: ContentType.image,
      contentMeta: {
        'width': decodedImage.width.toString(),
        'height': decodedImage.height.toString(),
        'size': imageBytes.length.toString(),
        'mime_type': mimeType,
        if (caption != null && caption.isNotEmpty) 'caption': caption,
      },
      replyToMessageId: replyToMessageId,
      replyToPreviewText: replyToPreviewText,
      replyToContentType: replyToContentType,
      plaintext: relativePath, // Store RELATIVE path for image file
      isRead: true, // Own sent messages are already "read"
      deliveryStatus: DeliveryStatus.pending,
      networkId: _networkService?.activeNetworkId ?? 'public', // Network separation
    );

    // 7. Sign
    final signResult = await _identity.sign(utf8.encode(message.signableData));
    if (signResult.isFailure) {
      print('❌ Failed to sign image message: ${signResult.errorOrNull?.userMessage}');
      throw Exception('Signature failed');
    }
    final signedMessage = message.copyWith(signature: signResult.valueOrNull!);

    // 8. Save locally before sending
    print('💾 Saving image message locally...');
    final saveResult = await _storage.saveMessage(signedMessage);
    if (saveResult.isFailure) {
      print('⚠️ Failed to save image message: ${saveResult.errorOrNull?.userMessage}');
      throw Exception('Failed to save image message: ${saveResult.errorOrNull?.message}');
    }

    // 9. Send via relay
    print('📦 Sending image message via relay...');
    try {
      await _sendViaRelay(signedMessage);
      
      // Success! Update status to sent
      final sentMessage = signedMessage.copyWith(deliveryStatus: DeliveryStatus.sent);
      await _storage.saveMessage(sentMessage);
      print('✅ Image message sent');
      
      // Trigger chat update so HomeScreen refreshes Chats tab
      triggerChatUpdate();
    } catch (e) {
      // Mark as failed
      final failedMessage = signedMessage.copyWith(deliveryStatus: DeliveryStatus.failed);
      await _storage.saveMessage(failedMessage);
      
      // Still trigger update to show failed message in UI
      triggerChatUpdate();
      
      rethrow;
    }
  }

  /// Send profile update to all contacts
  /// 
  /// Features:
  /// - Sends updated username and/or profile image to all contacts
  /// - Profile image is base64 encoded and encrypted
  /// - Allows contacts to keep profile info in sync
  /// 
  /// Parameters:
  /// - userName: Updated display name
  /// - profileImagePath: Path to local profile image (optional)
  Future<void> sendProfileUpdate({
    required String userName,
    String? profileImagePath,
    bool deleteImage = false,  // Explicitly signal image deletion
  }) async {
    if (!_initialized) throw StateError('Not initialized');

    print('👤 Sending profile update to all contacts...');
    print('   Name: $userName');
    print('   Profile image: ${profileImagePath ?? "none"}');
    print('   Delete image: $deleteImage');

    // Get all contacts
    final contactsResult = await _storage.getAllContacts();
    if (contactsResult.isFailure) {
      throw Exception('Failed to get contacts: ${contactsResult.errorOrNull?.message}');
    }
    
    final contacts = contactsResult.valueOrNull ?? [];
    if (contacts.isEmpty) {
      print('   No contacts to send profile update to');
      return;
    }
    
    // Filter out KM-Node contacts (they don't need profile updates)
    final regularContacts = contacts.where((c) => !c.isKMNodeContact).toList();
    if (regularContacts.isEmpty) {
      print('   No regular contacts to send profile update to (only KM-Node contacts)');
      return;
    }
    
    print('   Sending to ${regularContacts.length} contact(s)');

    // Prepare profile data as JSON
    final Map<String, dynamic> profileData = {
      'name': userName,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    // If image was explicitly deleted, add deletion flag
    if (deleteImage) {
      profileData['profile_image_deleted'] = true;
      print('   Flagging profile image as deleted');
    }

    // If profile image exists (and not deleted), encode it as base64
    if (!deleteImage && profileImagePath != null && profileImagePath.isNotEmpty) {
      try {
        File imageFile;
        
        // Handle both absolute paths and relative paths
        if (profileImagePath.startsWith('/')) {
          // Absolute path - use directly
          imageFile = File(profileImagePath);
        } else {
          // Relative path - construct full path from ApplicationSupportDirectory
          final appSupportDir = await getApplicationSupportDirectory();
          final fullPath = '${appSupportDir.path}/$profileImagePath';
          imageFile = File(fullPath);
        }
        
        if (await imageFile.exists()) {
          final imageBytes = await imageFile.readAsBytes();
          final imageSizeKB = (imageBytes.length / 1024).round();
          print('   Profile image size: ${imageSizeKB}KB');
          
          // Encode as base64
          profileData['profile_image'] = base64Encode(imageBytes);
          
          // Add image metadata
          final mimeType = lookupMimeType(imageFile.path) ?? 'image/jpeg';
          profileData['image_mime_type'] = mimeType;
        }
      } catch (e) {
        print('⚠️ Failed to read profile image: $e');
        // Continue without image
      }
    }

    final profileJson = jsonEncode(profileData);

    // Send to each contact
    int successCount = 0;
    int failCount = 0;
    
    for (final contact in regularContacts) {
      try {
        // Skip contacts without encryption keys
        if (contact.publicKey == null || contact.publicKey!.length != 32) {
          print('   Skipping ${contact.displayName} (no encryption key)');
          failCount++;
          continue;
        }

        // Encrypt profile data
        final encryptResult = await _crypto.encrypt(
          plaintext: profileJson,
          recipientPublicKey: contact.publicKey!,
          senderPrivateKey: _identity.encryptionPrivateKey!,
        );
        
        if (encryptResult.isFailure) {
          print('❌ Encryption failed for ${contact.displayName}: ${encryptResult.errorOrNull?.userMessage}');
          failCount++;
          continue;
        }

        // Create message
        final nonceResult = _crypto.generateNonce();
        if (nonceResult.isFailure) {
          failCount++;
          continue;
        }
        
        final message = Message(
          id: _uuid.v4(),
          senderPeerID: _identity.peerID!,
          targetPeerID: contact.peerID,
          timestamp: DateTime.now().toUtc(),
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
          ciphertext: encryptResult.valueOrNull!,
          signature: Uint8List(0), // temp
          nonce: nonceResult.valueOrNull!,
          senderPublicKey: _identity.encryptionPublicKey!,
          targetHomeNode: contact.connectedNodeMultiaddr,
          senderHomeNode: _activeBootstrapNode,
          contentType: ContentType.profile_update,
          plaintext: '👤 Profile updated', // For local display
          isRead: true,
          deliveryStatus: DeliveryStatus.pending,
          networkId: contact.networkId, // Use contact's network (profile updates are per-network)
        );

        // Sign
        final signResult = await _identity.sign(utf8.encode(message.signableData));
        if (signResult.isFailure) {
          print('❌ Failed to sign profile update for ${contact.displayName}');
          failCount++;
          continue;
        }
        final signedMessage = message.copyWith(signature: signResult.valueOrNull!);

        // Save locally
        await _storage.saveMessage(signedMessage);

        // Send via relay
        try {
          await _sendViaRelay(signedMessage);
          
          // Update status to sent
          final sentMessage = signedMessage.copyWith(deliveryStatus: DeliveryStatus.sent);
          await _storage.saveMessage(sentMessage);
          
          successCount++;
          print('   ✓ Sent to ${contact.displayName}');
        } catch (e) {
          print('   ✗ Failed to send to ${contact.displayName}: $e');
          final failedMessage = signedMessage.copyWith(deliveryStatus: DeliveryStatus.failed);
          await _storage.saveMessage(failedMessage);
          failCount++;
        }
      } catch (e) {
        print('❌ Error sending profile update to ${contact.displayName}: $e');
        failCount++;
      }
    }

    print('✅ Profile update sent to $successCount/${contacts.length} contacts ($failCount failed)');
  }

  /// Send profile update to a specific contact
  /// 
  /// Used for automatic profile exchange when adding new contacts
  /// 
  /// Parameters:
  /// - recipientPeerID: PeerID of the contact to send profile to
  /// - userName: Display name
  /// - profileImagePath: Path to local profile image (optional)
  /// - deleteImage: Flag to signal profile image deletion
  Future<void> sendProfileUpdateToContact({
    required String recipientPeerID,
    required String userName,
    String? profileImagePath,
    bool deleteImage = false,
  }) async {
    if (!_initialized) throw StateError('Not initialized');

    // Skip if no meaningful data to send (unless explicitly deleting image)
    final hasNoUserName = userName.isEmpty || userName == 'User';
    final hasNoImage = profileImagePath == null || profileImagePath.isEmpty;
    if (!deleteImage && hasNoUserName && hasNoImage) {
      print('ℹ️ No profile data to send to $recipientPeerID, skipping');
      return;
    }

    print('👤 Sending profile update to $recipientPeerID...');

    // Get contact
    final contactResult = await _storage.getContact(recipientPeerID);
    if (contactResult.isFailure || contactResult.valueOrNull == null) {
      print('   Contact not found, skipping');
      return;
    }
    
    final contact = contactResult.valueOrNull!;
    
    // Skip KM-Node contacts (they don't need profile updates)
    if (contact.isKMNodeContact) {
      print('   Skipping KM-Node contact, no profile updates needed');
      return;
    }
    
    // Skip if no encryption key
    if (contact.publicKey == null || contact.publicKey!.length != 32) {
      print('   No encryption key for contact, skipping');
      return;
    }

    // Prepare profile data as JSON
    final Map<String, dynamic> profileData = {
      'name': userName,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    // If image was explicitly deleted, add deletion flag
    if (deleteImage) {
      profileData['profile_image_deleted'] = true;
      print('   Flagging profile image as deleted');
    }

    // If profile image exists (and not deleted), encode it as base64
    if (!deleteImage && profileImagePath != null && profileImagePath.isNotEmpty) {
      try {
        File imageFile;
        
        // Handle both absolute paths and relative paths
        if (profileImagePath.startsWith('/')) {
          // Absolute path - use directly
          imageFile = File(profileImagePath);
        } else {
          // Relative path - construct full path from ApplicationSupportDirectory
          final appSupportDir = await getApplicationSupportDirectory();
          final fullPath = '${appSupportDir.path}/$profileImagePath';
          imageFile = File(fullPath);
        }
        
        if (await imageFile.exists()) {
          final imageBytes = await imageFile.readAsBytes();
          final imageSizeKB = (imageBytes.length / 1024).round();
          print('   Profile image size: ${imageSizeKB}KB');
          
          // Encode as base64
          profileData['profile_image'] = base64Encode(imageBytes);
          
          // Add image metadata
          final mimeType = lookupMimeType(imageFile.path) ?? 'image/jpeg';
          profileData['image_mime_type'] = mimeType;
        }
      } catch (e) {
        print('⚠️ Failed to read profile image: $e');
        // Continue without image
      }
    }

    final profileJson = jsonEncode(profileData);

    try {
      // Encrypt profile data
      final encryptResult = await _crypto.encrypt(
        plaintext: profileJson,
        recipientPublicKey: contact.publicKey!,
        senderPrivateKey: _identity.encryptionPrivateKey!,
      );
      
      if (encryptResult.isFailure) {
        print('❌ Encryption failed: ${encryptResult.errorOrNull?.userMessage}');
        return;
      }

      // Create message
      final nonceResult = _crypto.generateNonce();
      if (nonceResult.isFailure) {
        return;
      }
      
      final message = Message(
        id: _uuid.v4(),
        senderPeerID: _identity.peerID!,
        targetPeerID: contact.peerID,
        timestamp: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
        ciphertext: encryptResult.valueOrNull!,
        signature: Uint8List(0), // temp
        nonce: nonceResult.valueOrNull!,
        senderPublicKey: _identity.encryptionPublicKey!,
        targetHomeNode: contact.connectedNodeMultiaddr,
        senderHomeNode: _activeBootstrapNode,
        contentType: ContentType.profile_update,
        plaintext: '👤 Profile updated',
        isRead: true,
        deliveryStatus: DeliveryStatus.pending,
      );

      // Sign
      final signResult = await _identity.sign(utf8.encode(message.signableData));
      if (signResult.isFailure) {
        print('❌ Failed to sign profile update');
        return;
      }
      final signedMessage = message.copyWith(signature: signResult.valueOrNull!);

      // Save locally (temporarily for retry mechanism)
      await _storage.saveMessage(signedMessage);

      // Send via relay
      try {
        await _sendViaRelay(signedMessage);
        
        // Success! Delete from local storage after confirmation
        // Profile updates are not chat messages and shouldn't appear in chat history
        await _storage.deleteMessage(signedMessage.id);
        
        // Update contact with lastProfileUpdateSentAt timestamp for loop prevention
        final updatedContact = contact.copyWith(
          lastProfileUpdateSentAt: DateTime.now().toUtc(),
        );
        await _storage.saveContact(updatedContact);
        
        print('   ✓ Profile update sent to ${contact.displayName}');
      } catch (e) {
        print('   ✗ Failed to send: $e');
        final failedMessage = signedMessage.copyWith(deliveryStatus: DeliveryStatus.failed);
        await _storage.saveMessage(failedMessage);
      }
    } catch (e) {
      print('❌ Error sending profile update: $e');
    }
  }

  /// Send key exchange request to recipient
  /// 
  /// Sends an unencrypted message containing only the sender's X25519 public key
  /// This allows the recipient to store the key and enable encrypted messaging
  Future<void> sendKeyExchangeRequest(String recipientPeerID) async {
    if (!_initialized) throw StateError('Not initialized');

    print('🔑 Sending key exchange request to $recipientPeerID...');

    // Create a special key-exchange message with plaintext marker
    final nonceResult = _crypto.generateNonce();
    if (nonceResult.isFailure) {
      print('❌ Failed to generate nonce: ${nonceResult.errorOrNull?.userMessage}');
      throw Exception('Nonce generation failed');
    }
    
    final keyExchangeMessage = Message(
      id: _uuid.v4(),
      senderPeerID: _identity.peerID!,
      targetPeerID: recipientPeerID,
      timestamp: DateTime.now().toUtc(),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
      ciphertext: Uint8List.fromList(utf8.encode('KEY_EXCHANGE_REQUEST')), // Special marker
      signature: Uint8List(0), // temp
      nonce: nonceResult.valueOrNull!,
      senderPublicKey: _identity.encryptionPublicKey!, // The important part!
      plaintext: '🔑 Key exchange request', // For local display
      deliveryStatus: DeliveryStatus.pending, // Mark as pending for retry mechanism
    );

    // Sign the message
    final signResult = await _identity.sign(utf8.encode(keyExchangeMessage.signableData));
    if (signResult.isFailure) {
      print('❌ Failed to sign key exchange message: ${signResult.errorOrNull?.userMessage}');
      throw Exception('Signature failed');
    }
    final signature = signResult.valueOrNull!;
    final signedMessage = keyExchangeMessage.copyWith(signature: signature);

    // CRITICAL: Save before sending (enables retry if node connection fails!)
    // Without this, key exchanges are lost if no node is reachable at send time
    print('💾 Saving key exchange locally before send...');
    final saveResult = await _storage.saveMessage(signedMessage);
    if (saveResult.isFailure) {
      print('❌ Failed to save key exchange: ${saveResult.errorOrNull?.userMessage}');
      throw Exception('Failed to save key exchange: ${saveResult.errorOrNull?.message}');
    }
    print('✅ Key exchange saved to local storage (id: ${signedMessage.id})');

    // Try to send via relay (don't try direct, as we don't have encryption yet)
    try {
      await _sendViaRelay(signedMessage);
      
      // Success! Update status to sent (and delete from local storage after confirmation)
      final sentMessage = signedMessage.copyWith(deliveryStatus: DeliveryStatus.sent);
      await _storage.saveMessage(sentMessage);
      print('✅ Key exchange request sent to $recipientPeerID');
      
      // Clean up: Delete key exchange from local storage after successful send
      // (Key exchanges are not real chat messages and shouldn't appear in chat history)
      await _storage.deleteMessage(sentMessage.id);
    } catch (e) {
      // Mark as failed so retry mechanism can pick it up later
      print('⚠️ Send failed for $recipientPeerID, marking as failed for retry: $e');
      final failedMessage = signedMessage.copyWith(deliveryStatus: DeliveryStatus.failed);
      final failedSaveResult = await _storage.saveMessage(failedMessage);
      if (failedSaveResult.isSuccess) {
        print('✅ Key exchange marked as failed in storage (will retry later)');
      } else {
        print('❌ Failed to mark key exchange as failed: ${failedSaveResult.errorOrNull?.userMessage}');
      }
      // Don't rethrow - message is saved, retry will handle it
      // Throwing here would interrupt the loop in _sendPendingKeyExchanges
    }
  }

  /// Send key-exchange requests to all contacts without public keys
  /// Called automatically during initialization
  /// 
  /// Strategy:
  /// 1. Always create and save key exchange messages (with pending status)
  /// 2. Only attempt to send if node connection exists
  /// 3. If no connection: messages stay pending, retry mechanism sends later
  Future<void> _sendPendingKeyExchanges() async {
    try {
      final contactsResult = await _storage.getAllContacts();
      if (contactsResult.isFailure) {
        print('⚠️ Failed to load contacts for pending key exchanges');
        return;
      }

      final contacts = contactsResult.valueOrNull!;
      final pendingContacts = contacts.where((c) => c.publicKey == null).toList();

      if (pendingContacts.isEmpty) {
        Logger.info('No pending key exchanges needed');
        return;
      }

      Logger.info('Creating ${pendingContacts.length} pending key exchange(s)...');
      
      // Check if we can send immediately or if we need to defer
      final canSendNow = _activeBootstrapNode != null;
      
      if (!canSendNow) {
        print('ℹ️ No node connection yet - key exchanges will be stored as pending');
        print('   They will be sent automatically when connection is established');
      }
      
      for (final contact in pendingContacts) {
        try {
          await sendKeyExchangeRequest(contact.peerID);
          if (canSendNow) {
            print('   ✅ Processed: ${contact.displayName}');
          } else {
            print('   💾 Queued: ${contact.displayName} (will retry when online)');
          }
        } catch (e) {
          // This catches errors during message creation (signing, nonce gen, etc)
          // Send failures are handled inside sendKeyExchangeRequest
          print('   ❌ Failed to create key exchange for ${contact.displayName}: $e');
        }
      }
      
      print('✅ Pending key exchanges processed');
    } catch (e) {
      print('❌ Unexpected error processing key exchanges: $e');
      // Non-fatal, app continues to work
    }
  }
  
  /// Send message to recipient
  /// 
  /// Flow:
  /// 1. Encrypt message (E2E)
  /// 2. Try Direct P2P
  /// 3. Fallback to Relay
  Future<void> sendMessage({
    required String recipientPeerID,
    required String text,
    String? replyToMessageId,
    String? replyToPreviewText,
    ContentType? replyToContentType,
  }) async {
    if (!_initialized) throw StateError('Not initialized');

    print('📤 Sending message to $recipientPeerID...');

    // 1. Get recipient's X25519 encryption public key from stored contact
    final contactResult = await _storage.getContact(recipientPeerID);
    if (contactResult.isFailure) {
      throw Exception('Failed to get contact: ${contactResult.errorOrNull?.userMessage}');
    }
    
    final contact = contactResult.valueOrNull;
    var recipientPublicKey = contact?.publicKey;
    
    print('📇 Looking up recipient $recipientPeerID...');
    print('   Contact found: ${contact != null}');
    if (contact != null) {
      print('   Contact name: ${contact.displayName}');
      print('   Public key stored: ${contact.publicKey != null}');
      if (contact.publicKey != null) {
        print('   Public key length: ${contact.publicKey!.length} bytes');
        print('   Public key (base64): ${base64Encode(contact.publicKey!)}');
      }
    }
    
    if (recipientPublicKey == null) {
      throw Exception('No X25519 encryption key for recipient $recipientPeerID. Exchange keys first!');
    }

    if (recipientPublicKey.length != 32) {
      throw Exception('Invalid X25519 public key length: ${recipientPublicKey.length} (expected 32)');
    }

    print('🔑 Using stored X25519 key for $recipientPeerID (${contact!.displayName})');
    
    // Log recipient's home node for cross-node forwarding
    if (contact.connectedNodeMultiaddr != null && contact.connectedNodeMultiaddr!.isNotEmpty) {
      print('📍 Recipient home node: ${contact.connectedNodeMultiaddr}');
    } else {
      print('⚠️ No home node info for recipient (message will stay on this node)');
    }

    // 2. Encrypt using X25519 keys
    final encryptResult = await _crypto.encrypt(
      plaintext: text,
      recipientPublicKey: recipientPublicKey,
      senderPrivateKey: _identity.encryptionPrivateKey!,
    );
    
    if (encryptResult.isFailure) {
      print('❌ Encryption failed: ${encryptResult.errorOrNull?.userMessage}');
      throw Exception('Failed to encrypt message: ${encryptResult.errorOrNull?.message}');
    }
    
    final ciphertext = encryptResult.valueOrNull!;

    // 3. Create message envelope with sender's X25519 public key
    final senderPublicKeyToSend = _identity.encryptionPublicKey!;
    print('🔑 Sending X25519 encryption public key (${senderPublicKeyToSend.length} bytes)');
    
    final nonceResult = _crypto.generateNonce();
    if (nonceResult.isFailure) {
      print('❌ Failed to generate nonce: ${nonceResult.errorOrNull?.userMessage}');
      throw Exception('Nonce generation failed');
    }
    
    final message = Message(
      id: _uuid.v4(),
      senderPeerID: _identity.peerID!,
      targetPeerID: recipientPeerID,
      timestamp: DateTime.now().toUtc(),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
      ciphertext: ciphertext,
      signature: Uint8List(0), // temp
      nonce: nonceResult.valueOrNull!,
      senderPublicKey: senderPublicKeyToSend, // Include 32-byte public key for decryption
      targetHomeNode: contact.connectedNodeMultiaddr, // Recipient's known home node for cross-node forwarding
      senderHomeNode: _activeBootstrapNode, // Our current node (self-healing routing)
      replyToMessageId: replyToMessageId,
      replyToPreviewText: replyToPreviewText,
      replyToContentType: replyToContentType,
      plaintext: text, // Keep locally
      isRead: true, // Own sent messages are already "read"
      deliveryStatus: DeliveryStatus.pending, // Start as pending
    );

    // 4. Sign
    print('🔐 Signing message:');
    print('   Signable data: ${message.signableData}');
    print('   Timestamp: ${message.timestamp.toIso8601String()}');
    print('   Unix seconds: ${message.timestamp.millisecondsSinceEpoch ~/ 1000}');
    
    final signResult = await _identity.sign(utf8.encode(message.signableData));
    if (signResult.isFailure) {
      print('❌ Failed to sign message: ${signResult.errorOrNull?.userMessage}');
      throw Exception('Signature failed');
    }
    final signature = signResult.valueOrNull!;
    print('   Signature length: ${signature.length} bytes');
    final signedMessage = message.copyWith(signature: signature);

    // 5. Save immediately with status=pending (before attempting to send!)
    // This ensures the message is preserved even if node is offline
    print('💾 Saving message locally before send...');
    final saveResult = await _storage.saveMessage(signedMessage);
    if (saveResult.isFailure) {
      print('⚠️ Failed to save message locally: ${saveResult.errorOrNull?.userMessage}');
      throw Exception('Failed to save message: ${saveResult.errorOrNull?.message}');
    }

    // 6. Try to send via relay (Store-and-Forward for mobile architecture)
    // Note: Direct P2P is skipped because mobile apps don't have incoming stream handlers
    // All messaging goes through Oasis Node Store/Retrieve protocol (instant!)
    print('📦 Attempting relay-based delivery (mobile architecture)');
    
    try {
      await _sendViaRelay(signedMessage);
      
      // Success! Update status to sent
      final sentMessage = signedMessage.copyWith(deliveryStatus: DeliveryStatus.sent);
      final updateResult = await _storage.saveMessage(sentMessage);
      if (updateResult.isFailure) {
        print('⚠️ Failed to update delivery status: ${updateResult.errorOrNull?.userMessage}');
      }
      print('✅ Message sent and status updated');
      
      // Trigger chat update so HomeScreen refreshes Chats tab
      triggerChatUpdate();
      
    } catch (e) {
      // Sending failed - message stays pending in local DB
      print('⚠️ Message send failed, keeping status=pending: $e');
      // Mark as failed status
      final failedMessage = signedMessage.copyWith(deliveryStatus: DeliveryStatus.failed);
      await _storage.saveMessage(failedMessage);
      
      // Still trigger update to show failed message in UI
      triggerChatUpdate();
      
      // Don't throw - message is saved, we can retry later
      rethrow; // But still propagate error to UI
    }
  }

  /// Retry sending messages that are pending or failed
  /// Called automatically when reconnecting to a node
  Future<void> retryPendingMessages() async {
    Logger.debug('Checking for pending/failed messages to retry...');
    
    // Get all messages from storage
    final allMessagesResult = await _storage.getAllMessages();
    if (allMessagesResult.isFailure) {
      Logger.warning('Failed to load messages for retry: ${allMessagesResult.errorOrNull?.message}');
      return;
    }
    
    final allMessages = allMessagesResult.valueOrNull ?? [];
    final pendingMessages = allMessages.where((msg) => 
      msg.deliveryStatus == DeliveryStatus.pending || 
      msg.deliveryStatus == DeliveryStatus.failed
    ).toList();
    
    if (pendingMessages.isEmpty) {
      Logger.debug('No pending messages to retry');
      return;
    }
    
    print('📤 Found ${pendingMessages.length} pending/failed messages, retrying...');
    
    int successCount = 0;
    int failCount = 0;
    
    for (final message in pendingMessages) {
      try {
        await _sendViaRelay(message);
        
        // Success! Update status to sent
        final sentMessage = message.copyWith(deliveryStatus: DeliveryStatus.sent);
        final updateResult = await _storage.saveMessage(sentMessage);
        if (updateResult.isSuccess) {
          successCount++;
          print('   ✅ Retry success: ${message.id}');
          
          // Clean up: Delete key exchange and profile update messages after successful send
          // (They're not real chat messages and shouldn't appear in chat history)
          try {
            final ciphertextStr = utf8.decode(message.ciphertext);
            if (ciphertextStr == 'KEY_EXCHANGE_REQUEST') {
              await _storage.deleteMessage(message.id);
              print('   🗑️ Cleaned up key exchange message from storage');
            }
          } catch (_) {
            // Ciphertext is encrypted, check contentType instead
            if (message.contentType == ContentType.profile_update) {
              await _storage.deleteMessage(message.id);
              print('   🗑️ Cleaned up profile update message from storage');
            }
          }
        }
      } catch (e) {
        // Still failed - keep as failed
        failCount++;
        print('   ⚠️ Retry failed: ${message.id} - $e');
        final failedMessage = message.copyWith(deliveryStatus: DeliveryStatus.failed);
        await _storage.saveMessage(failedMessage);
      }
    }
    
    print('📊 Retry summary: $successCount sent, $failCount failed');
  }

  /// Retry a single failed message
  /// Used when user taps on a failed message to retry manually
  Future<void> retrySingleMessage(Message message) async {
    print('🔄 Retrying single message: ${message.id}');
    
    try {
      // Update to pending first
      final pendingMessage = message.copyWith(deliveryStatus: DeliveryStatus.pending);
      await _storage.saveMessage(pendingMessage);
      
      // Try to send
      await _sendViaRelay(message);
      
      // Success! Update status to sent
      final sentMessage = message.copyWith(deliveryStatus: DeliveryStatus.sent);
      final updateResult = await _storage.saveMessage(sentMessage);
      if (updateResult.isSuccess) {
        print('   ✅ Retry success: ${message.id}');
      }
    } catch (e) {
      print('   ⚠️ Retry failed: ${message.id} - $e');
      // Mark as failed again
      final failedMessage = message.copyWith(deliveryStatus: DeliveryStatus.failed);
      await _storage.saveMessage(failedMessage);
      rethrow;
    }
  }

  /// Send via relay (Store protocol)
  /// Simple client-server: Uses only active bootstrap node
  Future<void> _sendViaRelay(Message message) async {
    print('📦 Storing message for offline delivery:');
    print('   From: ${message.senderPeerID}');
    print('   To: ${message.targetPeerID}');
    print('   Message ID: ${message.id}');

    // Simple client-server architecture: Use active node only
    if (_activeBootstrapNode == null) {
      throw Exception('No active Oasis Node connected.\n'
          'Possible causes:\n'
          '- Bootstrap nodes unreachable (check network/firewall)\n'
          '- Oasis Node server not running\n'
          '- Wrong IP address or port\n\n'
          'Try: Restart app when network is stable');
    }

    final activePeerID = extractPeerIDFromMultiaddr(_activeBootstrapNode!);
    print('✅ Using active bootstrap node: $activePeerID');

    // Try to store on active node
    try {
      print('📤 Storing message on active node: $activePeerID');
      
      final messageJson = message.toJson();
      
      final response = await _repository.sendToRelay(
        activePeerID,
        '/oasis-node/store/1.0.0',
        jsonEncode(messageJson),
      ).timeout(
        _config.dhtQueryTimeout,
        onTimeout: () {
          print('⏱️ Store timeout on $activePeerID');
          throw TimeoutException('Store request timeout after ${_config.dhtQueryTimeout.inSeconds}s');
        },
      );

      print('📥 Store response: $response');

      // Parse response
      final decoded = jsonDecode(response);
      
      if (decoded is Map<String, dynamic>) {
        if (decoded['status'] == 'stored' || decoded['success'] == true) {
          print('✅ Message stored successfully');
          _recordNodeSuccess(activePeerID);
          return;
        }
      } else if (decoded is List || response.isEmpty || response == 'null') {
        print('✅ Message stored successfully');
        _recordNodeSuccess(activePeerID);
        return;
      }
      
      throw Exception('Invalid store response');
    } catch (e) {
      print('❌ Failed to store on active node: $e');
      _recordNodeFailure(activePeerID);
      throw Exception('Failed to store message on active Oasis Node: $e');
    }
  }

  /// Start polling for messages
  void _startPolling() {
    // Automatic polling is now SAFE (no DHT queries, only direct node requests)
    // Adaptive: Fast polling (1s) during calls, normal polling (config) otherwise
    final interval = _fastPollingEnabled 
        ? const Duration(seconds: 1)  // Fast for calls
        : _config.messagePollingInterval;  // Normal polling
    
    if (_config.debugLogging) {
      print('📡 Starting automatic message polling (every ${interval.inSeconds}s, fast=${_fastPollingEnabled})');
    }
    
    _pollingTimer = Timer.periodic(interval, (_) {
      if (!_isPolling) {
        _pollMessages();
      }
    });
  }
  
  /// Enable fast polling (1s interval) for time-sensitive operations like calls
  /// Call this when initiating or receiving a call
  void enableFastPolling() {
    if (_fastPollingEnabled) return; // Already enabled
    
    Logger.info('⚡ Enabling fast polling (1s) for call signaling');
    _fastPollingEnabled = true;
    
    // Restart polling with new interval
    _pollingTimer?.cancel();
    _startPolling();
  }
  
  /// Disable fast polling, return to normal interval
  /// Call this when call ends or is established
  void disableFastPolling() {
    if (!_fastPollingEnabled) return; // Already disabled
    
    Logger.info('🔋 Disabling fast polling, returning to normal (${_config.messagePollingInterval.inSeconds}s)');
    _fastPollingEnabled = false;
    
    // Restart polling with normal interval
    _pollingTimer?.cancel();
    _startPolling();
  }
  
  /// Manually trigger message polling (call from UI on pull-to-refresh)
  Future<void> pollMessagesManually() async {
    print('🔄 Manual poll triggered (from CallService)');
    await _pollMessages();
  }

  /// Poll messages from active node only
  /// Simple client-server architecture - node handles all routing
  Future<void> _pollMessages() async {
    if (!_initialized) return;
    
    // Skip if identity not loaded yet (during reset)
    if (_identity.peerID == null) {
      return;
    }
    
    // Skip if already polling
    if (_isPolling) {
      print('⏳ Already polling, skipping...');
      return;
    }
    
    _isPolling = true;
    
    try {
      // Simple client-server architecture: Poll ONLY from active node
      // The node handles all routing, forwarding, and multi-node coordination
      if (_activeBootstrapNode == null) {
        print('⚠️ No active node connected');
        return;
      }

      final activePeerID = extractPeerIDFromMultiaddr(_activeBootstrapNode!);
      Logger.debug('Retrieving messages from active node: $activePeerID');

      try {
        final requestData = jsonEncode({'peer_id': _identity.peerID});
        
        final response = await _repository.sendToRelay(
          activePeerID,
          '/oasis-node/retrieve/1.0.0',
          requestData,
        ).timeout(
          _config.dhtQueryTimeout,
          onTimeout: () {
            print('⏱️ Timeout retrieving from $activePeerID');
            throw TimeoutException('Node retrieve timeout');
          },
        );

        // Record success for health tracking
        _recordNodeSuccess(activePeerID);

        // Parse response
        if (response.isEmpty || response == 'null') {
          return;
        }

        final decoded = jsonDecode(response);
        
        if (decoded == null || decoded is! List || decoded.isEmpty) {
          return;
        }

        // Sort messages: process Offers BEFORE ICE/Answer to ensure call exists when ICE arrives
        final messages = decoded
            .where((msgData) => msgData is Map<String, dynamic>)
            .map((msgData) => Message.fromJson(msgData as Map<String, dynamic>))
            .toList();
        
        // Separate call signals by type
        final offerMessages = <Message>[];
        final otherMessages = <Message>[];
        
        for (final message in messages) {
          if (message.contentType == ContentType.call_signal) {
            try {
              final signalJSON = utf8.decode(message.ciphertext);
              final signalData = jsonDecode(signalJSON) as Map<String, dynamic>;
              final signalType = signalData['signal_type'] as String?;
              
              if (signalType == 'offer') {
                offerMessages.add(message);
              } else {
                otherMessages.add(message);
              }
            } catch (e) {
              // If parsing fails, process normally
              otherMessages.add(message);
            }
          } else {
            otherMessages.add(message);
          }
        }
        
        // Process Offers first, then everything else
        final sortedMessages = [...offerMessages, ...otherMessages];
        
        print('ℹ️  📬 Retrieved from relay: ${sortedMessages.length} messages');
        if (offerMessages.isNotEmpty) {
          print('   📞 Processing ${offerMessages.length} Offer(s) first');
        }

        // Process messages in sorted order
        for (final message in sortedMessages) {
          await _processReceivedMessage(message, activePeerID);
        }
      } catch (e) {
        print('⚠️ Failed to poll from $activePeerID: $e');
        _recordNodeFailure(activePeerID); // Track failure for potential failover
      }
    } catch (e, stackTrace) {
      // Catch any unexpected errors to prevent app crash
      print('❌ Unexpected error during message polling: $e');
      if (_config.debugLogging) {
        print('Stack trace: $stackTrace');
      }
    } finally {
      _isPolling = false;
    }
  }

  /// Process received message
  Future<void> _processReceivedMessage(Message message, String nodePeerID) async {
    try {
      // 0. Check if this is a call signal (special case - skip signature/nonce verification)
      if (message.contentType == ContentType.call_signal) {
        print('📞 Received call signal from ${message.senderPeerID}');
        
        try {
          // Parse call signal JSON from ciphertext field
          final signalJSON = utf8.decode(message.ciphertext);
          final signalData = jsonDecode(signalJSON) as Map<String, dynamic>;
          
          print('   Signal type: ${signalData['signal_type']}');
          print('   Call ID: ${signalData['call_id']}');
          
          // Forward to CallService
          await _handleIncomingCallSignal(signalData);
          
          // Delete from relay
          await _deleteFromRelay(message.id, nodePeerID);
          
          print('✅ Call signal processed');
          return;
        } catch (e) {
          print('❌ Failed to process call signal: $e');
          return;
        }
      }

      // 1. Check nonce (replay protection)
      final nonceStr = base64Encode(message.nonce);
      final nonceResult = await _storage.hasSeenNonce(nonceStr);
      if (nonceResult.isFailure) {
        print('⚠️ Failed to check nonce: ${nonceResult.errorOrNull?.userMessage}');
        return;
      }
      
      if (nonceResult.valueOrNull == true) {
        print('⚠️ Duplicate message (nonce seen): ${message.id}');
        // Delete from relay to prevent endless polling of duplicates
        await _deleteFromRelay(message.id, nodePeerID);
        return;
      }

      // 2. Verify signature using libp2p's native verification
      print('🔐 Verifying message signature...');
      print('   Message ID: ${message.id}');
      print('   Sender PeerID: ${message.senderPeerID}');
      print('   Timestamp (ISO): ${message.timestamp.toIso8601String()}');
      print('   Timestamp (Unix): ${message.timestamp.toUtc().millisecondsSinceEpoch ~/ 1000}');
      print('   Signable data: ${message.signableData}');
      
      bool isValid;
      try {
        // Use libp2p's native P2P_Verify which is compatible with oasis_node
        isValid = await _repository.verify(
          peerID: message.senderPeerID,
          data: utf8.encode(message.signableData),
          signature: message.signature,
        );
      } catch (e) {
        print('❌ Signature verification error: $e');
        return;
      }
      
      if (!isValid) {
        print('❌ Invalid signature: ${message.id}');
        return;
      }
      print('✅ Signature verified with libp2p');
      
      // 2.5. Check if sender is blocked
      final senderContactResult = await _storage.getContact(message.senderPeerID);
      if (senderContactResult.isSuccess) {
        final senderContact = senderContactResult.valueOrNull;
        if (senderContact?.isBlocked == true) {
          print('🚫 Message from BLOCKED contact ${senderContact?.displayName ?? message.senderPeerID} - rejecting');
          await _deleteFromRelay(message.id, nodePeerID);
          return;
        }
      }

      // 2.6. Update sender's known node (self-healing routing)
      // If the sender embedded their current node, update our contact record.
      // This keeps connectedNodeMultiaddr fresh without requiring a new QR scan.
      if (message.senderHomeNode != null && message.senderHomeNode!.isNotEmpty) {
        try {
          final contactForUpdate = senderContactResult.valueOrNull;
          if (contactForUpdate != null &&
              contactForUpdate.connectedNodeMultiaddr != message.senderHomeNode) {
            final updatedContact = contactForUpdate.copyWith(
              connectedNodeMultiaddr: message.senderHomeNode,
            );
            await _storage.saveContact(updatedContact);
            print('🏠 Updated sender node: ${message.senderPeerID.substring(0, 12)} → ${message.senderHomeNode!.split('/').last}');
          }
        } catch (e) {
          print('⚠️ Failed to update sender home node in contact: $e');
          // Non-fatal
        }
      }

      // 3. Check if this is a block notification (special case)
      if (message.contentType == ContentType.block_notification) {
        print('🚫 Received block notification from ${message.senderPeerID}');
        
        try {
          final blockData = utf8.decode(message.ciphertext);
          if (blockData == 'BLOCK_NOTIFICATION') {
            print('   You have been blocked by this contact');
            
            // Mark the sender as having blocked us
            final contactResult = await _storage.getContact(message.senderPeerID);
            if (contactResult.isSuccess && contactResult.valueOrNull != null) {
              final contact = contactResult.valueOrNull!;
              final updatedContact = contact.copyWith(
                blockedByOther: true,
                blockedByOtherAt: DateTime.now().toUtc(),
              );
              await _storage.saveContact(updatedContact);
              print('✅ Contact marked as blockedByOther');
            }
            
            // Delete from relay and mark nonce
            await _deleteFromRelay(message.id, nodePeerID);
            final markResult = await _storage.markNonceSeen(nonceStr);
            if (markResult.isFailure) {
              print('⚠️ Failed to mark nonce as seen: ${markResult.errorOrNull?.userMessage}');
            }
            
            // Notify UI about block (will show banner in ChatScreen)
            _chatUpdateStreamController.add(null);
            
            print('✅ Block notification processed');
            return;
          }
        } catch (e) {
          print('❌ Failed to process block notification: $e');
          return;
        }
      }

      // 4. Auto-save sender's public key if available
      if (message.senderPublicKey != null) {
        print('🔑 Auto-saving sender X25519 public key to contact');
        await _updateContactPublicKey(message.senderPeerID, message.senderPublicKey!);
      }

      // 5. Check if this is a key exchange request (special case)
      try {
        final ciphertextStr = utf8.decode(message.ciphertext);
        if (ciphertextStr == 'KEY_EXCHANGE_REQUEST') {
          print('🔑 Received key exchange request from ${message.senderPeerID}');
          print('   X25519 public key stored, encryption now possible!');
          
          // Don't save as a message, just delete from relay
          await _deleteFromRelay(message.id, nodePeerID);
          final markResult = await _storage.markNonceSeen(nonceStr);
          if (markResult.isFailure) {
            print('⚠️ Failed to mark nonce as seen: ${markResult.errorOrNull?.userMessage}');
          }
          
          // Automatically send profile update to new contact
          // This sends our current profile (name + image) to them
          try {
            final prefs = await SharedPreferences.getInstance();
            final userName = prefs.getString('user_display_name') ?? 'User';
            final profileImagePath = prefs.getString('profile_image_path');
            
            print('🔄 Automatically sending profile update to new contact...');
            await sendProfileUpdateToContact(
              recipientPeerID: message.senderPeerID,
              userName: userName,
              profileImagePath: profileImagePath,
            );
            print('✅ Profile update sent');
          } catch (e) {
            print('⚠️ Failed to auto-send profile update: $e');
            // Non-fatal - continue
          }
          
          // Notify UI to refresh chat list (new contact created)
          _chatUpdateStreamController.add(null);
          
          print('✅ Key exchange completed with ${message.senderPeerID}');
          
          // Create local system message to show connection in chat
          await _createLocalSystemMessage(
            peerID: message.senderPeerID,
            text: '🔐 Encryption enabled - You can now send messages',
          );
          
          return;
        }
      } catch (e) {
        // Not a key exchange request, continue with normal decryption
      }

      // 5. Decrypt (for regular encrypted messages)
      // Use sender's X25519 encryption public key from message
      if (message.senderPublicKey == null) {
        throw Exception('Message missing sender X25519 public key');
      }
      
      final senderX25519PublicKey = message.senderPublicKey!;
      
      print('📥 Received sender X25519 public key from message');
      print('   Length: ${senderX25519PublicKey.length} bytes');
      print('   Key (base64): ${base64Encode(senderX25519PublicKey)}');
      
      if (senderX25519PublicKey.length != 32) {
        throw Exception('Invalid X25519 public key length: ${senderX25519PublicKey.length} (expected 32)');
      }
      
      print('🔓 Starting decryption...');
      print('   Own encryption private key length: ${_identity.encryptionPrivateKey?.length ?? 0} bytes');
      print('   Ciphertext length: ${message.ciphertext.length} bytes');
      
      final decryptResult = await _crypto.decrypt(
        ciphertext: message.ciphertext,
        senderPublicKey: senderX25519PublicKey,
        recipientPrivateKey: _identity.encryptionPrivateKey!,
      );
      
      if (decryptResult.isFailure) {
        print('❌ Decryption failed: ${decryptResult.errorOrNull?.userMessage}');
        return;
      }
      
      final plaintext = decryptResult.valueOrNull!;

      print('✅ Decryption successful!');

      // 6. Handle audio messages - decode base64 and save to temp file
      String finalPlaintext = plaintext;
      if (message.contentType == ContentType.audio) {
        try {
          print('🎵 Processing received audio message...');
          
          // Decode base64 audio data
          final audioBytes = base64Decode(plaintext);
          print('   Audio size: ${(audioBytes.length / 1024).round()}KB');
          
          // Save to persistent directory
          final appSupportDir = await getApplicationSupportDirectory();
          final audioDir = Directory('${appSupportDir.path}/audio');
          if (!await audioDir.exists()) {
            await audioDir.create(recursive: true);
          }
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final audioPath = '${audioDir.path}/received_audio_$timestamp.m4a';
          final audioFile = File(audioPath);
          await audioFile.writeAsBytes(audioBytes);
          
          print('   Saved to: $audioPath');
          
          // Store RELATIVE path (iOS container UUID changes on app restart)
          final relativePath = 'audio/received_audio_$timestamp.m4a';
          print('   Storing relative path: $relativePath');
          finalPlaintext = relativePath;
        } catch (e) {
          print('❌ Failed to decode audio: $e');
          finalPlaintext = '[Audio decoding failed]';
        }
      } else if (message.contentType == ContentType.image) {
        try {
          print('🖼️ Processing received image message...');
          
          // Decode base64 image data
          final imageBytes = base64Decode(plaintext);
          print('   Image size: ${(imageBytes.length / 1024).round()}KB');
          
          // Save to persistent directory
          final appSupportDir = await getApplicationSupportDirectory();
          final imageDir = Directory('${appSupportDir.path}/images/encrypted');
          if (!await imageDir.exists()) {
            await imageDir.create(recursive: true);
          }
          
          // Determine file extension from MIME type
          final mimeType = message.contentMeta?['mime_type'] ?? 'image/jpeg';
          final extension = mimeType.contains('png') ? 'png' 
              : mimeType.contains('gif') ? 'gif'
              : mimeType.contains('webp') ? 'webp'
              : 'jpg';
          
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final imagePath = '${imageDir.path}/received_img_$timestamp.$extension';
          final imageFile = File(imagePath);
          await imageFile.writeAsBytes(imageBytes);
          
          print('   Saved to: $imagePath');
          
          // Store RELATIVE path (iOS container UUID changes on app restart)
          final relativePath = 'images/encrypted/received_img_$timestamp.$extension';
          print('   Storing relative path: $relativePath');
          finalPlaintext = relativePath;
        } catch (e) {
          print('❌ Failed to decode image: $e');
          finalPlaintext = '[Image decoding failed]';
        }
      } else if (message.contentType == ContentType.profile_update) {
        try {
          print('👤 Processing received profile update...');
          
          // Parse profile JSON
          final profileData = jsonDecode(plaintext) as Map<String, dynamic>;
          final updatedName = profileData['name'] as String?;
          final profileImageBase64 = profileData['profile_image'] as String?;
          final imageMimeType = profileData['image_mime_type'] as String?;
          final imageDeleted = profileData['profile_image_deleted'] as bool? ?? false;
          
          print('   Updated name: $updatedName');
          print('   Has profile image: ${profileImageBase64 != null}');
          print('   Image deleted: $imageDeleted');
          
          String? savedImagePath;
          bool shouldUpdateImage = false;
          
          // Handle profile image deletion
          if (imageDeleted) {
            try {
              // Get current contact to find old image path
              final contactResult = await _storage.getContact(message.senderPeerID);
              final contact = contactResult.valueOrNull;
              
              if (contact?.profileImagePath != null && contact!.profileImagePath!.isNotEmpty) {
                // Delete old profile image file
                final appSupportDir = await getApplicationSupportDirectory();
                String fullPath;
                
                // Handle both absolute and relative paths
                if (contact.profileImagePath!.startsWith('/')) {
                  fullPath = contact.profileImagePath!;
                } else {
                  fullPath = '${appSupportDir.path}/${contact.profileImagePath}';
                }
                
                final oldImageFile = File(fullPath);
                if (await oldImageFile.exists()) {
                  await oldImageFile.delete();
                  print('   🗑️ Deleted old profile image: $fullPath');
                }
              }
              
              savedImagePath = null;  // Clear the image path
              shouldUpdateImage = true;
            } catch (e) {
              print('⚠️ Failed to delete old profile image: $e');
            }
          }
          // Save new profile image if present
          else if (profileImageBase64 != null && profileImageBase64.isNotEmpty) {
            try {
              final imageBytes = base64Decode(profileImageBase64);
              final imageSizeKB = (imageBytes.length / 1024).round();
              print('   Profile image size: ${imageSizeKB}KB');
              
              // First, delete old profile image if contact has one
              // This handles extension changes (JPG -> PNG) and Flutter FileImage cache issues
              final contactResult = await _storage.getContact(message.senderPeerID);
              final contact = contactResult.valueOrNull;
              
              if (contact?.profileImagePath != null && contact!.profileImagePath!.isNotEmpty) {
                try {
                  final appSupportDir = await getApplicationSupportDirectory();
                  String oldFullPath;
                  
                  // Handle both absolute and relative paths
                  if (contact.profileImagePath!.startsWith('/')) {
                    oldFullPath = contact.profileImagePath!;
                  } else {
                    oldFullPath = '${appSupportDir.path}/${contact.profileImagePath}';
                  }
                  
                  final oldImageFile = File(oldFullPath);
                  if (await oldImageFile.exists()) {
                    await oldImageFile.delete();
                    print('   🗑️ Deleted old profile image: $oldFullPath');
                  }
                } catch (e) {
                  print('⚠️ Failed to delete old profile image: $e');
                  // Continue anyway
                }
              }
              
              // Save to persistent directory
              final appSupportDir = await getApplicationSupportDirectory();
              final profileImageDir = Directory('${appSupportDir.path}/profile_images');
              if (!await profileImageDir.exists()) {
                await profileImageDir.create(recursive: true);
              }
              
              // Determine file extension
              final extension = imageMimeType?.contains('png') == true ? 'png' 
                  : imageMimeType?.contains('gif') == true ? 'gif'
                  : imageMimeType?.contains('webp') == true ? 'webp'
                  : 'jpg';
              
              // Use sender's peerID + timestamp in filename to avoid Flutter FileImage cache issues
              // When profile image is updated, new filename forces Flutter to reload from disk
              final sanitizedPeerID = message.senderPeerID.replaceAll(RegExp(r'[^\w\d]'), '_');
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final imagePath = '${profileImageDir.path}/profile_${sanitizedPeerID}_$timestamp.$extension';
              final imageFile = File(imagePath);
              
              await imageFile.writeAsBytes(imageBytes);
              print('   Saved profile image to: $imagePath');
              
              // Extract relative path (iOS container path changes on restart)
              // Store only: profile_images/profile_XXX.jpg instead of full path
              final relativePath = imagePath.replaceFirst('${appSupportDir.path}/', '');
              print('   Storing relative path: $relativePath');
              savedImagePath = relativePath;
              shouldUpdateImage = true;
            } catch (e) {
              print('⚠️ Failed to save profile image: $e');
            }
          }
          
          // Update contact with new profile info (only userName, keep displayName)
          if (updatedName != null || shouldUpdateImage) {
            final updateResult = await _storage.updateContactProfile(
              message.senderPeerID,
              userName: updatedName,  // Only update userName from profile updates
              profileImagePath: savedImagePath,
              updateImage: shouldUpdateImage,
            );
            
            if (updateResult.isSuccess) {
              print('✅ Updated contact profile (userName only)');
              
              // Notify UI to refresh
              _chatUpdateStreamController.add(null);
              
              // Auto-reply with own profile update if we haven't sent one yet
              // This ensures both sides exchange profile info after QR code scan
              try {
                // Check if we've already sent a profile update to this contact
                // Using contact flag for better performance (no getAllMessages() needed)
                final contactResult = await _storage.getContact(message.senderPeerID);
                final contact = contactResult.valueOrNull;
                final alreadySentUpdate = contact?.lastProfileUpdateSentAt != null;
                
                if (!alreadySentUpdate) {
                  print('🔄 Auto-replying with own profile update...');
                  final prefs = await SharedPreferences.getInstance();
                  final userName = prefs.getString('user_display_name') ?? 'User';
                  final profileImagePath = prefs.getString('profile_image_path');
                  
                  await sendProfileUpdateToContact(
                    recipientPeerID: message.senderPeerID,
                    userName: userName,
                    profileImagePath: profileImagePath,
                  );
                  print('✅ Profile update auto-reply sent');
                } else {
                  print('ℹ️ Already sent profile update to this contact, skipping auto-reply');
                }
              } catch (e) {
                print('⚠️ Failed to auto-reply with profile update: $e');
                // Non-fatal
              }
            } else {
              print('⚠️ Failed to update contact: ${updateResult.errorOrNull?.message}');
            }
          }
          
          // Set plaintext for message display
          finalPlaintext = '👤 ${updatedName ?? "Unknown"} updated their profile';
          
          // Don't show profile updates as regular messages in chat
          // Skip saving and just delete from relay
          await _deleteFromRelay(message.id, nodePeerID);
          final markResult = await _storage.markNonceSeen(nonceStr);
          if (markResult.isFailure) {
            print('⚠️ Failed to mark nonce as seen: ${markResult.errorOrNull?.userMessage}');
          }
          
          print('✅ Profile update processed');
          
          // Check if this is the first profile update (= key exchange just completed)
          // Create system message if no messages exist yet for this peer
          try {
            final existingMessagesResult = await _storage.getMessagesForPeer(message.senderPeerID);
            final existingMessages = existingMessagesResult.valueOrNull ?? [];
            
            if (existingMessages.isEmpty) {
              print('🆕 First profile update received - creating connection message');
              await _createLocalSystemMessage(
                peerID: message.senderPeerID,
                text: '🔐 Encryption enabled - You can now send messages',
              );
            }
          } catch (e) {
            print('⚠️ Could not check for first message: $e');
          }
          
          return; // Don't continue with normal message flow
          
        } catch (e) {
          print('❌ Failed to process profile update: $e');
          finalPlaintext = '[Profile update failed]';
        }
      } else {
        print('   Plaintext: "$plaintext"');
      }

      // 7. Update message with plaintext (file path for audio/image, text for messages)
      final decryptedMessage = message.copyWith(plaintext: finalPlaintext);

      // 7.5. If we receive a normal message from this contact, they are not blocking us anymore
      // Clear blockedByOther status
      try {
        final contactResult = await _storage.getContact(message.senderPeerID);
        if (contactResult.isSuccess && contactResult.valueOrNull != null) {
          final contact = contactResult.valueOrNull!;
          if (contact.blockedByOther == true) {
            print('📩 Received message from previously blocking contact, clearing blockedByOther status');
            final updatedContact = contact.copyWith(
              blockedByOther: false,
              blockedByOtherAt: null,
            );
            await _storage.saveContact(updatedContact);
            print('✅ blockedByOther cleared - contact is communicating again');
            
            // Notify UI to update
            _chatUpdateStreamController.add(null);
          }
        }
      } catch (e) {
        print('⚠️ Failed to clear blockedByOther status: $e');
        // Non-fatal, continue with message processing
      }

      // 8. Save locally
      final saveResult = await _storage.saveMessage(decryptedMessage);
      if (saveResult.isFailure) {
        print('⚠️ Failed to save message: ${saveResult.errorOrNull?.userMessage}');
      }
      
      final markResult = await _storage.markNonceSeen(nonceStr);
      if (markResult.isFailure) {
        print('⚠️ Failed to mark nonce: ${markResult.errorOrNull?.userMessage}');
      }

      // 8. Notify UI
      _messageStreamController.add(decryptedMessage);

      print('✅ Processed message: ${message.id}');

      // 9. Delete from relay
      await _deleteFromRelay(message.id, nodePeerID);

    } catch (e, stackTrace) {
      print('❌ Failed to process message ${message.id}: $e');
      print('   Stack trace: $stackTrace');
      // Don't save failed messages - they would show as [Encrypted]
    }
  }

  /// Delete message from relay node
  Future<void> _deleteFromRelay(String messageId, String nodePeerID) async {
    try {
      await _repository.sendToRelay(
        nodePeerID,
        '/oasis-node/delete/1.0.0',
        jsonEncode({
          'peer_id': _identity.peerID,
          'message_id': messageId,
        }),
      );
      print('🗑️ Deleted message $messageId from $nodePeerID');
    } catch (e) {
      print('⚠️ Failed to delete message from relay: $e');
    }
  }

  /// Create local system message (not sent to relay, only for UI)
  Future<void> _createLocalSystemMessage({
    required String peerID,
    required String text,
  }) async {
    try {
      final systemMessage = Message(
        id: 'system_${_uuid.v4()}',
        senderPeerID: _identity.peerID!,
        targetPeerID: peerID,
        timestamp: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 365)),
        ciphertext: Uint8List(0),
        signature: Uint8List(0),
        nonce: Uint8List(0),
        plaintext: text,
        contentType: ContentType.text,
        isRead: true,
        deliveryStatus: DeliveryStatus.delivered,
        networkId: _networkService?.activeNetworkId ?? 'public', // Network separation
      );
      
      await _storage.saveMessage(systemMessage);
      print('💬 Created local system message: $text');
      
      // Trigger UI update
      _chatUpdateStreamController.add(null);
    } catch (e) {
      print('⚠️ Failed to create system message: $e');
      // Non-fatal
    }
  }

  // ==================== CONTACTS ====================

  /// Add contact
  Future<void> addContact({
    required String peerID,
    required String name,
  }) async {
    final contact = Contact(
      peerID: peerID,
      displayName: name,  // Initially use provided name as display name
      userName: name,      // And as user name
      addedAt: DateTime.now(),
      networkId: _networkService?.activeNetworkId ?? 'public', // Network separation
    );
    final saveResult = await _storage.saveContact(contact);
    if (saveResult.isFailure) {
      throw Exception('Failed to save contact: ${saveResult.errorOrNull?.userMessage}');
    }
    print('✅ Contact added: $name ($peerID)');
    triggerChatUpdate();
  }

  /// Add contact with connected Oasis Node multiaddr
  /// This allows syncing healthy nodes from the contact's node
  Future<void> addContactWithNode({
    required String peerID,
    required String name,
    required String connectedNodeMultiaddr,
  }) async {
    final contact = Contact(
      peerID: peerID,
      displayName: name,  // Initially use provided name as display name
      userName: name,      // And as user name
      addedAt: DateTime.now(),
      connectedNodeMultiaddr: connectedNodeMultiaddr,
      networkId: _networkService?.activeNetworkId ?? 'public', // Network separation
    );
    final saveResult = await _storage.saveContact(contact);
    if (saveResult.isFailure) {
      throw Exception('Failed to save contact: ${saveResult.errorOrNull?.userMessage}');
    }
    print('✅ Contact added: $name ($peerID)');
    print('   Connected node: ${connectedNodeMultiaddr.split('/').last}');
    triggerChatUpdate();
  }

  /// Sync healthy nodes from contact's Oasis Node
  /// NOTE: No longer needed - app uses simple client-server model
  /// The connected node handles all routing internally
  /// This function is kept for backward compatibility but does nothing
  Future<int> syncNodesWithContact(String contactNodeMultiaddr) async {
    print('ℹ️ Node sync skipped - not needed (using single active node)');
    return 0; // No nodes synced, app doesn't need node discovery anymore
  }

  /// Get all contacts (excludes deleted contacts)
  Future<List<Contact>> getContacts() async {
    // Get contacts for active network only (network separation)
    final activeNetworkId = _networkService?.activeNetworkId ?? 'public';
    final result = await _storage.getContactsForNetwork(activeNetworkId);
    if (result.isFailure) {
      print('⚠️ Failed to get contacts: ${result.errorOrNull?.userMessage}');
      return [];
    }
    final allContacts = result.valueOrNull ?? [];
    
    // Filter out blocked contacts
    return allContacts.where((c) => !c.isBlocked).toList();
  }
  
  /// Block contact and send notification
  Future<void> blockContact(String peerID) async {
    final blockResult = await _storage.blockContact(peerID);
    if (blockResult.isFailure) {
      throw Exception('Failed to block contact: ${blockResult.errorOrNull?.userMessage}');
    }
    print('🚫 Contact blocked: $peerID');
    
    // Send block notification to the contact
    try {
      await _sendBlockNotification(peerID);
      print('✅ Block notification sent');
    } catch (e) {
      print('⚠️ Failed to send block notification (non-fatal): $e');
      // Non-fatal - contact is blocked locally anyway
    }
    
    // Trigger chat update to notify UI
    triggerChatUpdate();
  }
  
  /// Unblock contact
  Future<void> unblockContact(String peerID) async {
    final unblockResult = await _storage.unblockContact(peerID);
    if (unblockResult.isFailure) {
      throw Exception('Failed to unblock contact: ${unblockResult.errorOrNull?.userMessage}');
    }
    print('✅ Contact unblocked: $peerID');
    
    // Trigger chat update to notify UI
    triggerChatUpdate();
  }

  /// Send block notification to a contact
  /// Notifies them that they have been blocked
  Future<void> _sendBlockNotification(String recipientPeerID) async {
    try {
      print('🚫 Sending block notification to $recipientPeerID...');
      
      // Create simple block notification message
      final nonceResult = _crypto.generateNonce();
      if (nonceResult.isFailure) {
        throw Exception('Failed to generate nonce');
      }
      
      final message = Message(
        id: _uuid.v4(),
        senderPeerID: _identity.peerID!,
        targetPeerID: recipientPeerID,
        timestamp: DateTime.now().toUtc(),
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
        ciphertext: utf8.encode('BLOCK_NOTIFICATION'),
        signature: Uint8List(0), // temp, will be signed
        nonce: nonceResult.valueOrNull!,
        senderPublicKey: _identity.encryptionPublicKey,
        contentType: ContentType.block_notification,
      );
      
      // Sign the message
      final signResult = await _identity.sign(utf8.encode(message.signableData));
      if (signResult.isFailure) {
        throw Exception('Signing failed: ${signResult.errorOrNull?.message}');
      }
      
      final signedMessage = message.copyWith(signature: signResult.valueOrNull!);
      
      // Save before sending (for retry mechanism)
      final saveResult = await _storage.saveMessage(signedMessage);
      if (saveResult.isFailure) {
        throw Exception('Failed to save block notification: ${saveResult.errorOrNull?.userMessage}');
      }
      
      // Send via relay
      await _sendViaRelay(signedMessage);
      
      // Update status to sent
      final sentMessage = signedMessage.copyWith(deliveryStatus: DeliveryStatus.sent);
      await _storage.saveMessage(sentMessage);
      
      // Delete from storage (not a real chat message)
      await _storage.deleteMessage(sentMessage.id);
      
      print('✅ Block notification sent and cleaned up');
    } catch (e) {
      print('❌ Failed to send block notification: $e');
      rethrow;
    }
  }

  /// Check if a peer is online
  /// Returns multiaddress if online, null if offline
  Future<String?> checkPeerOnlineStatus(String peerID) async {
    try {
      final multiaddr = await _repository.findPeer(peerID);
      return multiaddr.isNotEmpty ? multiaddr : null;
    } catch (e) {
      print('⚠️ Error checking peer online status: $e');
      return null;
    }
  }

  // ==================== CHATS ====================

  /// Get all chats (grouped by contact)
  /// Excludes blocked contacts
  Future<List<Chat>> getChats() async {
    // Get active network ID for filtering (network separation)
    final activeNetworkId = _networkService?.activeNetworkId ?? 'public';
    
    // Get contacts for active network only
    final contactsResult = await _storage.getContactsForNetwork(activeNetworkId);
    if (contactsResult.isFailure) {
      print('⚠️ Failed to get contacts: ${contactsResult.errorOrNull?.userMessage}');
      return [];
    }
    final allContacts = contactsResult.valueOrNull ?? [];
    
    // Filter out blocked contacts - they appear in Blocked tab instead
    final contacts = allContacts.where((c) => !c.isBlocked).toList();
    
    // Get messages for active network only
    final allMessagesResult = await _storage.getMessagesForNetwork(activeNetworkId);
    if (allMessagesResult.isFailure) {
      print('⚠️ Failed to get messages: ${allMessagesResult.errorOrNull?.userMessage}');
      return [];
    }
    final allMessages = allMessagesResult.valueOrNull ?? [];
    
    final chats = <Chat>[];

    for (final contact in contacts) {
      // Get messages for this contact
      final messages = allMessages
          .where((m) =>
              m.senderPeerID == contact.peerID ||
              m.targetPeerID == contact.peerID)
          .toList();

      // Skip contacts without messages - they won't appear in Chats tab
      if (messages.isEmpty) {
        continue;
      }

      final lastMessage = messages.first; // Already sorted by timestamp
      final unreadCount = messages
          .where((m) => !m.isRead && m.senderPeerID == contact.peerID)
          .length;

      chats.add(Chat(
        peerID: contact.peerID,
        name: contact.displayName,
        lastMessage: lastMessage,
        unreadCount: unreadCount,
        lastActivity: lastMessage.timestamp,
      ));
    }

    // Sort by last activity
    chats.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
    return chats;
  }

  /// Get messages for specific chat
  Future<List<Message>> getMessagesForChat(String peerID) async {
    final result = await _storage.getMessagesForPeer(peerID);
    if (result.isFailure) {
      print('⚠️ Failed to get messages: ${result.errorOrNull?.userMessage}');
      return [];
    }
    return result.valueOrNull ?? [];
  }

  /// Mark chat as read
  Future<void> markChatAsRead(String peerID) async {
    final messagesResult = await _storage.getMessagesForPeer(peerID);
    if (messagesResult.isFailure) {
      print('⚠️ Failed to get messages: ${messagesResult.errorOrNull?.userMessage}');
      return;
    }
    
    final messages = messagesResult.valueOrNull ?? [];
    for (final message in messages) {
      if (!message.isRead && message.senderPeerID == peerID) {
        final markResult = await _storage.markAsRead(message.id);
        if (markResult.isFailure) {
          print('⚠️ Failed to mark message as read: ${markResult.errorOrNull?.userMessage}');
        }
      }
    }
  }

  // ==================== LIFECYCLE ====================

  /// Extract PeerID from multiaddr
  /// Converts "/ip4/172.16.10.10/tcp/4001/p2p/12D3KooW..." to "12D3KooW..."
  /// If input is already just a PeerID, returns it as-is
  String extractPeerIDFromMultiaddr(String multiaddr) {
    // If it doesn't contain slashes, it's probably already a PeerID
    if (!multiaddr.contains('/')) {
      return multiaddr;
    }
    
    // Split by /p2p/ to extract PeerID
    final parts = multiaddr.split('/p2p/');
    if (parts.length >= 2) {
      return parts[1].split('/')[0]; // Take first segment after /p2p/
    }
    
    // Fallback: try /ipfs/ (alternative format)
    final ipfsParts = multiaddr.split('/ipfs/');
    if (ipfsParts.length >= 2) {
      return ipfsParts[1].split('/')[0];
    }
    
    // Last resort: return original (might be already just a PeerID)
    return multiaddr;
  }

  /// Filter out invalid/problematic multiaddrs (localhost, link-local, etc)
  /// Returns true if multiaddr should be used, false if should be filtered out
  bool _isValidMultiaddr(String multiaddr) {
    // Filter out localhost addresses - only work on same device
    if (multiaddr.contains('/ip4/127.0.0.1/') || 
        multiaddr.contains('/ip6/::1/')) {
      return false;
    }
    
    // Filter out link-local IPv6 addresses (fe80::)
    if (multiaddr.contains('/ip6/fe80:')) {
      return false;
    }
    
    // Valid multiaddr
    return true;
  }

  /// Record successful request to a node (reset health score)
  void _recordNodeSuccess(String nodePeerID) {
    _nodeHealthScores[nodePeerID] = 0;
  }

  /// Record failed request to a node (increment failure count)
  /// Triggers failover if consecutive failures exceed threshold
  void _recordNodeFailure(String nodePeerID) {
    _nodeHealthScores[nodePeerID] = (_nodeHealthScores[nodePeerID] ?? 0) + 1;
    
    final failures = _nodeHealthScores[nodePeerID]!;
    if (_config.debugLogging) {
      print('⚠️ Node $nodePeerID failure count: $failures/$_maxConsecutiveFailures');
    }
    
    // Check if this is the active bootstrap node and needs failover
    if (_activeBootstrapNode != null && 
        extractPeerIDFromMultiaddr(_activeBootstrapNode!) == nodePeerID &&
        failures >= _maxConsecutiveFailures) {
      print('🔄 Active bootstrap node unhealthy, switching to fallback...');
      // Fire-and-forget: Don't block polling with failover connection attempts
      _switchToFallbackNode().catchError((e) {
        print('⚠️ Failover failed: $e');
        // Start reconnect timer as fallback
        _startBootstrapReconnectTimer();
      });
    }
  }

  /// Switch to next available bootstrap node (failover)
  Future<void> _switchToFallbackNode() async {
    if (_availableBootstrapNodes.length <= 1) {
      print('⚠️ No fallback nodes available');
      return;
    }
    
    // Remove current active node from pool temporarily
    final currentNode = _activeBootstrapNode;
    final remainingNodes = _availableBootstrapNodes.where((n) => n != currentNode).toList();
    
    // Try to connect to next available node
    for (final peer in remainingNodes) {
      try {
        await _repository.connectToRelay(peer).timeout(_config.connectionTimeout);
        
        print('✅ Switched to fallback node: ${peer.split('/').last}');
        _activeBootstrapNode = peer;
        _nodeHealthScores[extractPeerIDFromMultiaddr(peer)] = 0; // Reset health
        
        // Stop reconnect timer if running (we're connected now)
        _bootstrapReconnectTimer?.cancel();
        _bootstrapReconnectTimer = null;
        
        // Add old node back to pool for future failback
        if (currentNode != null && !_availableBootstrapNodes.contains(currentNode)) {
          _availableBootstrapNodes.add(currentNode);
        }
        
        return;
      } catch (e) {
        print('⚠️ Failover to ${peer.split('/').last} failed: $e');
        continue;
      }
    }
    
    print('❌ All fallback nodes unreachable');
  }

  /// Switch to a specific bootstrap node (e.g., after user adds new node via QR)
  /// Returns true if connection successful, false otherwise
  Future<bool> switchToBootstrapNode(String multiaddr) async {
    if (_config.debugLogging) {
      print('🔄 Attempting to switch to bootstrap node: ${multiaddr.split('/').last}');
    }
    
    try {
      // Try to connect to the specified node
      await _repository.connectToRelay(multiaddr).timeout(_config.connectionTimeout);
      
      // Success! Update active node
      final oldNode = _activeBootstrapNode;
      _activeBootstrapNode = multiaddr;
      
      // Initialize health score for new node
      final peerID = extractPeerIDFromMultiaddr(multiaddr);
      _nodeHealthScores[peerID] = 0;
      
      // Stop reconnect timer if running (we're connected now)
      _bootstrapReconnectTimer?.cancel();
      _bootstrapReconnectTimer = null;
      
      // Add to available nodes if not already there
      if (!_availableBootstrapNodes.contains(multiaddr)) {
        _availableBootstrapNodes.add(multiaddr);
      }
      
      if (_config.debugLogging) {
        print('✅ Successfully switched to new bootstrap node: ${multiaddr.split('/').last}');
        if (oldNode != null) {
          print('   Previous node: ${oldNode.split('/').last}');
        }
      }
      
      return true;
    } catch (e) {
      print('❌ Failed to switch to bootstrap node: $e');
      return false;
    }
  }

  /// Connect to a discovered Oasis Node via DHT routing
  /// 
  /// This method is used after auto-discovery to connect to found Oasis Nodes.
  /// Uses DHT-based routing with PeerID instead of full multiaddr.
  /// 
  /// IMPORTANT: This should be called AFTER IPFS bootstrap connection is established
  /// (IPFS is only used for DHT routing, NOT for message protocols).
  Future<bool> connectToDiscoveredNode(String peerID) async {
    print('🔄 Attempting to connect to discovered Oasis Node: $peerID');
    
    try {
      // Use DHT-based routing: /p2p/{peerID}
      // This allows connection without knowing the full multiaddr
      // (libp2p will use DHT to find the peer's addresses)
      final dhtMultiaddr = '/p2p/$peerID';
      
      await _repository.connectToRelay(dhtMultiaddr)
          .timeout(_config.connectionTimeout);
      
      // Success! Update active node to the Oasis Node
      final oldNode = _activeBootstrapNode;
      _activeBootstrapNode = dhtMultiaddr;
      
      // Initialize health score
      _nodeHealthScores[peerID] = 0;
      
      // Stop reconnect timer (we're connected to a real Oasis Node now)
      _bootstrapReconnectTimer?.cancel();
      _bootstrapReconnectTimer = null;
      
      // Add to available nodes for failover
      if (!_availableBootstrapNodes.contains(dhtMultiaddr)) {
        _availableBootstrapNodes.add(dhtMultiaddr);
      }
      
      print('✅ Successfully connected to discovered Oasis Node: $peerID');
      if (oldNode != null && oldNode.contains('bootstrap.libp2p.io')) {
        print('   Switched from IPFS Bootstrap → Oasis Node (correct architecture!)');
      }
      
      return true;
    } catch (e) {
      print('❌ Failed to connect to discovered node $peerID: $e');
      return false;
    }
  }

  /// Validate and register with a My Oasis Node before adding it
  /// 
  /// This performs a handshake with the node to verify:
  /// 1. The node is reachable
  /// 2. The node accepts this app's PeerID
  /// 3. The node has storage capacity
  /// 
  /// Returns node info (including node_name) if accepted
  /// Throws Exception if validation fails
  Future<Map<String, dynamic>> validateAndRegisterNode(String multiaddr) async {
    final nodePeerID = extractPeerIDFromMultiaddr(multiaddr);
    print('🔍 Validating My Oasis Node: $nodePeerID');
    
    // 1. Connect to node
    try {
      await _repository.connectToRelay(multiaddr).timeout(_config.connectionTimeout);
      print('✅ Connected to node');
    } catch (e) {
      throw Exception('Failed to connect to node: $e');
    }
    
    // 2. Send registration request
    final request = jsonEncode({
      'peer_id': _identity.peerID,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    
    print('📤 Sending registration request...');
    final response = await _repository.sendToRelay(
      nodePeerID,
      '/oasis-node/register/1.0.0',
      request,
    ).timeout(_config.dhtQueryTimeout);
    
    // 3. Parse response
    final decoded = jsonDecode(response) as Map<String, dynamic>;
    final status = decoded['status'] as String?;
    
    if (status == 'accepted') {
      print('✅ Node accepted registration');
      return {
        'node_name': decoded['node_name'] as String? ?? 'Oasis Node',
        'peer_id': nodePeerID,
      };
    } else {
      final reason = decoded['reason'] as String? ?? 'unknown';
      print('❌ Node rejected: $reason');
      throw Exception(_formatRejectionReason(reason));
    }
  }
  
  /// Unregister from an Oasis Node (when removing node from My Private Networks)
  /// This allows another user to register the node
  Future<void> unregisterFromNode(String multiaddr) async {
    final nodePeerID = extractPeerIDFromMultiaddr(multiaddr);
    print('🔓 Unregistering from My Private Networks: $nodePeerID');
    
    final userPeerID = _identity.peerID;
    if (userPeerID == null) {
      throw Exception('Identity not initialized');
    }
    
    try {
      // Add timeout to prevent UI hang if node is offline
      await _repository.unregisterPeer(nodePeerID, userPeerID)
          .timeout(const Duration(seconds: 3), onTimeout: () {
        print('⏱️ Unregister timeout (node offline?) - continuing anyway');
        throw TimeoutException('Node unregister timeout after 3s');
      });
      print('✅ Successfully unregistered from node');
    } catch (e) {
      print('⚠️ Failed to unregister from node: $e');
      // Don't throw - allow node removal even if unregistration fails
      // (e.g., node offline, already unregistered, etc.)
    }
  }
  
  /// Disconnect and remove node from all active connections
  /// Call this when deleting a node (Owner Node or Discovered Node)
  Future<void> disconnectAndRemoveNode(String multiaddr) async {
    final nodePeerID = extractPeerIDFromMultiaddr(multiaddr);
    print('🔌 Disconnecting and removing node: $nodePeerID');
    
    // 1. Remove from active bootstrap if it was active
    if (_activeBootstrapNode == multiaddr) {
      print('   ⚠️ Was active bootstrap node - clearing');
      _activeBootstrapNode = null;
      
      // Try to switch to another bootstrap node immediately (non-blocking)
      if (_availableBootstrapNodes.length > 1) {
        _switchToFallbackNode().catchError((e) {
          print('⚠️ Failover after node removal failed: $e');
          // Start reconnect timer as backup
          _startBootstrapReconnectTimer();
        });
      }
    }
    
    // 2. Remove from bootstrap list
    _availableBootstrapNodes.removeWhere((addr) => addr == multiaddr);
    
    // 3. Clear health score
    _nodeHealthScores.remove(nodePeerID);
    
    print('✅ Node completely disconnected and removed from memory');
  }
  
  /// Start automatic reconnect timer for bootstrap nodes
  /// Called when no bootstrap nodes are reachable at startup
  void _startBootstrapReconnectTimer() {
    // Cancel existing timer if any
    _bootstrapReconnectTimer?.cancel();
    
    // Try to reconnect every 30 seconds
    _bootstrapReconnectTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      // Skip if already connected
      if (_activeBootstrapNode != null) {
        if (_config.debugLogging) {
          print('✅ Node connected - stopping reconnect timer');
        }
        timer.cancel();
        _bootstrapReconnectTimer = null;
        return;
      }
      
      await _attemptBootstrapReconnect();
    });
    
    if (_config.debugLogging) {
      print('⏰ Reconnect timer started (30s interval)');
    }
  }
  
  /// Attempt to reconnect to any available bootstrap node
  Future<void> _attemptBootstrapReconnect() async {
    if (_availableBootstrapNodes.isEmpty) {
      print('⚠️ No nodes configured for reconnect');
      return;
    }
    
    if (_config.debugLogging) {
      print('🔄 Attempting reconnect (${_availableBootstrapNodes.length} nodes available)...');
    }
    
    // Try each node (My Private Networks have priority - they're first in list!)
    for (final peer in _availableBootstrapNodes) {
      try {
        await _repository.connectToRelay(peer)
          .timeout(_config.connectionTimeout);
        
        print('✅ Reconnected: ${peer.split('/').last}');
        _activeBootstrapNode = peer;
        _nodeHealthScores[extractPeerIDFromMultiaddr(peer)] = 0;
        
        // Stop reconnect timer - we're connected!
        _bootstrapReconnectTimer?.cancel();
        _bootstrapReconnectTimer = null;
        
        // Retry pending/failed messages now that we're connected (non-blocking!)
        retryPendingMessages().catchError((e) {
          print('⚠️ Background retry of pending messages failed: $e');
          // Non-fatal, messages stay pending for next retry
        });
        
        return; // Success!
      } catch (e) {
        if (_config.debugLogging) {
          print('   ⚠️ Failed: ${peer.split('/').last}');
        }
        continue;
      }
    }
    
    if (_config.debugLogging) {
      print('⚠️ Bootstrap reconnect failed - will retry in 30s');
    }
  }
  
  /// Format rejection reason for user-friendly error messages
  String _formatRejectionReason(String reason) {
    switch (reason) {
      case 'peer_already_registered':
        return 'This PeerID is already registered on this node';
      case 'node_already_owned':
        return 'This Oasis Node already belongs to another user. Each node can only be registered to one user.';
      case 'peer_id_mismatch':
        return 'PeerID verification failed';
      case 'not_whitelisted':
        return 'Your PeerID is not in the node\'s whitelist';
      case 'storage_full':
        return 'Node storage is full';
      case 'timestamp_expired':
        return 'Request expired - please try again';
      case 'invalid_request':
        return 'Invalid registration request';
      case 'invalid_peer_id':
        return 'Invalid PeerID format';
      case 'registration_failed':
        return 'Node failed to complete registration';
      default:
        return 'Registration rejected: $reason';
    }
  }

  /// Dispose resources
  /// Update contact with received X25519 encryption public key
  Future<void> _updateContactPublicKey(String peerID, Uint8List publicKey) async {
    try {
      // Validate X25519 key length
      if (publicKey.length != 32) {
        throw Exception('Invalid X25519 public key length: ${publicKey.length} (expected 32)');
      }
      
      // Get existing contact or create new one
      final contactResult = await _storage.getContact(peerID);
      if (contactResult.isFailure) {
        print('⚠️ Failed to get contact: ${contactResult.errorOrNull?.userMessage}');
        return;
      }
      
      Contact? contact = contactResult.valueOrNull;
      
      if (contact == null) {
        // Create new contact with the X25519 public key
        final defaultName = 'User ${peerID.substring(peerID.length - 8)}';
        contact = Contact(
          peerID: peerID,
          displayName: defaultName, // Use default as display name
          userName: defaultName,     // And as user name
          publicKey: publicKey,
          addedAt: DateTime.now().toUtc(),
        );
        print('📇 Creating new contact for $peerID with X25519 public key');
      } else if (contact.publicKey == null || 
                 !_listEquals(contact.publicKey!, publicKey)) {
        // Update existing contact with new/changed public key
        contact = contact.copyWith(
          publicKey: publicKey,
        );
        print('🔑 Updating X25519 public key for existing contact: ${contact.displayName}');
      } else {
        // Public key already matches, no update needed
        print('✅ X25519 public key already stored for: ${contact.displayName}');
        return;
      }
      
      final saveResult = await _storage.saveContact(contact);
      if (saveResult.isFailure) {
        print('⚠️ Failed to save contact: ${saveResult.errorOrNull?.userMessage}');
        return;
      }
      
      // Notify UI about contact update
      _chatUpdateStreamController.add(null);
    } catch (e) {
      print('❌ Failed to update contact public key: $e');
    }
  }

  /// Helper to compare two Uint8List
  bool _listEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Handle incoming call signal
  /// Forwards the signal to the CallService via stream
  Future<void> _handleIncomingCallSignal(Map<String, dynamic> signalData) async {
    try {
      print('📞 Forwarding call signal to CallService...');
      _callSignalStreamController.add(signalData);
    } catch (e) {
      print('❌ Failed to forward call signal: $e');
    }
  }

  /// Query DHT for a peer's multiaddresses
  /// 
  /// Used for transport pre-checking before connection attempts.
  /// Returns list of multiaddrs (e.g., ["/ip4/1.2.3.4/tcp/4001/p2p/Qm..."]).
  Future<List<String>?> dhtFindPeerAddresses(String peerID) async {
    try {
      // Call P2PBridge directly to get raw JSON result
      final P2PBridge bridge = P2PBridge();
      final result = await bridge.dhtFindPeer(peerID);
      
      // If null, peer not found
      if (result == null) {
        return null;
      }
      
      // Extract addresses from result map
      // Expected formats from Go backend:
      // 1. {"addrs": ["/ip4/...", "/ip6/..."], "peerID": "..."} (libp2p standard)
      // 2. {"addresses": ["/ip4/...", "/ip6/..."]} (alternative)
      // 3. {"multiaddr": "/ip4/1.2.3.4/tcp/4001"}  (single address)
      if (result.containsKey('addrs')) {
        final addrs = result['addrs'] as List?;
        return addrs?.cast<String>() ?? [];
      } else if (result.containsKey('addresses')) {
        final addrs = result['addresses'] as List?;
        return addrs?.cast<String>() ?? [];
      } else if (result.containsKey('multiaddr')) {
        final addr = result['multiaddr'] as String?;
        return addr != null ? [addr] : [];
      } else {
        print('⚠️  Unexpected DHT FindPeer result format: $result');
        return null;
      }
    } catch (e) {
      print('⚠️  Failed to query DHT for peer $peerID: $e');
      return null;
    }
  }

  Future<void> dispose() async {
    _pollingTimer?.cancel();
    _bootstrapReconnectTimer?.cancel();
    _bootstrapReconnectTimer = null;
    await _messageStreamController.close();
    await _chatUpdateStreamController.close();
    await _callSignalStreamController.close();
    await _repository.close();
    _initialized = false;
    print('👋 P2P Service disposed');
  }

  /// Get service status
  Map<String, dynamic> getStatus() {
    return _repository.getStatus();
  }
  
  /// Get detailed node information for debugging/settings UI
  /// Returns information about configured, connected, and cached nodes
  Map<String, dynamic> getNodeInfo() {
    return {
      // Configuration (from AppConfig)
      'bootstrap_nodes': _config.bootstrapNodes,
      'initial_oasis_nodes': _config.initialOasisNodes,
      'deprecated_peer_ids': _config.deprecatedPeerIDs,
      
      // Simple client-server architecture (single active node)
      'active_bootstrap_node': _activeBootstrapNode,
      'available_bootstrap_nodes': _availableBootstrapNodes,
      'node_health_scores': _nodeHealthScores,
      
      // Runtime status
      'connected_node': _activeBootstrapNode,
      
      // Config info
      'config_hash': _config.configHash,
      'environment': _config.environment.toString(),
    };
  }
  
  /// Query DHT for providers of a specific key
  /// 
  /// Used for automatic node discovery. Nodes announce themselves 
  /// with key "/oasis-node/nodes" in the DHT.
  Future<Result<List<String>, AppError>> dhtFindProviders(
    String key, {
    int maxProviders = 20,
  }) async {
    if (!_initialized) {
      return Failure(NetworkError(
        message: 'P2P service not initialized',
        type: NetworkErrorType.notInitialized,
      ));
    }
    
    try {
      print('🔍 Querying DHT for providers of "$key" (max: $maxProviders)...');
      
      final peerIDs = await _repository.findProviders(
        key,
        maxProviders,
      );
      
      if (peerIDs.isEmpty) {
        print('ℹ️  No providers found for "$key"');
      } else {
        print('✅ Found ${peerIDs.length} provider(s) for "$key"');
      }
      
      return Success(peerIDs);
    } catch (e) {
      print('❌ DHT query failed: $e');
      return Failure(NetworkError(
        message: 'DHT query failed: $e',
        type: NetworkErrorType.dhtQueryFailed,
      ));
    }
  }
}
