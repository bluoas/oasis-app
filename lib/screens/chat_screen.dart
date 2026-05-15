import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/services_provider.dart';
import '../services/p2p_service.dart';
import '../services/interfaces/i_identity_service.dart';
import '../services/interfaces/i_storage_service.dart';
import '../models/contact.dart';
import '../models/message.dart';
// TODO(coming-soon): re-enable when call feature ships
// import '../models/call.dart';
// import 'active_call_screen.dart';
import '../widgets/loading_state.dart';
import '../widgets/empty_state.dart';
import '../widgets/audio_recorder_button.dart';
import '../widgets/audio_message_bubble.dart';
import '../widgets/attachment_button.dart';
import '../widgets/image_message_bubble.dart';
import '../utils/top_notification.dart';
import '../utils/notification_utils.dart';
import '../utils/logger.dart';
import 'contact_detail_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String peerID;
  final String contactName;

  const ChatScreen({
    super.key,
    required this.peerID,
    required this.contactName,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> 
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _messageFocusNode = FocusNode();

  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<void>? _chatUpdateSubscription;
  
  List<Message> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _hasEncryptionKey = false;
  bool _hasText = false;
  bool _isRecording = false; // Track recording state
  Timer? _reloadDebounceTimer;
  Timer? _scrollDebounceTimer;
  bool _isReloading = false;
  
  // Cached contact profile image to avoid re-loading on every build
  File? _contactProfileImage;
  
  // Cached contact to access all contact properties including isKMNodeContact
  Contact? _contact;
  
  // Track if I am blocked by this contact
  bool _isBlockedByOther = false;
  
  // Selected images for preview before sending
  List<String> _selectedImages = [];

  // Pagination state
  int _currentPage = 0;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  static const int _pageSize = 50;
  
  // Show "scroll to bottom" button
  bool _showScrollToBottom = false;
  
  // Count of new messages received while user is scrolled up
  int _unreadNewMessageCount = 0;
  
  // Long-press context menu state (Phase 1: Basic tracking, Phase 2: Visual effects)
  Message? _selectedMessage;
  
  // Phase 2: Animation and Overlay state
  AnimationController? _scaleController;
  Animation<double>? _scaleAnimation;
  OverlayEntry? _backdropOverlay;
  OverlayEntry? _messageHighlightOverlay; // Renders selected message above blur
  OverlayEntry? _menuOverlay;
  
  // Phase 3: Dynamic positioning and Reply state
  final Map<String, GlobalKey> _messageKeys = {}; // Track GlobalKeys for each message
  Message? _replyToMessage; // Message being replied to
  Offset? _selectedMessagePosition; // Position of selected message for menu placement
  Size? _selectedMessageSize; // Size for overlay rendering
  
  // Phase 4: Edge case handling
  double _lastKeyboardHeight = 0; // Track keyboard state to detect changes
  Size? _lastScreenSize; // Track screen size to detect rotation
  
  // Reply navigation: Scroll to and highlight replied message
  String? _highlightedMessageId; // ID of message to highlight temporarily
  AnimationController? _highlightController; // Animation for smooth highlight fade
  Animation<double>? _highlightAnimation; // Opacity animation (fade in/out)

  // Getter for services from Riverpod providers
  P2PService get _p2pService => ref.read(p2pServiceProvider);
  IIdentityService get _identityService => ref.read(identityServiceProvider);
  IStorageService get _storageService => ref.read(storageServiceProvider);

  @override
  void initState() {
    super.initState();
    
    // Initialize scale animation for message selection (Phase 2)
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _scaleController!, curve: Curves.easeOut),
    );
    
    // Initialize highlight animation for reply navigation
    _highlightController = AnimationController(
      duration: const Duration(milliseconds: 2000), // Total duration: fade in + hold + fade out
      vsync: this,
    );
    _highlightAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 10, // 200ms fade in (10% of 2000ms)
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 65, // 1300ms hold (65% of 2000ms)
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 25, // 500ms fade out (25% of 2000ms)
      ),
    ]).animate(_highlightController!);
    
    // Listen to animation completion to clear highlighted message
    _highlightController!.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _highlightedMessageId = null;
        });
        _highlightController!.reset();
      }
    });
    
    // Rebuild during animation to update highlight opacity
    _highlightAnimation!.addListener(() {
      if (mounted) setState(() {});
    });
    
    _checkEncryptionKey();
    _loadMessages(isInitialLoad: true);
    _markAsRead();
    _listenToNewMessages();
    _listenToChatUpdates();
    _loadContactProfileImage(); // Load profile image once
    _loadContactName(); // Load contact name once
    
    // Listen to scroll position for infinite scroll
    _scrollController.addListener(_onScroll);
    
    // Listen to text changes
    _messageController.addListener(() {
      final hasText = _messageController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
    
    // Phase 4: Listen to device metrics changes (rotation, keyboard)
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize screen size tracking
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _lastScreenSize = MediaQuery.of(context).size;
      }
    });
  }
  


  Future<void> _checkEncryptionKey() async {
    final result = await _storageService.getContact(widget.peerID);
    final contact = result.valueOrNull;
    if (mounted) {
      setState(() {
        _hasEncryptionKey = contact?.publicKey != null && contact!.publicKey!.length == 32;
        _isBlockedByOther = contact?.blockedByOther ?? false;
      });
    }
  }

  /// Get contact's profile image file, reconstructing path if needed
  Future<File?> _getContactProfileImage(String peerID) async {
    try {
      final result = await _storageService.getContact(peerID);
      final contact = result.valueOrNull;
      final profileImagePath = contact?.profileImagePath;
      
      if (profileImagePath == null || profileImagePath.isEmpty) {
        return null;
      }
      
      File imageFile;
      
      // Handle both absolute paths and relative paths (iOS container changes)
      if (profileImagePath.startsWith('/')) {
        // Absolute path - use directly
        imageFile = File(profileImagePath);
      } else {
        // Relative path - reconstruct full path from ApplicationSupportDirectory
        final appSupportDir = await getApplicationSupportDirectory();
        final fullPath = '${appSupportDir.path}/$profileImagePath';
        imageFile = File(fullPath);
      }
      
      // Only return if file exists
      if (await imageFile.exists()) {
        return imageFile;
      }
      
      return null;
    } catch (e) {
      Logger.warning('Error loading contact profile image: $e');
      return null;
    }
  }
  
  /// Load and cache contact profile image
  Future<void> _loadContactProfileImage() async {
    final imageFile = await _getContactProfileImage(widget.peerID);
    if (mounted) {
      setState(() {
        _contactProfileImage = imageFile;
      });
    }
  }
  
  Future<void> _loadContactName() async {
    final contactResult = await _storageService.getContact(widget.peerID);
    if (mounted && contactResult.isSuccess) {
      setState(() {
        _contact = contactResult.value;
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    
    final position = _scrollController.position;
    
    // Check if user is at bottom (within 100px threshold)
    final isAtBottom = (position.maxScrollExtent - position.pixels) < 100;
    
    // Update scroll-to-bottom button visibility and reset counter if at bottom
    if (isAtBottom != !_showScrollToBottom) {
      final hadUnreadMessages = _unreadNewMessageCount > 0;
      setState(() {
        _showScrollToBottom = !isAtBottom;
        // Reset unread counter when user scrolls to bottom manually
        if (isAtBottom) {
          _unreadNewMessageCount = 0;
        }
      });
      // Mark messages as read when user scrolls to bottom manually
      if (isAtBottom && hadUnreadMessages) {
        _markAsRead();
      }
    }
    
    // Debounce scroll events to prevent rapid firing
    _scrollDebounceTimer?.cancel();
    _scrollDebounceTimer = Timer(const Duration(milliseconds: 100), () {
      if (!mounted || !_scrollController.hasClients) return;
      
      // Load more when scrolling near the top (20% threshold)
      final position = _scrollController.position;
      if (position.pixels <= position.minScrollExtent + 200) {
        if (!_isLoadingMore && _hasMore) {
          _loadMoreMessages();
        }
      }
    });
  }

  void _loadMessages({bool isInitialLoad = false}) async {
    // Debounce - don't reload if already reloading
    if (_isReloading) return;
    
    _isReloading = true;
    
    try {
      if (!mounted) return;
      
      // Check if user is at bottom before loading
      final isAtBottom = !_scrollController.hasClients || 
                         (_scrollController.position.maxScrollExtent - _scrollController.position.pixels) < 100;
      
      // Store old messages to detect new ones from peer
      final oldMessages = List<Message>.from(_messages);
      
      // Only show loading on first load
      if (_messages.isEmpty && mounted) {
        setState(() => _loading = true);
      }
      
      // Load first page with pagination
      final result = await _storageService.getMessagesForPeerPaginated(
        widget.peerID,
        page: 0,
        pageSize: _pageSize,
      );
      
      if (!mounted) return;
      
      final paginatedResult = result.valueOrNull;
      if (paginatedResult != null) {
        final newMessages = paginatedResult.items.reversed.toList();
        
        // Count only new messages from peer (not from me)
        int newPeerMessageCount = 0;
        if (!isAtBottom && !isInitialLoad) {
          final oldMessageIds = oldMessages.map((m) => m.id).toSet();
          for (final msg in newMessages) {
            // Only count if message is new AND from peer (not from me)
            if (!oldMessageIds.contains(msg.id) && msg.senderPeerID == widget.peerID) {
              newPeerMessageCount++;
            }
          }
        }
        
        setState(() {
          _messages = newMessages; // Show oldest first
          _currentPage = 0;
          _hasMore = paginatedResult.hasMore;
          _loading = false;
          
          // Increment counter only for new messages from peer
          if (newPeerMessageCount > 0) {
            _unreadNewMessageCount += newPeerMessageCount;
          }
        });
        
        // Only auto-scroll if user was already at bottom or it's initial load
        if (isAtBottom || isInitialLoad) {
          // For initial load, add extra delay to ensure ListView is fully rendered
          if (isInitialLoad) {
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) _scrollToBottom();
            });
          } else {
            _scrollToBottom();
            // Mark messages as read immediately when user is at bottom
            // (prevents showing unread count in home screen for actively viewed chats)
            _markAsRead();
          }
        }
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      Logger.error('Error loading messages', e);
      if (!mounted) return;
      setState(() => _loading = false);
    } finally {
      _isReloading = false;
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore) return;
    
    setState(() => _isLoadingMore = true);
    
    try {
      final nextPage = _currentPage + 1;
      
      final result = await _storageService.getMessagesForPeerPaginated(
        widget.peerID,
        page: nextPage,
        pageSize: _pageSize,
      );
      
      if (!mounted) return;
      
      final paginatedResult = result.valueOrNull;
      if (paginatedResult != null) {
        // Keep current scroll position
        final currentScrollPos = _scrollController.position.pixels;
        final currentMaxScrollExtent = _scrollController.position.maxScrollExtent;
        
        setState(() {
          // Insert older messages at the beginning
          _messages.insertAll(
            0,
            paginatedResult.items.reversed.toList(),
          );
          _currentPage = nextPage;
          _hasMore = paginatedResult.hasMore;
        });
        
        // Restore scroll position (accounting for new content height)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final newMaxScrollExtent = _scrollController.position.maxScrollExtent;
            final scrollDelta = newMaxScrollExtent - currentMaxScrollExtent;
            _scrollController.jumpTo(currentScrollPos + scrollDelta);
          }
        });
      }
    } catch (e) {
      Logger.error('Error loading more messages', e);
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _markAsRead() async {
    await _p2pService.markChatAsRead(widget.peerID);
  }

  /// Try reconnecting - sends test message to check if still blocked
  /// Rate limited to once per 5 minutes to prevent spam
  Future<void> _tryReconnecting() async {
    if (!mounted) return;
    
    // Check rate limiting (5 minutes cooldown)
    final contactResult = await _storageService.getContact(widget.peerID);
    if (contactResult.isSuccess && contactResult.valueOrNull != null) {
      final contact = contactResult.valueOrNull!;
      if (contact.lastReconnectAttemptAt != null) {
        final timeSinceLastAttempt = DateTime.now().difference(contact.lastReconnectAttemptAt!);
        const cooldownDuration = Duration(hours: 24);
        
        if (timeSinceLastAttempt < cooldownDuration) {
          final remainingHours = (cooldownDuration - timeSinceLastAttempt).inHours + 1;
          showTopNotification(
            context,
            'You can only try reconnecting once per day. Please wait $remainingHours more hour${remainingHours != 1 ? 's' : ''}',
            isError: true,
          );
          return;
        }
      }
    }
    
    setState(() => _sending = true);
    
    try {
      // Send a simple test message
      await _p2pService.sendMessage(
        recipientPeerID: widget.peerID,
        text: '👋', // Simple wave emoji as reconnection test
      );
      
      // Message sent successfully (stored locally)
      if (!mounted) return;
      
      // Update lastReconnectAttemptAt timestamp
      final contactResult = await _storageService.getContact(widget.peerID);
      if (contactResult.isSuccess && contactResult.valueOrNull != null) {
        final contact = contactResult.valueOrNull!;
        final updatedContact = contact.copyWith(
          lastReconnectAttemptAt: DateTime.now(),
        );
        await _storageService.saveContact(updatedContact);
      }
      
      // Reload messages to show sent message
      _loadMessages();
      
      showTopNotification(
        context,
        '👋 Test message sent. If they respond, you\'ll know they unblocked you.',
      );
    } catch (e) {
      Logger.error('Failed to send test message', e);
      if (!mounted) return;
      
      showTopNotification(
        context,
        'Failed to send message',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _listenToNewMessages() {
    _messageSubscription = _p2pService.messageStream.listen((message) async {
      if (message.senderPeerID == widget.peerID ||
          message.targetPeerID == widget.peerID) {
        // Trigger vibration and sound for incoming messages from this peer
        if (message.senderPeerID == widget.peerID) {
          try {
            await NotificationUtils.notifyIncomingMessage();
          } catch (e) {
            // Silently ignore notification errors
          }
        }
        
        // Debounced reload - max once per 300ms
        _reloadDebounceTimer?.cancel();
        _reloadDebounceTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted) {
            _checkEncryptionKey();
            _loadMessages();
          }
        });
      }
    });
  }

  void _listenToChatUpdates() {
    // Listen to chat updates (e.g., profile changes, chat cleaned)
    _chatUpdateSubscription = _p2pService.chatUpdateStream.listen((_) {
      if (mounted) {
        // Reload profile image when updates occur
        _loadContactProfileImage();
        // Reload contact name when updates occur
        _loadContactName();
        // Reload contact deleted status
        _checkEncryptionKey();
        // Also reload messages (e.g., when chat is cleaned)
        _loadMessages();
      }
    });
  }

  void _scrollToBottom() {
    if (!mounted || !_scrollController.hasClients) return;
    
    final maxScroll = _scrollController.position.maxScrollExtent;
    final hadUnreadMessages = _unreadNewMessageCount > 0;
    
    // Scroll immediately to bottom
    _scrollController.animateTo(
      maxScroll,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    
    // Reset unread counter after animation starts (don't block the scroll)
    if (hadUnreadMessages) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          setState(() {
            _unreadNewMessageCount = 0;
          });
          _markAsRead();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ContactDetailScreen(peerID: widget.peerID),
                ),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  backgroundImage: (_contactProfileImage != null)
                      ? FileImage(_contactProfileImage!)
                      : null,
                  child: (_contactProfileImage == null)
                      ? Text(
                          widget.contactName.isNotEmpty ? widget.contactName[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Text(_contact?.displayName ?? widget.contactName),
              ],
            ),
          ),
          centerTitle: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          actions: [
            // TODO(coming-soon): Audio call button — re-enable when call feature ships
            // if (_hasEncryptionKey && !_isBlockedByOther)
            //   IconButton(
            //     icon: const Icon(Icons.call),
            //     tooltip: 'Audio Call',
            //     onPressed: () => _initiateCall(context),
            //   ),
          ],
        ),
        body: Column(
        children: [
          if (_isBlockedByOther) _buildBlockedByOtherNotice(),
          if (!_hasEncryptionKey && !_isBlockedByOther) _buildKeyExchangeNotice(),
          Expanded(
            child: _loading
                ? const LoadingState(message: 'Loading messages...')
                : _messages.isEmpty
                    ? const EmptyState(
                        message: 'No messages yet',
                        subtitle: 'Send the first message!',
                        icon: Icons.chat_outlined,
                      )
                    : _buildMessageList(),
          ),
          _buildMessageInput(),
        ],
      ),
      floatingActionButton: _showScrollToBottom
          ? GestureDetector(
              behavior: HitTestBehavior.opaque, // Prevent tap from propagating
              onTap: _scrollToBottom,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.arrow_downward,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 18,
                    ),
                  ),
                  // Badge showing unread message count
                  if (_unreadNewMessageCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          _unreadNewMessageCount > 99 ? '99+' : '$_unreadNewMessageCount',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            )
          : null,
      floatingActionButtonLocation: const _CustomFabLocation(),
    );
  }



  Widget _buildBlockedByOtherNotice() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50]!.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.block, color: Colors.red[900], size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You Have Been Blocked',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red[900],
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This contact may have blocked you. Messages and calls are currently disabled.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red[800],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _tryReconnecting,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Reconnecting'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyExchangeNotice() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade50,
            Colors.blue.shade100,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade200.withOpacity(0.5),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade500,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.key,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting for key exchange...',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Encryption keys are being exchanged with ${widget.contactName}. Messages will be encrypted once the exchange is complete.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue.shade800,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent, // Only intercept taps on empty areas, not on children
      onTap: () {
        // Dismiss keyboard when tapping on message list
        FocusScope.of(context).unfocus();
      },
      child: ListView.builder(
        controller: _scrollController,
      physics: const ClampingScrollPhysics(), // Prevent iOS bounce at edges
      padding: const EdgeInsets.all(8),
      itemCount: _messages.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Show loading indicator at the top when loading more
        if (index == 0 && _isLoadingMore) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(
              child: InlineLoadingIndicator(
                size: 24,
              ),
            ),
          );
        }
        
        // Adjust index if loading indicator is present
        final messageIndex = _isLoadingMore ? index - 1 : index;
        final message = _messages[messageIndex];
        final isMe = message.senderPeerID == _identityService.peerID;
        
        // Check if this is a system message
        final isSystemMessage = message.id.startsWith('system_');

        // Check if we need to show a date header
        bool showDateHeader = false;
        if (messageIndex == 0) {
          // Always show header for first message
          showDateHeader = true;
        } else {
          // Show header if date changed from previous message
          final previousMessage = _messages[messageIndex - 1];
          if (!_isSameDay(previousMessage.timestamp, message.timestamp)) {
            showDateHeader = true;
          }
        }

        // Build the message widget based on content type
        Widget messageWidget;
        
        // Render system messages (centered, special style)
        if (isSystemMessage) {
          messageWidget = Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50.withOpacity(0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.blue.shade200,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message.plaintext ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Render audio messages with AudioMessageBubble
        else if (message.contentType == ContentType.audio) {
          // Parse waveform data if available
          List<double>? waveform;
          final waveformJson = message.contentMeta?['waveform'];
          if (waveformJson != null) {
            try {
              final decoded = jsonDecode(waveformJson);
              if (decoded is List) {
                waveform = decoded.map((e) => (e as num).toDouble()).toList();
              }
            } catch (e) {
              // Ignore parsing errors, waveform will remain null
            }
          }
          
          messageWidget = Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: AudioMessageBubble(
                audioPath: message.plaintext ?? '', // Decrypted audio file path
                duration: Duration(
                  seconds: int.tryParse(message.contentMeta?['duration'] ?? '0') ?? 0,
                ),
                timestamp: message.timestamp,
                isMe: isMe,
                deliveryStatus: message.deliveryStatus,
                waveform: waveform,
                replyToMessageId: message.replyToMessageId,
                replyToPreviewText: message.replyToPreviewText,
                replyToContentType: message.replyToContentType?.name,
                replyToSenderName: message.replyToMessageId != null ? _getReplyToSenderName(message.replyToMessageId!) : null,
                isHighlighted: _highlightedMessageId == message.id,
                highlightOpacity: _getHighlightOpacity(message.id),
                onReplyTap: message.replyToMessageId != null 
                    ? () => _scrollToAndHighlightMessage(message.replyToMessageId!) 
                    : null,
                onLongPress: () => _onMessageLongPress(message),
                onPlayError: () {
                  // Handle playback error
                  showTopNotification(
                    context,
                    'Could not play audio message',
                    duration: const Duration(seconds: 2),
                    isError: true,
                  );
                },
              ),
            ),
          );
        }

        // Render image messages
        else if (message.contentType == ContentType.image) {
          final caption = message.contentMeta?['caption'];
          
          messageWidget = ImageMessageBubble(
            messageId: message.id,
            imagePath: _resolveImagePath(message.plaintext ?? ''),
            timestamp: message.timestamp,
            isMe: isMe,
            senderName: isMe ? 'You' : widget.contactName,
            deliveryStatus: message.deliveryStatus,
            caption: caption,
            replyToMessageId: message.replyToMessageId,
            replyToPreviewText: message.replyToPreviewText,
            replyToContentType: message.replyToContentType?.name,
            replyToSenderName: message.replyToMessageId != null ? _getReplyToSenderName(message.replyToMessageId!) : null,
            isHighlighted: _highlightedMessageId == message.id,
            highlightOpacity: _getHighlightOpacity(message.id),
            onReplyTap: message.replyToMessageId != null 
                ? () => _scrollToAndHighlightMessage(message.replyToMessageId!) 
                : null,
            onLongPress: () => _onMessageLongPress(message),
            onLoadError: () {
              showTopNotification(
                context,
                'Failed to load image',
                duration: const Duration(seconds: 2),
                isError: true,
              );
            },
          );
        }

        // Render text messages (existing logic)
        else {
          messageWidget = Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: GestureDetector(
              onTap: isMe && message.deliveryStatus == DeliveryStatus.failed
                  ? () => _retryFailedMessage(message)
                  : null,
              onLongPress: () => _onMessageLongPress(message),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                decoration: BoxDecoration(
                  color: () {
                    final highlightOpacity = _getHighlightOpacity(message.id);
                    if (highlightOpacity > 0) {
                      final highlightColor = Theme.of(context).brightness == Brightness.dark
                          ? Colors.amber
                          : Colors.orange[200]!;
                      return highlightColor.withOpacity(0.3 * highlightOpacity);
                    }
                    return isMe
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                        : (Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[800]!.withOpacity(0.3)
                            : Colors.grey[400]!.withOpacity(0.2));
                  }(),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 16),
                  ),
                  border: Border.all(
                    color: isMe
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                        : (Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[600]!.withOpacity(0.3)
                            : Colors.grey[400]!.withOpacity(0.3)),
                    width: 1,
                  ),
                ),
              child: IntrinsicWidth(
                child: Column(
                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, // Make bubble fit content dynamically
                  children: [
                    // Reply indicator (if replying to another message)
                    if (message.replyToMessageId != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _buildReplyIndicator(message)!,
                      ),
                    Linkify(
                      onOpen: (link) async {
                        final uri = Uri.parse(link.url);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      text: message.plaintext ?? '[Encrypted]',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87,
                      ),
                      linkStyle: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  const SizedBox(height: 4),
                  // Timestamp row - always align to right
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('HH:mm').format(message.timestamp.toLocal()),
                          style: TextStyle(
                            fontSize: 10,
                            color: (Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : Colors.black87).withOpacity(0.7),
                          ),
                        ),
                      if (isMe && message.deliveryStatus == DeliveryStatus.sent) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.check,
                          size: 14,
                          color: (Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black87).withOpacity(0.7),
                        ),
                      ],
                    ],
                  ),
                  ),
                  // Show delivery status for sent messages (pending/failed)
                  if (isMe && message.deliveryStatus != DeliveryStatus.sent) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          message.deliveryStatus == DeliveryStatus.pending
                              ? Icons.schedule
                              : Icons.warning,
                          size: 12,
                          color: message.deliveryStatus == DeliveryStatus.pending
                              ? (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white
                                  : Colors.black87).withOpacity(0.7)
                              : Colors.orange,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          message.deliveryStatus == DeliveryStatus.pending
                              ? 'Sending...'
                              : 'Failed - Tap to retry',
                          style: TextStyle(
                            fontSize: 10,
                            color: (Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.black87).withOpacity(0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          ),
        );
        }

        // Phase 3: Create or retrieve GlobalKey for this message
        final messageKey = _messageKeys.putIfAbsent(
          message.id,
          () => GlobalKey(),
        );

        // Wrap message - hide when selected (shown in overlay above blur)
        final isSelected = _selectedMessage?.id == message.id;
        final wrappedMessage = Container(
          key: messageKey,
          child: Opacity(
            opacity: isSelected ? 0.0 : 1.0,
            child: messageWidget,
          ),
        );

        // Return with or without date header
        if (showDateHeader) {
          return Column(
            children: [
              _buildDateHeader(_formatDateHeader(message.timestamp)),
              wrappedMessage,
            ],
          );
        } else {
          return wrappedMessage;
        }
      },
    ),
    );
  }

  Widget _buildMessageInput() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // Show blocked message if blocked by other user
    if (_isBlockedByOther) {
      return Container(
        margin: EdgeInsets.fromLTRB(16, 8, 16, 8 + bottomPadding),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red[100],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.red[700], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Try reconnecting with button above',
                style: TextStyle(
                  color: Colors.red[900],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottomPadding),
      child: _isRecording
          ? // Full-width recording UI when recording with reply preview
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reply preview area (Phase 3: shown when replying)
                if (_replyToMessage != null)
                  _buildReplyPreview(),
                AudioRecorderButton(
                  autoStart: true, // Auto-start recording when shown
                  onAudioRecorded: _sendAudioMessage,
                  onRecordingStarted: () {
                    // Already recording, autoStart handles it
                  },
                  onRecordingCancelled: () {
                    setState(() => _isRecording = false);
                  },
                ),
              ],
            )
          : // Standard messenger layout with image preview support
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reply preview area (Phase 3: shown when replying)
                if (_replyToMessage != null)
                  _buildReplyPreview(),
                
                // Image preview area (shown when images are selected)
                if (_selectedImages.isNotEmpty)
                  Container(
                    height: 100,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedImages.length,
                      itemBuilder: (context, index) {
                        return Stack(
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                image: DecorationImage(
                                  image: FileImage(File(_selectedImages[index])),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            // Remove button
                            Positioned(
                              top: 4,
                              right: 12,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedImages.removeAt(index);
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                
                  Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Attachment button (left side)
                    AttachmentButton(
                      enabled: !_sending && !_isRecording,
                      onImageSelected: (imagePath) {
                        Logger.debug('Image selected callback: $imagePath');
                        setState(() {
                          _selectedImages.add(imagePath);
                        });
                      },
                    ),
                    
                    const SizedBox(width: 8),
                    
                    // Input field (expandable center)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _messageController,
                      focusNode: _messageFocusNode,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        isDense: true,
                      ),
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // Animated switch between Microphone and Send button (same position)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: (_hasText || _selectedImages.isNotEmpty)
                      ? // Send button (when text or images are present)
                        Container(
                          key: const ValueKey('send'),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.9),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _sending ? null : _sendMessage,
                            icon: _sending
                                ? const InlineLoadingIndicator(
                                    size: 18,
                                    color: Colors.white,
                                  )
                                : const Icon(Icons.send, size: 18),
                            color: Theme.of(context).colorScheme.onPrimary,
                            padding: EdgeInsets.zero,
                          ),
                        )
                      : // Microphone button (when text field is empty)
                        GestureDetector(
                          key: const ValueKey('mic'),
                          onTapDown: (_) {
                            setState(() => _isRecording = true);
                            FocusScope.of(context).unfocus();
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.mic,
                              color: Theme.of(context).colorScheme.primary,
                              size: 18,
                            ),
                          ),
                        ),
                ),
              ], // End Row children
            ), // End Row
          ], // End Column children
        ), // End Column
    );
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    final imagesToSend = List<String>.from(_selectedImages);
    
    // Must have either text or images
    if (text.isEmpty && imagesToSend.isEmpty) return;
    
    // Safety check: Don't send if blocked by other
    if (_isBlockedByOther) {
      if (mounted) {
        showTopNotification(
          context,
          'Cannot send - you have been blocked',
          isError: true,
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _sending = true);

    try {
      // Send images first (each as separate message)
      for (final imagePath in imagesToSend) {
        await _p2pService.sendImageMessage(
          recipientPeerID: widget.peerID,
          imagePath: imagePath,
          caption: imagesToSend.indexOf(imagePath) == imagesToSend.length - 1 && text.isNotEmpty
              ? text // Add caption to last image if text exists
              : null,
          replyToMessageId: _replyToMessage?.id,
          replyToPreviewText: _replyToMessage != null ? _getReplyPreviewText() : null,
          replyToContentType: _replyToMessage?.contentType,
        );
      }
      
      // Send text as separate message if no images (or if images were sent without caption)
      if (text.isNotEmpty && imagesToSend.isEmpty) {
        await _p2pService.sendMessage(
          recipientPeerID: widget.peerID,
          text: text,
          replyToMessageId: _replyToMessage?.id,
          replyToPreviewText: _replyToMessage != null ? _getReplyPreviewText() : null,
          replyToContentType: _replyToMessage?.contentType,
        );
      }

      _messageController.clear();
      setState(() {
        _selectedImages.clear();
      });
      
      // Clear reply after sending
      if (_replyToMessage != null) {
        _clearReply();
      }
      
      _loadMessages();
      // Scroll to bottom after sending to show the sent message
      _scrollToBottom();
      // Keep keyboard open after sending
      _messageFocusNode.requestFocus();
    } catch (e) {
      Logger.error('Error sending message', e);
      
      // Check if it's the key exchange error
      if (e.toString().contains('No X25519 encryption key')) {
        if (mounted) {
          _showKeyExchangeDialog();
        }
      } else {
        if (mounted) {
          showTopNotification(
            context,
            'Error sending message: $e',
            isError: true,
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _sendAudioMessage(String audioPath, Duration duration, List<double> waveform) async {
    if (!mounted) return;
    
    // Safety check: Don't send if blocked by other
    if (_isBlockedByOther) {
      if (mounted) {
        showTopNotification(
          context,
          'Cannot send - you have been blocked',
          isError: true,
        );
      }
      return;
    }
    
    Logger.debug('Sending audio message: $audioPath (${duration.inSeconds}s, ${waveform.length} waveform samples)');
    
    // Reset recording state (recording is finished when this callback is called)
    setState(() {
      _isRecording = false;
      _sending = true;
    });

    try {
      // Send audio message via P2P service
      // The P2P service will handle encryption and sending
      await _p2pService.sendAudioMessage(
        recipientPeerID: widget.peerID,
        audioPath: audioPath,
        duration: duration,
        waveform: waveform,
        replyToMessageId: _replyToMessage?.id,
        replyToPreviewText: _replyToMessage != null ? _getReplyPreviewText() : null,
        replyToContentType: _replyToMessage?.contentType,
      );

      // Clear reply after sending
      if (_replyToMessage != null) {
        _clearReply();
      }

      _loadMessages();
      // Scroll to bottom after sending to show the sent message
      _scrollToBottom();
    } catch (e) {
      Logger.error('Error sending audio message', e);
      
      // Check if it's a key exchange error
      if (e.toString().contains('No X25519 encryption key')) {
        if (mounted) {
          _showKeyExchangeDialog();
        }
      } else {
        if (mounted) {
          showTopNotification(
            context,
            'Error sending audio: $e',
            isError: true,
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  // TODO(coming-soon): _initiateCall — re-enable when call feature ships
  // void _initiateCall(BuildContext context) async { ... }

  // Helper to resolve relative image paths to absolute paths
  String _resolveImagePath(String relativePath) {
    // Already absolute
    if (relativePath.startsWith('/')) {
      return relativePath;
    }
    
    // Resolve relative path (will be completed asynchronously in widget state)
    // For now, return relative path and let ImageMessageBubble handle it
    return relativePath;
  }

  Future<void> _retryFailedMessage(Message message) async {
    if (!mounted) return;
    
    try {
      // Show loading indicator
      showTopNotification(
        context,
        'Retrying message...',
        duration: const Duration(seconds: 1),
      );
      
      // Retry the message via P2P service
      await _p2pService.retrySingleMessage(message);
      
      // Reload messages to show updated status
      _loadMessages();
      
      if (mounted) {
        showTopNotification(
          context,
          'Message sent',
          duration: const Duration(seconds: 1),
        );
      }
    } catch (e) {
      Logger.warning('Error retrying message: $e');
      if (mounted) {
        // Reload to show failed status still
        _loadMessages();
        showTopNotification(
          context,
          'Retry failed: $e',
          isError: true,
        );
      }
    }
  }

  // ========== LONG PRESS CONTEXT MENU (Phase 1 + Phase 2 + Phase 3) ==========
  
  /// Handle long press on a message bubble (Phase 3: with dynamic positioning)
  Future<void> _onMessageLongPress(Message message) async {
    // Trigger haptic feedback immediately
    await HapticFeedback.mediumImpact();
    
    // Phase 3: Calculate message position for dynamic menu placement
    final messageKey = _messageKeys[message.id];
    Offset? messagePosition;
    
    if (messageKey?.currentContext != null) {
      final RenderBox renderBox = messageKey!.currentContext!.findRenderObject() as RenderBox;
      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      
      // Store position and size for overlay rendering
      messagePosition = Offset(position.dx, position.dy);
      
      Logger.debug('📍 Message position: $messagePosition, size: $size');
      
      setState(() {
        _selectedMessageSize = size;
      });
    }
    
    // Set selected message and start scale animation
    setState(() {
      _selectedMessage = message;
      _selectedMessagePosition = messagePosition;
    });
    
    // Animate scale
    _scaleController?.forward();
    
    // Show context menu with custom overlay
    if (!mounted) return;
    _showCustomContextMenu(message);
  }
  
  /// Show custom context menu with backdrop overlay (Phase 2 + Phase 3: dynamic positioning)
  void _showCustomContextMenu(Message message) {
    if (!mounted) return;
    
    final overlay = Overlay.of(context);
    final isMe = message.senderPeerID == _identityService.peerID;
    
    // Create backdrop overlay with blur
    _backdropOverlay = OverlayEntry(
      builder: (context) => _BackdropWidget(
        onTap: _dismissContextMenu,
      ),
    );
    
    // Create message highlight overlay ABOVE backdrop
    if (_selectedMessagePosition != null && _selectedMessageSize != null) {
      // Pre-calculate reply sender name for overlay
      final replyToSenderName = message.replyToMessageId != null 
          ? _getReplyToSenderName(message.replyToMessageId!)
          : null;
      
      _messageHighlightOverlay = OverlayEntry(
        builder: (context) => _MessageHighlightOverlay(
          message: message,
          isMe: isMe,
          position: _selectedMessagePosition!,
          size: _selectedMessageSize!,
          scaleAnimation: _scaleAnimation!,
          contactName: widget.contactName,
          identityService: _identityService,
          replyToSenderName: replyToSenderName,
        ),
      );
    }
    
    // Create menu overlay (Phase 3: with dynamic positioning)
    _menuOverlay = OverlayEntry(
      builder: (context) => _ContextMenuOverlay(
        message: message,
        isMe: isMe,
        messagePosition: _selectedMessagePosition, // Phase 3: Pass position
        onCopy: () {
          _dismissContextMenu();
          _handleCopyMessage(message);
        },
        onReply: () {
          _dismissContextMenu();
          _handleReplyMessage(message);
        },
        onForward: () {
          _dismissContextMenu();
          _handleForwardMessage(message);
        },
        onInfo: () {
          _dismissContextMenu();
          _handleShowMessageInfo(message);
        },
        onDelete: isMe ? () {
          _dismissContextMenu();
          _handleDeleteMessage(message);
        } : null,
      ),
    );
    
    // Insert overlays: backdrop → message → menu
    overlay.insert(_backdropOverlay!);
    if (_messageHighlightOverlay != null) {
      overlay.insert(_messageHighlightOverlay!);
    }
    overlay.insert(_menuOverlay!);
  }
  
  /// Dismiss context menu and clean up (Phase 2 + Phase 3)
  void _dismissContextMenu() {
    // First: Reverse scale animation
    _scaleController?.reverse().then((_) {
      if (mounted) {
        // After animation completes: Remove overlays
        _backdropOverlay?.remove();
        _backdropOverlay = null;
        
        _messageHighlightOverlay?.remove();
        _messageHighlightOverlay = null;
        
        _menuOverlay?.remove();
        _menuOverlay = null;
        
        // Finally: Clear selection to show original message
        setState(() {
          _selectedMessage = null;
          _selectedMessagePosition = null;
          _selectedMessageSize = null;
        });
      }
    });
  }
  
  // ========== ACTION HANDLERS ==========
  
  /// Copy message text to clipboard (Phase 3: extended for captions)
  Future<void> _handleCopyMessage(Message message) async {
    try {
      String text;
      
      // Phase 3: Handle different content types
      switch (message.contentType) {
        case ContentType.text:
          text = message.plaintext ?? '[Encrypted]';
          break;
        case ContentType.image:
          // Copy caption if available, otherwise notify user
          final caption = message.contentMeta?['caption'];
          if (caption != null && caption.isNotEmpty) {
            text = caption;
          } else {
            if (mounted) {
              showTopNotification(
                context,
                'Image has no caption to copy',
                duration: const Duration(seconds: 2),
              );
            }
            return;
          }
          break;
        case ContentType.audio:
          if (mounted) {
            showTopNotification(
              context,
              'Cannot copy voice message',
              duration: const Duration(seconds: 2),
            );
          }
          return;
        default:
          text = message.id; // Fallback: copy message ID
          break;
      }
      
      await Clipboard.setData(ClipboardData(text: text));
      
      if (mounted) {
        showTopNotification(
          context,
          'Copied to clipboard',
          duration: const Duration(seconds: 1),
        );
      }
      
      Logger.debug('📋 Message copied to clipboard: ${message.id}');
    } catch (e) {
      Logger.error('Error copying message', e);
      if (mounted) {
        showTopNotification(
          context,
          'Failed to copy message',
          isError: true,
        );
      }
    }
  }
  
  /// Reply to message (Phase 3: Full implementation)
  void _handleReplyMessage(Message message) {
    Logger.debug('🔄 Reply to message: ${message.id}');
    
    setState(() {
      _replyToMessage = message;
    });
    
    // Focus message input
    _messageFocusNode.requestFocus();
  }
  
  /// Clear reply state
  void _clearReply() {
    setState(() {
      _replyToMessage = null;
    });
  }
  
  /// Get reply preview text for sending
  String _getReplyPreviewText() {
    if (_replyToMessage == null) return '';
    
    switch (_replyToMessage!.contentType) {
      case ContentType.audio:
        return 'Voice message';
      case ContentType.image:
        return _replyToMessage!.contentMeta?['caption'] ?? 'Image';
      case ContentType.text:
      default:
        final text = _replyToMessage!.plaintext ?? '[Encrypted]';
        // Truncate long messages
        return text.length > 50 ? '${text.substring(0, 50)}...' : text;
    }
  }
  
  /// Get the name of the person who sent the original message being replied to
  String _getReplyToSenderName(String replyToMessageId) {
    // Find the original message in _messages list
    final originalMessage = _messages.firstWhere(
      (m) => m.id == replyToMessageId,
      orElse: () => _messages.first, // Fallback
    );
    
    if (originalMessage.id == replyToMessageId) {
      final wasFromMe = originalMessage.senderPeerID == _identityService.peerID;
      return wasFromMe ? 'You' : widget.contactName;
    }
    
    return 'Message';
  }
  
  /// Build reply indicator widget to show inside message bubble
  Widget? _buildReplyIndicator(Message message) {
    if (message.replyToMessageId == null) return null;
    
    final isMe = message.senderPeerID == _identityService.peerID;
    final replyToName = _getReplyToSenderName(message.replyToMessageId!);
    
    return GestureDetector(
      onTap: () => _scrollToAndHighlightMessage(message.replyToMessageId!),
      child: Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: isMe 
                ? Colors.amber.withOpacity(0.9)
                : Colors.grey.withOpacity(0.7),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            replyToName,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isMe 
                  ? (Theme.of(context).brightness == Brightness.dark
                      ? Colors.amber
                      : Colors.orange[800]!)
                  : (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withOpacity(0.8)
                      : Colors.black87),
            ),
          ),
          Text(
            message.replyToPreviewText ?? '',
            style: TextStyle(
              fontSize: 10,
              color: (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black87).withOpacity(0.6),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      ),
    );
  }
  
  /// Scroll to and highlight a message when tapping on reply indicator
  void _scrollToAndHighlightMessage(String messageId) async {
    print('🎯 DEBUG: Scrolling to message: ${messageId.substring(0, 8)}');
    
    // Find the index of the message
    final messageIndex = _messages.indexWhere((m) => m.id == messageId);
    
    if (messageIndex == -1) {
      print('❌ DEBUG: Message not found in _messages list');
      // Message not found (might be outside loaded range)
      if (mounted) {
        showTopNotification(
          context,
          'Message not found in current view',
          duration: const Duration(seconds: 2),
        );
      }
      return;
    }
    
    print('✅ DEBUG: Message found at index: $messageIndex');
    
    // Get the GlobalKey for this message
    final messageKey = _messageKeys[messageId];
    
    print('🔑 DEBUG: messageKey exists: ${messageKey != null}');
    print('📍 DEBUG: currentContext exists: ${messageKey?.currentContext != null}');
    
    if (messageKey != null && messageKey.currentContext != null) {
      print('🎯 DEBUG: Using Scrollable.ensureVisible');
      try {
        // Use Scrollable.ensureVisible for automatic scroll calculation
        await Scrollable.ensureVisible(
          messageKey.currentContext!,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          alignment: 0.2, // Position at 20% from top (allows space for header)
        );
        print('✅ DEBUG: Scroll completed successfully');
      } catch (e) {
        print('❌ DEBUG: Scrollable.ensureVisible failed: $e');
      }
    } else {
      print('⚠️ DEBUG: Falling back to manual scroll calculation');
      // Fallback: use manual scroll calculation
      if (_scrollController.hasClients) {
        // Estimate scroll position based on index
        // Average message height is around 80px
        final estimatedHeight = 80.0;
        final targetOffset = messageIndex * estimatedHeight;
        
        await _scrollController.animateTo(
          targetOffset.clamp(
            _scrollController.position.minScrollExtent,
            _scrollController.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        print('✅ DEBUG: Manual scroll completed to offset: $targetOffset');
      }
    }
    
    // Start highlight animation
    if (mounted) {
      setState(() {
        _highlightedMessageId = messageId;
      });
      
      print('✨ DEBUG: Starting highlight animation');
      // Start the fade animation
      _highlightController?.forward(from: 0.0);
    }
  }
  
  /// Get highlight opacity for a message (0.0 = no highlight, 1.0 = full highlight)
  double _getHighlightOpacity(String messageId) {
    if (_highlightedMessageId == messageId && _highlightAnimation != null) {
      return _highlightAnimation!.value;
    }
    return 0.0;
  }
  
  /// Forward message to another contact (Phase 3: Placeholder)
  void _handleForwardMessage(Message message) {
    Logger.debug('➡️ Forward message: ${message.id}');
    
    if (mounted) {
      showTopNotification(
        context,
        'Forward feature coming soon',
        duration: const Duration(seconds: 2),
      );
    }
    
    // TODO: Show contact picker dialog
    // Navigator.push(context, ContactPickerScreen(message: message));
  }
  
  /// Show message info dialog
  void _handleShowMessageInfo(Message message) {
    final isMe = message.senderPeerID == _identityService.peerID;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Message Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Type', message.contentType.name),
            _buildInfoRow('Sender', isMe ? 'You' : widget.contactName),
            _buildInfoRow('Time', DateFormat('dd.MM.yyyy HH:mm:ss').format(message.timestamp.toLocal())),
            _buildInfoRow('Status', message.deliveryStatus.name),
            _buildInfoRow('Network', message.networkId),
            if (message.contentMeta != null && message.contentMeta!.isNotEmpty)
              ...message.contentMeta!.entries.map((e) => _buildInfoRow(e.key, e.value)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    
    Logger.debug('ℹ️ Show message info: ${message.id}');
  }
  
  /// Build info row for message info dialog
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
  
  /// Delete message (only own messages)
  Future<void> _handleDeleteMessage(Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      await _storageService.deleteMessage(message.id);
      _loadMessages();
      
      if (mounted) {
        showTopNotification(
          context,
          'Message deleted',
          duration: const Duration(seconds: 1),
        );
      }
      
      Logger.debug('🗑️ Message deleted: ${message.id}');
    } catch (e) {
      Logger.error('Error deleting message', e);
      if (mounted) {
        showTopNotification(
          context,
          'Failed to delete message',
          isError: true,
        );
      }
    }
  }

  void _showKeyExchangeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encryption Keys Not Exchanged'),
        content: const Text(
          'You need to exchange encryption keys with this contact before sending encrypted messages.\n\n'
          'Would you like to send a key exchange request now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _sendKeyExchange();
            },
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendKeyExchange() async {
    try {
      await _p2pService.sendKeyExchangeRequest(widget.peerID);
      
      if (mounted) {
        showTopNotification(
          context,
          'Key exchange request sent! Wait for the other person to accept.',
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e) {
      Logger.warning('Error sending key exchange: $e');
      if (mounted) {
        showTopNotification(
          context,
          'Error sending key exchange: $e',
          isError: true,
        );
      }
    }
  }

  /// Check if two dates are on the same day
  bool _isSameDay(DateTime date1, DateTime date2) {
    final local1 = date1.toLocal();
    final local2 = date2.toLocal();
    return local1.year == local2.year && 
           local1.month == local2.month && 
           local1.day == local2.day;
  }

  /// Format date for chat header (like WhatsApp)
  String _formatDateHeader(DateTime dateTime) {
    final localTime = dateTime.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(localTime.year, localTime.month, localTime.day);
    
    if (messageDate == today) {
      return 'Heute';
    } else if (messageDate == yesterday) {
      return 'Gestern';
    } else if (now.difference(localTime).inDays < 7) {
      // This week: show weekday
      return DateFormat('EEEE, d. MMMM').format(localTime);
    } else {
      // Older: show full date
      return DateFormat('d. MMMM yyyy').format(localTime);
    }
  }

  /// Build date header widget
  Widget _buildDateHeader(String dateText) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          dateText,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
  
  /// Build reply preview widget (Phase 3)
  Widget _buildReplyPreview() {
    if (_replyToMessage == null) return const SizedBox.shrink();
    
    final replyToIsMe = _replyToMessage!.senderPeerID == _identityService.peerID;
    final replyToName = replyToIsMe ? 'You' : widget.contactName;
    
    // Get preview text based on content type
    String previewText;
    IconData previewIcon;
    
    switch (_replyToMessage!.contentType) {
      case ContentType.audio:
        previewText = 'Voice message';
        previewIcon = Icons.mic;
        break;
      case ContentType.image:
        previewText = _replyToMessage!.contentMeta?['caption'] ?? 'Image';
        previewIcon = Icons.image;
        break;
      case ContentType.text:
      default:
        previewText = _replyToMessage!.plaintext ?? '[Encrypted]';
        previewIcon = Icons.reply;
        break;
    }
    
    // Truncate long messages
    if (previewText.length > 50) {
      previewText = '${previewText.substring(0, 50)}...';
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.amber
                : Colors.orange[800]!,
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            previewIcon,
            size: 20,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.amber
                : Colors.orange[800]!,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to $replyToName',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.amber
                        : Colors.orange[800]!,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  previewText,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Cancel reply',
            child: IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: _clearReply,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Phase 4: Handle device metrics changes (rotation, keyboard)
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    
    if (!mounted) return;
    
    // Get current metrics
    final currentSize = MediaQuery.of(context).size;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    
    // Check for screen size change (rotation)
    if (_lastScreenSize != null && 
        (_lastScreenSize!.width != currentSize.width || 
         _lastScreenSize!.height != currentSize.height)) {
      // Screen rotated - dismiss context menu if open
      if (_selectedMessage != null || _backdropOverlay != null) {
        Logger.debug('🔄 Screen rotation detected - dismissing context menu');
        _dismissContextMenu();
      }
    }
    
    // Check for keyboard state change
    if ((keyboardHeight - _lastKeyboardHeight).abs() > 50) {
      // Significant keyboard height change detected
      if (keyboardHeight > _lastKeyboardHeight && 
          (_selectedMessage != null || _backdropOverlay != null)) {
        // Keyboard appeared while menu was open - dismiss menu
        Logger.debug('⌨️ Keyboard appeared - dismissing context menu');
        _dismissContextMenu();
      }
    }
    
    // Update tracked values
    _lastScreenSize = currentSize;
    _lastKeyboardHeight = keyboardHeight;
  }

  @override
  void dispose() {
    // Phase 4: Remove observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Clean up overlays if still mounted (Phase 2)
    _dismissContextMenu();
    
    // Dispose animation controllers (Phase 2 + Highlight)
    _scaleController?.dispose();
    _highlightController?.dispose();
    
    _messageSubscription?.cancel();
    _chatUpdateSubscription?.cancel();
    _reloadDebounceTimer?.cancel();
    _scrollDebounceTimer?.cancel();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

// ========== PHASE 2: CUSTOM OVERLAY WIDGETS ==========

/// Backdrop overlay with blur effect
class _BackdropWidget extends StatefulWidget {
  final VoidCallback onTap;

  const _BackdropWidget({required this.onTap});

  @override
  State<_BackdropWidget> createState() => _BackdropWidgetState();
}

class _BackdropWidgetState extends State<_BackdropWidget> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return GestureDetector(
          onTap: widget.onTap,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 3.0 * _fadeAnimation.value,
              sigmaY: 3.0 * _fadeAnimation.value,
            ),
            child: Container(
              color: Colors.black.withOpacity(0.4 * _fadeAnimation.value),
            ),
          ),
        );
      },
    );
  }
}

/// Message highlight overlay - renders selected message ABOVE blur layer
class _MessageHighlightOverlay extends StatelessWidget {
  final Message message;
  final bool isMe;
  final Offset position;
  final Size size;
  final Animation<double> scaleAnimation;
  final String contactName;
  final IIdentityService identityService;
  final String? replyToSenderName; // Pre-calculated sender name for reply

  const _MessageHighlightOverlay({
    required this.message,
    required this.isMe,
    required this.position,
    required this.size,
    required this.scaleAnimation,
    required this.contactName,
    required this.identityService,
    this.replyToSenderName,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context),
          child: MediaQuery(
            data: MediaQuery.of(context),
            child: DefaultTextStyle(
              style: DefaultTextStyle.of(context).style,
              child: AnimatedBuilder(
                animation: scaleAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: scaleAnimation.value,
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: child,
                  );
                },
                child: SizedBox(
                  width: size.width,
                  child: _buildOriginalMessage(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build the ORIGINAL message widget (same as in ListView)
  Widget _buildOriginalMessage(BuildContext context) {
    // System messages
    if (message.id.startsWith('system_')) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message.plaintext ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue.shade800,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Audio messages
    if (message.contentType == ContentType.audio) {
      List<double>? waveform;
      final waveformJson = message.contentMeta?['waveform'];
      if (waveformJson != null) {
        try {
          final decoded = jsonDecode(waveformJson);
          if (decoded is List) {
            waveform = decoded.map((e) => (e as num).toDouble()).toList();
          }
        } catch (e) {
          // Ignore
        }
      }
      
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: AudioMessageBubble(
            audioPath: message.plaintext ?? '',
            duration: Duration(
              seconds: int.tryParse(message.contentMeta?['duration'] ?? '0') ?? 0,
            ),
            timestamp: message.timestamp,
            isMe: isMe,
            deliveryStatus: message.deliveryStatus,
            waveform: waveform,
            replyToMessageId: message.replyToMessageId,
            replyToPreviewText: message.replyToPreviewText,
            replyToContentType: message.replyToContentType?.name,
            replyToSenderName: replyToSenderName,
            onLongPress: null, // Disable in overlay
            onPlayError: () {},
          ),
        ),
      );
    }

    // Image messages
    if (message.contentType == ContentType.image) {
      final caption = message.contentMeta?['caption'];
      return ImageMessageBubble(
        messageId: message.id,
        imagePath: _resolveImagePath(message.plaintext ?? ''),
        timestamp: message.timestamp,
        isMe: isMe,
        senderName: isMe ? 'You' : contactName,
        deliveryStatus: message.deliveryStatus,
        caption: caption,
        replyToMessageId: message.replyToMessageId,
        replyToPreviewText: message.replyToPreviewText,
        replyToContentType: message.replyToContentType?.name,
        replyToSenderName: replyToSenderName,
        onLongPress: null, // Disable in overlay
        onLoadError: () {},
      );
    }

    // Text messages
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
              : (Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[800]!.withOpacity(0.3)
                  : Colors.grey[400]!.withOpacity(0.2)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(
            color: isMe
                ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                : (Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey[600]!.withOpacity(0.3)
                    : Colors.grey[400]!.withOpacity(0.3)),
            width: 1,
          ),
        ),
        child: IntrinsicWidth(
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // Make bubble fit content dynamically
            children: [
              // Reply indicator (if replying to another message)
              if (message.replyToMessageId != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _buildReplyIndicatorForOverlay(context, message, isMe),
                ),
              DefaultTextStyle(
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                  fontSize: 14,
                  decoration: TextDecoration.none,
                ),
                child: Text(message.plaintext ?? '[Encrypted]'),
              ),
            const SizedBox(height: 4),
            // Timestamp row - always align to right
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('HH:mm').format(message.timestamp.toLocal()),
                    style: TextStyle(
                      fontSize: 10,
                      color: (Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87).withOpacity(0.7),
                      decoration: TextDecoration.none,
                    ),
                  ),
                if (isMe && message.deliveryStatus == DeliveryStatus.sent) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.check,
                    size: 14,
                    color: (Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87).withOpacity(0.7),
                  ),
                ],
              ],
            ),
            ),
            // Show delivery status for sent messages (pending/failed)
            if (isMe && message.deliveryStatus != DeliveryStatus.sent) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    message.deliveryStatus == DeliveryStatus.pending
                        ? Icons.schedule
                        : Icons.warning,
                    size: 12,
                    color: message.deliveryStatus == DeliveryStatus.pending
                        ? (Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black87).withOpacity(0.7)
                        : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    message.deliveryStatus == DeliveryStatus.pending
                        ? 'Sending...'
                        : 'Failed - Tap to retry',
                    style: TextStyle(
                      fontSize: 10,
                      color: (Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black87).withOpacity(0.7),
                      fontStyle: FontStyle.italic,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  /// Build reply indicator for overlay (static method to avoid context issues)
  Widget _buildReplyIndicatorForOverlay(BuildContext context, Message message, bool isMe) {
    final replyToName = message.replyToMessageId != null && replyToSenderName != null
        ? replyToSenderName!
        : 'Message';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 5, 8, 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
            color: isMe 
                ? (Theme.of(context).brightness == Brightness.dark
                    ? Colors.amber.withOpacity(0.9)
                    : Colors.orange[800]!)
                : Colors.grey.withOpacity(0.7),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            replyToName,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isMe 
                  ? (Theme.of(context).brightness == Brightness.dark
                      ? Colors.amber
                      : Colors.orange[800]!) 
                  : (Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withOpacity(0.8)
                      : Colors.black87),
              decoration: TextDecoration.none,
            ),
          ),
          Text(
            message.replyToPreviewText ?? '',
            style: TextStyle(
              fontSize: 10,
              color: (Theme.of(context).brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black87).withOpacity(0.6),
              decoration: TextDecoration.none,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Resolve image path (helper method)
  String _resolveImagePath(String path) {
    if (path.isEmpty) return path;
    if (path.startsWith('/') || path.contains('://')) {
      return path;
    }
    return path;
  }
}

/// Context menu overlay with slide animation (Phase 2 + Phase 3: positioning support)
class _ContextMenuOverlay extends StatefulWidget {
  final Message message;
  final bool isMe;
  final Offset? messagePosition; // Phase 3: Position hint for future dynamic placement
  final VoidCallback onCopy;
  final VoidCallback onReply;
  final VoidCallback onForward;
  final VoidCallback onInfo;
  final VoidCallback? onDelete;

  const _ContextMenuOverlay({
    required this.message,
    required this.isMe,
    this.messagePosition,
    required this.onCopy,
    required this.onReply,
    required this.onForward,
    required this.onInfo,
    this.onDelete,
  });

  @override
  State<_ContextMenuOverlay> createState() => _ContextMenuOverlayState();
}

class _ContextMenuOverlayState extends State<_ContextMenuOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate menu position dynamically
    final screenSize = MediaQuery.of(context).size;
    final messagePos = widget.messagePosition;
    
    // Default to center if no position provided
    double? menuLeft;
    double? menuRight;
    double? menuTop;
    double? menuBottom;
    
    if (messagePos != null) {
      // Position menu near the message
      final isUpperHalf = messagePos.dy < screenSize.height / 2;
      
      if (isUpperHalf) {
        // Message is in upper half → show menu below
        menuTop = messagePos.dy + 70; // Below message
      } else {
        // Message is in lower half → show menu above
        menuBottom = screenSize.height - messagePos.dy + 10; // Above message
      }
      
      // Position horizontally (center with slight offset from edges)
      final menuWidth = 200.0;
      menuLeft = (screenSize.width - menuWidth) / 2;
    } else {
      // Fallback: center screen
      menuTop = screenSize.height / 2 - 150;
      menuLeft = (screenSize.width - 200.0) / 2;
    }
    
    return Positioned(
      left: menuLeft,
      right: menuRight,
      top: menuTop,
      bottom: menuBottom,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 200,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Menu items - compact design with dividers
                    if ((widget.message.contentType == ContentType.text &&
                         widget.message.plaintext != null) ||
                        (widget.message.contentType == ContentType.image &&
                         widget.message.contentMeta?['caption'] != null &&
                         widget.message.contentMeta!['caption']!.isNotEmpty)) ...[
                      _MenuOption(
                        icon: Icons.copy,
                        label: widget.message.contentType == ContentType.image 
                            ? 'Copy Caption' 
                            : 'Copy',
                        onTap: widget.onCopy,
                      ),
                      _buildDivider(),
                    ],

                    _MenuOption(
                      icon: Icons.reply_outlined,
                      label: 'Reply',
                      onTap: widget.onReply,
                    ),
                    
                    _buildDivider(),

                    _MenuOption(
                      icon: Icons.forward_outlined,
                      label: 'Forward',
                      onTap: widget.onForward,
                    ),
                    
                    _buildDivider(),

                    _MenuOption(
                      icon: Icons.info_outline,
                      label: 'Info',
                      onTap: widget.onInfo,
                    ),

                    // Delete option (only for own messages)
                    if (widget.onDelete != null) ...[
                      _buildDivider(),
                      _MenuOption(
                        icon: Icons.delete_outline,
                        label: 'Delete',
                        color: Colors.red,
                        onTap: widget.onDelete!,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  /// Build divider with padding from edges
  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.white.withOpacity(0.15),
      ),
    );
  }
}

/// Menu option item widget
class _MenuOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _MenuOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final itemColor = color ?? Colors.white;

    return Semantics(
      button: true,
      label: label,
      enabled: true,
      child: InkWell(
        onTap: () async {
          await HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: itemColor),
              const SizedBox(width: 12),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: itemColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom FloatingActionButton location - positioned above mic/send button
class _CustomFabLocation extends FloatingActionButtonLocation {
  const _CustomFabLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    // Position at bottom right, with padding from edges
    // X: right edge minus fab width minus padding (8px)
    final double fabX = scaffoldGeometry.scaffoldSize.width - 
                        scaffoldGeometry.floatingActionButtonSize.width - 8.0;
    
    // Y: bottom edge minus input area height minus fab height minus spacing
    final double fabY = scaffoldGeometry.scaffoldSize.height - 
                        scaffoldGeometry.floatingActionButtonSize.height - 93.0;
    
    return Offset(fabX, fabY);
  }
}
