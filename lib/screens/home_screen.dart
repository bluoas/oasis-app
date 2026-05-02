import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/services_provider.dart';
import '../services/p2p_service.dart';
import '../services/network_service.dart';
import '../services/interfaces/i_storage_service.dart';
import '../models/contact.dart';
import '../models/chat.dart';
import '../models/message.dart';
// TODO(coming-soon): re-enable when call feature ships
// import '../models/call.dart';
// import 'active_call_screen.dart';
// import 'incoming_call_screen.dart';
import '../widgets/loading_state.dart';
import '../widgets/empty_state.dart';
import '../widgets/profile_image_viewer.dart';
import 'chat_screen.dart';
import 'add_contact_screen.dart';
import 'contact_detail_screen.dart';
import 'settings_screen.dart';
import 'show_my_qr_code_screen.dart';
import 'create_private_network_screen.dart';
import '../utils/top_notification.dart';
import '../utils/notification_utils.dart';
import '../utils/logger.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  
  // Feature flag for network switching UI (temporary disabled)
  static const bool _enableNetworkSwitching = false;
  
  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<void>? _chatUpdateSubscription;
  
  List<Chat> _chats = [];
  List<Chat> _filteredChats = []; // Filtered chats based on search
  bool _loading = true;
  Timer? _reloadDebounceTimer;
  Timer? _searchDebounceTimer;
  bool _isReloading = false;
  int _selectedIndex = 0; // Start with Chats tab
  String _userName = ''; // User's display name
  final _nameController = TextEditingController();
  final _searchController = TextEditingController();
  String? _profileImagePath; // Path to profile image
  String _searchQuery = ''; // Current search query
  
  // Contacts list for Me tab
  List<Contact> _contacts = [];
  List<Contact> _blockedContacts = [];
  bool _loadingContacts = false;
  
  // Cache for contact profile images to avoid re-loading on every build
  final Map<String, File?> _profileImageCache = {};
  
  // Cache for contact objects to check isKMNodeContact flag
  final Map<String, Contact?> _contactCache = {};
  
  // Network service instance to listen for network changes
  NetworkService? _networkService;

  // Getter for services from Riverpod providers
  P2PService get _p2pService => ref.read(p2pServiceProvider);
  IStorageService get _storageService => ref.read(storageServiceProvider);

  @override
  void initState() {
    super.initState();
    _loadChatsLocal();
    _listenToMessages();
    _loadUserName();
    _loadProfileImage();
    
    // Listen for network changes
    _networkService = ref.read(networkServiceProvider);
    _networkService?.addListener(_onNetworkChanged);
  }
  
  /// Called when network changes
  void _onNetworkChanged() {
    // Reload chats and contacts for the new network
    _loadChatsLocal();
    if (_selectedIndex == 1) {
      _loadContacts();
    }
  }

  /// Load chats from LOCAL database only (fast, no network)
  void _loadChatsLocal() async {
    // Debounce - don't reload if already reloading
    if (_isReloading) return;
    
    _isReloading = true;
    
    try {
      if (!mounted) return;
      
      // Only show loading on first load
      if (_chats.isEmpty && mounted) {
        setState(() => _loading = true);
      }
      
      // ONLY read from local SQLite - NO NETWORK!
      final chats = await _p2pService.getChats();
      
      if (!mounted) return;
      
      setState(() {
        _chats = chats;
        _filteredChats = chats; // Initialize filtered list
        _loading = false;
      });
      
      // Apply search filter if query exists
      if (_searchQuery.isNotEmpty) {
        _filterChats(_searchQuery);
      }
      
      // Load contact data (profile images and contact objects) for chats
      _loadContactData();
    } catch (e) {
      Logger.error('Error loading chats', e);
      if (!mounted) return;
      setState(() => _loading = false);
    } finally {
      _isReloading = false;
    }
  }
  
  
  /// Load contacts for Me tab
  Future<void> _loadContacts() async {
    if (_loadingContacts) return;
    
    setState(() => _loadingContacts = true);

    try {
      // Get contacts for active network only (network separation)
      final activeNetworkId = _networkService?.activeNetworkId ?? 'public';
      final result = await _storageService.getContactsForNetwork(activeNetworkId);
      
      if (!mounted) return;

      if (result.isSuccess) {
        final allContacts = result.valueOrNull ?? [];
        
        // Separate blocked and non-blocked contacts
        final normalContacts = allContacts.where((c) => !c.isBlocked).toList();
        final blockedContacts = allContacts.where((c) => c.isBlocked).toList();
        
        // Sort by name
        normalContacts.sort((a, b) => a.displayName.compareTo(b.displayName));
        blockedContacts.sort((a, b) => a.displayName.compareTo(b.displayName));
        
        setState(() {
          _contacts = normalContacts;
          _blockedContacts = blockedContacts;
          _loadingContacts = false;
        });

        // Load profile images for contacts
        await _loadContactProfileImages();
      } else {
        setState(() => _loadingContacts = false);
      }
    } catch (e) {
      Logger.error('Error loading contacts', e);
      if (!mounted) return;
      setState(() => _loadingContacts = false);
    }
  }
  
  /// Load profile images for contacts in Me tab
  Future<void> _loadContactProfileImages() async {
    final allContacts = [..._contacts, ..._blockedContacts];
    for (final contact in allContacts) {
      if (contact.profileImagePath != null && contact.profileImagePath!.isNotEmpty) {
        try {
          File imageFile;
          final imagePath = contact.profileImagePath!;

          if (imagePath.startsWith('/')) {
            imageFile = File(imagePath);
          } else {
            final appSupportDir = await getApplicationSupportDirectory();
            imageFile = File('${appSupportDir.path}/$imagePath');
          }

          if (await imageFile.exists()) {
            if (mounted) {
              setState(() {
                _profileImageCache[contact.peerID] = imageFile;
              });
            }
          }
        } catch (e) {
          Logger.warning('Error loading profile image for ${contact.displayName}: $e');
        }
      }
    }
  }

  /// Filter chats based on search query (with debounce)
  void _onSearchChanged(String query) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _filterChats(query);
      }
    });
  }

  /// Apply filter to chat list
  void _filterChats(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredChats = _chats;
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredChats = _chats.where((chat) {
          // Search in contact name
          final nameMatch = chat.name.toLowerCase().contains(lowerQuery);
          
          // Search in last message content
          final messageMatch = chat.lastMessage?.plaintext?.toLowerCase().contains(lowerQuery) ?? false;
          
          return nameMatch || messageMatch;
        }).toList();
      }
    });
  }

  /// Clear search and reset filter
  void _clearSearch() {
    _searchController.clear();
    _filterChats('');
    FocusScope.of(context).unfocus();
  }

  /// Load user's display name from SharedPreferences
  Future<void> _loadUserName() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final savedName = prefs.getString('user_display_name');
      
      if (savedName != null && savedName.isNotEmpty) {
        if (mounted) {
          setState(() {
            _userName = savedName;
            _nameController.text = savedName;
          });
        }
      } else {
        // Default name from PeerID (last 8 chars)
        final peerID = await ref.read(currentPeerIDProvider.future);
        
        if (peerID != null && mounted) {
          final defaultName = 'User ${peerID.substring(peerID.length - 8)}';
          setState(() {
            _userName = defaultName;
            _nameController.text = defaultName;
          });
        }
      }
    } catch (e) {
      Logger.error('Error loading username', e);
    }
  }

  /// Edit user's display name
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

  /// Save user's display name
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
          'Display name updated',
        );
        
        // Broadcast profile update to all contacts
        _broadcastProfileUpdate();
      }
    } catch (e) {
      Logger.error('Error saving username', e);
      if (mounted) {
        showTopNotification(
          context,
          'Failed to update display name',
          isError: true,
        );
      }
    }
  }

  /// Load profile image path from SharedPreferences
  Future<void> _loadProfileImage() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final relativePath = prefs.getString('profile_image_path');
      
      Logger.debug('Loading profile image...');
      Logger.debug('   Stored relative path: $relativePath');
      
      if (relativePath != null && relativePath.isNotEmpty) {
        // Reconstruct full path from relative path (iOS container path changes on restart)
        final appSupportDir = await getApplicationSupportDirectory();
        final fullPath = '${appSupportDir.path}/$relativePath';
        
        Logger.debug('   Reconstructed full path: $fullPath');
        
        // Check if file exists at reconstructed path
        final file = File(fullPath);
        final exists = await file.exists();
        Logger.debug('   File exists: $exists');
        
        if (exists) {
          if (mounted) {
            setState(() {
              _profileImagePath = fullPath;
            });
            Logger.debug('Profile image loaded successfully');
          }
        } else {
          // File was deleted, clear from preferences
          Logger.warning('Profile image file not found, clearing from preferences');
          await prefs.remove('profile_image_path');
        }
      } else {
        Logger.debug('   No profile image path stored');
      }
    } catch (e) {
      Logger.error('Error loading profile image', e);
    }
  }

  /// Save profile image path
  Future<void> _saveProfileImagePath(String fullPath) async {
    try {
      // Extract relative path from full path (iOS container path changes on restart)
      final appSupportDir = await getApplicationSupportDirectory();
      final relativePath = fullPath.replaceFirst('${appSupportDir.path}/', '');
      
      Logger.debug('Saving profile image path...');
      Logger.debug('   Full path: $fullPath');
      Logger.debug('   Relative path: $relativePath');
      
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString('profile_image_path', relativePath);
      
      if (mounted) {
        setState(() {
          _profileImagePath = fullPath;
        });
      }
    } catch (e) {
      Logger.error('Error saving profile image path', e);
    }
  }

  /// Pick profile image from gallery or camera
  Future<void> _pickProfileImage() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                          'Profile Photo',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Choose your profile picture',
                          style: TextStyle(
                            fontSize: 12,
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
            
            // Camera option
            _buildProfileOption(
              context,
              icon: Icons.camera_alt,
              label: 'Camera',
              color: Colors.blue,
              onTap: () => _pickImageFromSource(ImageSource.camera),
            ),
            
            // Gallery option
            _buildProfileOption(
              context,
              icon: Icons.photo_library,
              label: 'Gallery',
              color: Colors.green,
              onTap: () => _pickImageFromSource(ImageSource.gallery),
            ),
            
            // Remove option (only if image exists)
            if (_profileImagePath != null)
              _buildProfileOption(
                context,
                icon: Icons.delete_outline,
                label: 'Remove Photo',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _deleteProfileImage();
                },
              ),
            
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Build profile option in bottom sheet
  Widget _buildProfileOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(label),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
    );
  }

  /// Pick image from specific source
  Future<void> _pickImageFromSource(ImageSource source) async {
    Navigator.pop(context); // Close bottom sheet
    
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image != null) {
        // Delete old profile image if exists
        if (_profileImagePath != null && _profileImagePath!.isNotEmpty) {
          try {
            final oldFile = File(_profileImagePath!);
            if (await oldFile.exists()) {
              await oldFile.delete();
              Logger.info('Deleted old profile image');
            }
          } catch (e) {
            Logger.warning('Failed to delete old profile image: $e');
          }
        }
        
        // Copy image to permanent directory
        final appSupportDir = await getApplicationSupportDirectory();
        final profileImageDir = Directory('${appSupportDir.path}/profile_images');
        if (!await profileImageDir.exists()) {
          await profileImageDir.create(recursive: true);
        }
        
        // Determine file extension
        final extension = image.path.split('.').last.toLowerCase();
        final validExtension = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension) ? extension : 'jpg';
        
        // Create permanent file path with timestamp to avoid Flutter FileImage cache issues
        // Each new image gets a unique filename, forcing Flutter to reload from disk
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final permanentPath = '${profileImageDir.path}/my_profile_$timestamp.$validExtension';
        
        // Copy file to permanent location
        final sourceFile = File(image.path);
        final permanentFile = await sourceFile.copy(permanentPath);
        
        Logger.debug('Profile image saved to: $permanentPath');
        
        // Save permanent path
        await _saveProfileImagePath(permanentFile.path);
        
        if (mounted) {
          showTopNotification(
            context,
            'Profile image updated',
          );
          
          // Broadcast profile update to all contacts
          _broadcastProfileUpdate();
        }
      }
    } catch (e) {
      Logger.error('Error picking image', e);
      if (mounted) {
        showTopNotification(
          context,
          'Failed to pick image',
          isError: true,
        );
      }
    }
  }

  /// Delete profile image
  Future<void> _deleteProfileImage() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final relativePath = prefs.getString('profile_image_path');
      
      // Delete physical file if it exists
      if (relativePath != null && relativePath.isNotEmpty) {
        try {
          // Reconstruct full path from relative path
          final appSupportDir = await getApplicationSupportDirectory();
          final fullPath = '${appSupportDir.path}/$relativePath';
          final file = File(fullPath);
          
          if (await file.exists()) {
            await file.delete();
            Logger.info('Deleted profile image file: $fullPath');
          }
        } catch (e) {
          Logger.warning('Failed to delete profile image file: $e');
          // Continue anyway to remove from preferences
        }
      }
      
      await prefs.remove('profile_image_path');
      
      if (mounted) {
        setState(() {
          _profileImagePath = null;
        });
        
        showTopNotification(
          context,
          'Profile image removed',
        );
        
        // Broadcast profile update to all contacts (with deletion flag)
        await _p2pService.sendProfileUpdate(
          userName: _userName,
          profileImagePath: null,
          deleteImage: true,
        );
      }
    } catch (e) {
      Logger.error('Error deleting profile image', e);
    }
  }

  /// Broadcast profile update to all contacts
  Future<void> _broadcastProfileUpdate() async {
    try {
      Logger.debug('Broadcasting profile update to contacts...');
      
      // Send profile update via P2P service
      await _p2pService.sendProfileUpdate(
        userName: _userName,
        profileImagePath: _profileImagePath,
      );
      
      Logger.debug('Profile update broadcast complete');
    } catch (e) {
      Logger.warning('Error broadcasting profile update: $e');
      // Don't show error to user - it's a background operation
    }
  }

  /// Get contact's profile image file, reconstructing path if needed
  /// Cached version to avoid re-loading on every build
  Future<File?> _getContactProfileImage(String peerID) async {
    // Return cached value if available
    if (_profileImageCache.containsKey(peerID)) {
      return _profileImageCache[peerID];
    }
    
    try {
      final result = await ref.read(storageServiceProvider).getContact(peerID);
      final contact = result.valueOrNull;
      final profileImagePath = contact?.profileImagePath;
      
      if (profileImagePath == null || profileImagePath.isEmpty) {
        _profileImageCache[peerID] = null;
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
      
      // Only cache and return if file exists
      if (await imageFile.exists()) {
        _profileImageCache[peerID] = imageFile;
        return imageFile;
      }
      
      _profileImageCache[peerID] = null;
      return null;
    } catch (e) {
      Logger.warning('Error loading contact profile image: $e');
      _profileImageCache[peerID] = null;
      return null;
    }
  }
  
  /// Load contact data (profile images and contact objects) for all chats
  Future<void> _loadContactData() async {
    for (final chat in _chats) {
      // Load profile image
      await _getContactProfileImage(chat.peerID);
      
      // Load contact object
      if (!_contactCache.containsKey(chat.peerID)) {
        final contactResult = await _storageService.getContact(chat.peerID);
        if (contactResult.isSuccess && contactResult.value != null) {
          if (mounted) {
            setState(() {
              _contactCache[chat.peerID] = contactResult.value;
            });
          }
        }
      }
    }
  }

  /// Show profile image in fullscreen
  void _showProfileImageFullscreen() {
    if (_profileImagePath == null) {
      // No image, show picker directly
      _pickProfileImage();
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileImageViewer(
          imagePath: _profileImagePath!,
          userName: _userName.isNotEmpty ? _userName : 'Me',
          heroTag: 'profile_image',
          onChangePhoto: _pickProfileImage,
          onRemovePhoto: _deleteProfileImage,
        ),
      ),
    );
  }
  
  /// Sync messages from network (slow, blocks UI for ~5s)
  Future<void> _syncMessagesFromNetwork() async {
    if (_isReloading) return;
    
    try {
      setState(() => _loading = true);
      
      // Simple client-server: Poll from active node only
      Logger.debug('Syncing messages from network...');
      
      // Poll for messages from active node
      await _p2pService.pollMessagesManually();
      
      // Reload local chats after sync
      _loadChatsLocal();
      
      if (mounted) {
        showTopNotification(
          context,
          'Messages synced',
        );
      }
    } catch (e) {
      Logger.warning('Sync failed: $e');
      if (mounted) {
        showTopNotification(
          context,
          'Sync failed: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _listenToMessages() {
    _messageSubscription = _p2pService.messageStream.listen((message) async {
      // Trigger vibration and sound for incoming messages (not from self)
      try {
        final myPeerID = await ref.read(currentPeerIDProvider.future);
        if (myPeerID != null && message.senderPeerID != myPeerID) {
          // This is an incoming message from another peer
          await NotificationUtils.notifyIncomingMessage();
        }
      } catch (e) {
        // Silently ignore notification errors
      }
      
      // Debounced reload - max once per 500ms
      // NOTE: Only reloads LOCAL DB, no network calls!
      _reloadDebounceTimer?.cancel();
      _reloadDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) _loadChatsLocal();
      });
    });
    
    _chatUpdateSubscription = _p2pService.chatUpdateStream.listen((_) {
      // Clear profile image cache to force reload after profile updates
      _profileImageCache.clear();
      
      // Debounced reload - LOCAL ONLY
      _reloadDebounceTimer?.cancel();
      _reloadDebounceTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          _loadChatsLocal();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // TODO(coming-soon): Incoming call listener — re-enable when call feature ships
    // ref.listen<AsyncValue<Call?>>(currentCallProvider, (previous, next) {
    //   next.whenData((call) {
    //     if (call != null && call.direction == CallDirection.incoming) {
    //       if (call.state == CallState.ringing) {
    //         Navigator.of(context).push(
    //           MaterialPageRoute(
    //             builder: (_) => IncomingCallScreen(call: call),
    //             fullscreenDialog: true,
    //           ),
    //         );
    //       }
    //     }
    //   });
    // });
    
    return Scaffold(
      appBar: AppBar(
        leading: _selectedIndex == 1 ? _buildMeTabLeading() : null,
        title: _enableNetworkSwitching
            ? _buildTabTitleWithNetwork(
                _getAppBarTitle(),
                showEdit: _selectedIndex == 1,
              )
            : Text(_getAppBarTitle()),
        centerTitle: true,
        actions: _selectedIndex == 0 ? _buildChatActions() : _buildCommonActions(),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
      ),
      body: _buildBody(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          child: BottomNavigationBar(
            items: const <BottomNavigationBarItem>[
              // TODO: Community tab - coming soon
              // BottomNavigationBarItem(
              //   icon: Icon(Icons.groups_outlined),
              //   activeIcon: Icon(Icons.groups),
              //   label: 'Community',
              // ),
              BottomNavigationBarItem(
                icon: Icon(Icons.chat_bubble_outline),
                activeIcon: Icon(Icons.chat_bubble),
                label: 'Chats',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: 'Me',
              ),
            ],
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            elevation: 0,
          ),
        ),
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      // TODO: Community tab - coming soon
      // case 0:
      //   return 'Community';
      case 0:
        return 'Chats';
      case 1:
        return _userName.isNotEmpty ? _userName : 'Me';
      default:
        return 'Chats';
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    
    // Clear search when leaving Chats tab
    if (index != 0 && _searchQuery.isNotEmpty) {
      _clearSearch();
    }
    
    // Load contacts when switching to Me tab
    if (index == 1 && _contacts.isEmpty) {
      _loadContacts();
    }
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      // TODO: Community tab - coming soon
      // case 0:
      //   return _buildCommunityTab();
      case 0:
        return _buildChatsTab();
      case 1:
        return _buildProfileTab();
      default:
        return _buildChatsTab();
    }
  }

  // TODO: Community tab - coming soon
  // Widget _buildCommunityTab() {
  //   return Center(
  //     child: Column(
  //       mainAxisAlignment: MainAxisAlignment.center,
  //       children: [
  //         Icon(
  //           Icons.groups_outlined,
  //           size: 80,
  //           color: Theme.of(context).colorScheme.primary,
  //         ),
  //         const SizedBox(height: 16),
  //         Text(
  //           'Community',
  //           style: Theme.of(context).textTheme.headlineMedium,
  //         ),
  //         const SizedBox(height: 8),
  //         Text(
  //           'Welcome to Helo P2P',
  //           style: Theme.of(context).textTheme.bodyMedium?.copyWith(
  //             color: Colors.grey,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _buildChatsTab() {
    if (_loading) {
      return const LoadingState(message: 'Loading chats...');
    }
    
    return Column(
      children: [
        // Search bar (sticky at top)
        _buildSearchBar(),
        
        // Chat list or empty state
        Expanded(
          child: _chats.isEmpty
              ? EmptyState(
                  message: 'No chats yet',
                  subtitle: 'Add a contact to start chatting',
                  icon: Icons.chat_bubble_outline,
                  action: GestureDetector(
                    onTap: _addContact,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_add,
                            color: Theme.of(context).colorScheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Add Contact',
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
                )
              : _filteredChats.isEmpty && _searchQuery.isNotEmpty
                  ? EmptyState(
                      message: 'No chats found',
                      subtitle: 'No results for "$_searchQuery"',
                      icon: Icons.search_off,
                    )
                  : _buildChatList(),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
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
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Search chats...',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                minLines: 1,
                maxLines: 1,
                textCapitalization: TextCapitalization.sentences,
              ),
            ),
          ),
          
          // Clear button (right side) - only shown when search is active
          if (_searchQuery.isNotEmpty) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _clearSearch,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.clear,
                  color: Theme.of(context).colorScheme.primary,
                  size: 18,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Profile Header (Instagram-style)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Profile Image
                GestureDetector(
                  onTap: _showProfileImageFullscreen,
                  child: Stack(
                    children: [
                      Hero(
                        tag: 'profile_image',
                        child: CircleAvatar(
                          key: ValueKey(_profileImagePath), // Force rebuild when image changes
                          radius: 40,
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          backgroundImage: _profileImagePath != null
                              ? FileImage(File(_profileImagePath!))
                              : null,
                          child: _profileImagePath == null
                              ? Text(
                                  _userName.isNotEmpty && _userName != 'Me'
                                      ? _userName[0].toUpperCase()
                                      : 'M',
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      // Camera icon indicator
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Stats as Tabs
                Expanded(
                  child: Column(
                    children: [
                      const TabBar(
                        dividerHeight: 0,
                        labelPadding: EdgeInsets.symmetric(horizontal: 8),
                        labelStyle: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        unselectedLabelStyle: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        tabs: [
                          Tab(text: 'Contacts'),
                          Tab(text: 'Assets'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 0.5,
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Contacts/Assets Content
          if (_loadingContacts)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else
            Expanded(
              child: TabBarView(
                children: [
                  // Contacts Tab
                  _contacts.isEmpty
                      ? EmptyState(
                          message: 'No contacts yet',
                          subtitle: 'Add your first contact to start chatting',
                          icon: Icons.person_add_outlined,
                          action: GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => const AddContactScreen(),
                                ),
                              ).then((_) => _loadContacts());
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.person_add,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Add Contact',
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
                        )
                      : ListView.separated(
                          itemCount: _contacts.length,
                          itemBuilder: (context, index) {
                            return _buildContactListItem(_contacts[index]);
                          },
                          separatorBuilder: (context, index) {
                            return Divider(
                              height: 1,
                              thickness: 0.5,
                              indent: 72,
                              endIndent: 16,
                              color: Theme.of(context).dividerColor.withOpacity(0.3),
                            );
                          },
                        ),
                  // Assets Tab
                  EmptyState(
                    message: 'No assets yet',
                    subtitle: 'Your digital assets will appear here',
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
  
  /// Build contact list item for Me tab
  Widget _buildContactListItem(Contact contact) {
    final profileImage = _profileImageCache[contact.peerID];
    final isBlocked = contact.isBlocked;
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: isBlocked 
            ? Colors.grey.shade400 
            : Theme.of(context).colorScheme.primary,
        backgroundImage: profileImage != null ? FileImage(profileImage) : null,
        child: profileImage == null
            ? Text(
                contact.displayName.isNotEmpty
                    ? contact.displayName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              )
            : null,
      ),
      title: Text(
        contact.displayName,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isBlocked ? Colors.grey : null,
        ),
      ),
      subtitle: contact.isKMNodeContact
          ? Row(
              children: [
                Icon(Icons.verified, size: 14, color: Colors.blue.shade600),
                const SizedBox(width: 4),
                Text(
                  'Key Manager',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade600,
                  ),
                ),
              ],
            )
          : (isBlocked
              ? const Text(
                  'Blocked',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                )
              : null),
      trailing: isBlocked
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.message_outlined, size: 20),
                  tooltip: 'Message',
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(
                          peerID: contact.peerID,
                          contactName: contact.displayName,
                        ),
                      ),
                    );
                  },
                ),
                // TODO(coming-soon): Call button — re-enable when call feature ships
                // IconButton(
                //   icon: const Icon(Icons.phone_outlined, size: 20),
                //   tooltip: 'Call',
                //   color: Colors.green,
                //   onPressed: () => _initiateCallFromContact(contact),
                // ),
              ],
            ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ContactDetailScreen(peerID: contact.peerID),
          ),
        ).then((contactChanged) {
          // Reload contacts and chats if contact was blocked/unblocked
          _loadContacts();
          if (contactChanged == true) {
            _loadChatsLocal();
          }
        });
      },
    );
  }
  
  // TODO(coming-soon): _initiateCallFromContact — re-enable when call feature ships
  // Future<void> _initiateCallFromContact(Contact contact) async { ... }

  Widget _buildTabTitleWithNetwork(String title, {bool showEdit = false}) {
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (showEdit) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      // Stop propagation to parent InkWell
                      _editUserName();
                    },
                    child: Icon(
                      Icons.edit,
                      size: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
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

  /// Show network selector dialog (Public Network + Private Networks)
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
                            final created = await Navigator.push<bool>(
                              scaffoldContext,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const CreatePrivateNetworkScreen(),
                              ),
                            );
                            if (created == true && mounted) {
                              _loadChatsLocal();
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
                            
                            // CRITICAL: Reload chats for new network
                            _loadChatsLocal();
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

                              // CRITICAL: Reload chats for new network
                              _loadChatsLocal();
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

  Widget? _buildMeTabLeading() {
    return IconButton(
      icon: const Icon(Icons.qr_code),
      tooltip: 'My QR Code',
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const ShowMyQrCodeScreen(),
          ),
        );
      },
    );
  }

  List<Widget> _buildChatActions() {
    return [
      IconButton(
        icon: const Icon(Icons.person_add),
        tooltip: 'Add Contact',
        onPressed: _addContact,
      ),
    ];
  }

  List<Widget> _buildCommonActions() {
    return [
      IconButton(
        icon: const Icon(Icons.settings),
        tooltip: 'Settings',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const SettingsScreen(),
            ),
          ).then((contactsChanged) {
            // Reload user name in case it was changed
            _loadUserName();
            
            // Reload contacts and chats if any contact was unblocked
            if (contactsChanged == true) {
              _loadContacts();
              _loadChatsLocal();
            }
          });
        },
      ),
    ];
  }

  Widget _buildChatList() {
    return ListView.separated(
      itemCount: _filteredChats.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final chat = _filteredChats[index];
        // Use cached profile image instead of FutureBuilder to avoid re-loading on every build
        final profileImageFile = _profileImageCache[chat.peerID];
        
        return Dismissible(
          key: ValueKey(chat.peerID),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            // Only show confirmation dialog and delete messages
            // Don't modify state here to avoid race conditions
            return await _confirmDeleteChat(chat);
          },
          onDismissed: (direction) {
            // After Dismissible animation completes, update our lists
            setState(() {
              _chats.removeWhere((c) => c.peerID == chat.peerID);
              _filteredChats.removeWhere((c) => c.peerID == chat.peerID);
            });
          },
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(
              Icons.delete_outline,
              color: Colors.white,
              size: 28,
            ),
          ),
          child: InkWell(
            onTap: () => _openChat(chat),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: (_contactCache[chat.peerID]?.isKMNodeContact ?? false)
                        ? Colors.transparent
                        : null,
                    backgroundImage: (_contactCache[chat.peerID]?.isKMNodeContact ?? false)
                        ? const AssetImage('assets/images/logo.png')
                        : ((profileImageFile != null)
                            ? FileImage(profileImageFile)
                            : null),
                    child: (!(_contactCache[chat.peerID]?.isKMNodeContact ?? false) && profileImageFile == null)
                        ? Text(chat.name[0].toUpperCase())
                        : null,
                  ),
                  const SizedBox(width: 12),
                  // Name and message
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                chat.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getLastMessagePreview(chat.lastMessage),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontStyle: chat.lastMessage == null ? FontStyle.italic : FontStyle.normal,
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Time and badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatChatTime(chat.lastActivity),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      if (chat.unreadCount > 0) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${chat.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _getLastMessagePreview(Message? message) {
    if (message == null) {
      return 'No messages yet - Tap to start chatting';
    }
    
    // Handle audio messages
    if (message.contentType == ContentType.audio) {
      final durationSeconds = int.tryParse(message.contentMeta?['duration'] ?? '0') ?? 0;
      return '🎤 Voice message (${durationSeconds}s)';
    }
    
    // Handle image messages
    if (message.contentType == ContentType.image) {
      return '📷 Image';
    }
    
    // Handle file messages
    if (message.contentType == ContentType.file) {
      return '📎 File';
    }
    
    // Handle contact messages
    if (message.contentType == ContentType.contact) {
      return '👤 Contact';
    }
    
    // Handle profile update messages
    if (message.contentType == ContentType.profile_update) {
      return '👤 Profile updated';
    }
    
    // Default: text message
    return message.plaintext ?? '[Encrypted]';
  }

  String _formatChatTime(DateTime dateTime) {
    // Convert UTC time to local time
    final localTime = dateTime.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final chatDate = DateTime(localTime.year, localTime.month, localTime.day);
    
    if (chatDate == today) {
      // Today: show time (e.g. "14:30")
      return DateFormat('HH:mm').format(localTime);
    } else if (chatDate == yesterday) {
      // Yesterday
      return 'Yesterday';
    } else if (now.difference(localTime).inDays < 7) {
      // This week: show weekday (e.g. "Monday")
      return DateFormat('EEEE').format(localTime);
    } else {
      // Older: show date (e.g. "12.03")
      return DateFormat('dd.MM').format(localTime);
    }
  }

  Future<bool> _confirmDeleteChat(Chat chat) async {
    // Show bottom sheet with 2 options
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Actions for ${chat.name}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'What would you like to do?',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, null),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            
            // Option 1: Clean Chat
            InkWell(
              onTap: () => Navigator.pop(context, 'clean'),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.cleaning_services, size: 28),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Clean Chat',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Delete all messages',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const Divider(height: 1),
            
            // Option 2: Block Contact
            InkWell(
              onTap: () => Navigator.pop(context, 'block'),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.block, size: 28, color: Colors.red.shade700),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Block Contact',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.red.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Block contact and hide from Chats',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
    
    if (action == null || !mounted) return false;
    
    try {
      switch (action) {
        case 'clean':
          return await _handleCleanChat(chat);
        case 'block':
          return await _handleBlockContact(chat);
        default:
          return false;
      }
    } catch (e) {
      if (!mounted) return false;
      showTopNotification(
        context,
        'Action failed: $e',
        isError: true,
      );
      return false;
    }
  }
  
  /// Handle "Clean Chat" - delete all messages
  Future<bool> _handleCleanChat(Chat chat) async {
    // Get all messages for this peer
    final messagesResult = await _storageService.getMessagesForPeer(chat.peerID);
    final messages = messagesResult.valueOrNull ?? [];
    
    // Delete each message from database
    for (final message in messages) {
      await _storageService.deleteMessage(message.id);
    }
    
    if (!mounted) return false;
    
    showTopNotification(
      context,
      'Chat cleaned - ${messages.length} messages deleted',
    );
    
    return true; // Remove from UI list
  }
  
  /// Handle "Block Contact" - block and remove from Chats tab
  Future<bool> _handleBlockContact(Chat chat) async {
    // Block contact (sends notification)
    await _p2pService.blockContact(chat.peerID);
    
    if (!mounted) return false;
    
    showTopNotification(
      context,
      'Contact blocked - moved to Blocked tab',
    );
    
    // Reload chats and contacts to remove blocked contact from lists
    _loadChatsLocal();
    _loadContacts();
    return false; // Let reload methods handle UI update
  }

  void _openChat(Chat chat) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          peerID: chat.peerID,
          contactName: chat.name,
        ),
      ),
    );
    _loadChatsLocal(); // Refresh after returning
  }

  void _addContact() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddContactScreen(),
      ),
    );

    if (result == true) {
      _loadChatsLocal();
      // Automatically sync after adding contact to check for incoming key exchange
      Logger.debug('Auto-syncing after add contact...');
      _syncMessagesFromNetwork();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    _messageSubscription?.cancel();
    _chatUpdateSubscription?.cancel();
    _reloadDebounceTimer?.cancel();
    _searchDebounceTimer?.cancel();
    
    // Remove network listener
    _networkService?.removeListener(_onNetworkChanged);
    
    super.dispose();
  }
}
